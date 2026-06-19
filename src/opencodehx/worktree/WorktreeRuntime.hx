package opencodehx.worktree;

import opencodehx.externs.node.Fs;
import opencodehx.git.Git;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectInfo;
import opencodehx.project.ProjectRuntime.ProjectVcs;

using StringTools;

typedef WorktreeInfo = {
	final name:String;
	final branch:String;
	final directory:String;
}

enum abstract WorktreeEventType(String) to String {
	var Ready = "worktree.ready";
	var Failed = "worktree.failed";
}

typedef WorktreeEvent = {
	final type:WorktreeEventType;
	final name:String;
	final branch:String;
	@:optional final message:String;
}

typedef WorktreeEventListener = WorktreeEvent->Void;
typedef WorktreeEventUnsubscribe = Void->Void;

private typedef WorktreeListEntry = {
	final path:String;
	@:optional final branch:String;
}

class WorktreeRuntime {
	static final MAX_NAME_ATTEMPTS = 26;
	static final history:Array<WorktreeEvent> = [];
	static final listeners:Array<WorktreeEventListener> = [];

	public static function resetEvents():Void {
		history.resize(0);
		listeners.resize(0);
	}

	public static function events():Array<WorktreeEvent> {
		return history.copy();
	}

	public static function subscribe(listener:WorktreeEventListener):WorktreeEventUnsubscribe {
		listeners.push(listener);
		var active = true;
		return () -> {
			if (!active)
				return;
			active = false;
			listeners.remove(listener);
		};
	}

	public static function makeWorktreeInfo(project:ProjectInfo, ?name:String):WorktreeInfo {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final root = NodePath.join(NodePath.join(NodePath.join(project.worktree, ".opencode"), "worktree"), project.id.toString());
		Fs.mkdirSync(root, {recursive: true});
		final base = name == null || name.trim() == "" ? "workspace" : slugify(name);
		for (attempt in 0...MAX_NAME_ATTEMPTS) {
			final value = attempt == 0 ? base : '${base}-${attempt + 1}';
			final branch = 'opencode/${value}';
			final directory = NodePath.join(root, value);
			if (Fs.existsSync(directory) || branchExists(project, branch))
				continue;
			return {
				name: value,
				branch: branch,
				directory: directory,
			};
		}
		throw "Failed to generate a unique worktree name";
	}

	public static function create(project:ProjectInfo, info:WorktreeInfo, ?startCommand:String):WorktreeInfo {
		createFromInfo(project, info, startCommand);
		return info;
	}

	public static function createFromInfo(project:ProjectInfo, info:WorktreeInfo, ?startCommand:String):Void {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final result = Git.run(project.worktree, ["worktree", "add", "--no-checkout", "-b", info.branch, info.directory]);
		if (result.code != 0)
			throw result.stderr.trim() == "" ? "Failed to create git worktree" : result.stderr.trim();
		ProjectRuntime.addSandbox(project.id, info.directory);
		final populated = Git.run(info.directory, ["reset", "--hard"]);
		if (populated.code != 0) {
			publish({
				type: Failed,
				name: info.name,
				branch: info.branch,
				message: message(populated, "Failed to populate worktree")
			});
			return;
		}
		publish({type: Ready, name: info.name, branch: info.branch});
		runStartScripts(project, info, startCommand);
	}

	public static function remove(project:ProjectInfo, directory:String):Bool {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final target = canonical(directory);
		final entry = findEntry(project.worktree, target);
		if (entry == null) {
			if (Fs.existsSync(directory)) {
				stopFsmonitor(directory);
				cleanDirectory(directory);
			}
			ProjectRuntime.removeSandbox(project.id, directory);
			return true;
		}

		stopFsmonitor(entry.path);
		final removed = Git.run(project.worktree, ["worktree", "remove", "--force", entry.path]);
		if (removed.code != 0 && findEntry(project.worktree, target) != null)
			throw message(removed, "Failed to remove git worktree");
		cleanDirectory(entry.path);
		if (entry.branch != null && entry.branch.startsWith("refs/heads/")) {
			final branch = entry.branch.substr("refs/heads/".length);
			final deleted = Git.run(project.worktree, ["branch", "-D", branch]);
			if (deleted.code != 0)
				throw message(deleted, "Failed to delete worktree branch");
		}
		ProjectRuntime.removeSandbox(project.id, directory);
		return true;
	}

	public static function reset(project:ProjectInfo, directory:String):Bool {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final target = canonical(directory);
		if (target == canonical(project.worktree))
			throw "Cannot reset the primary workspace";
		final entry = findEntry(project.worktree, target);
		if (entry == null)
			throw "Worktree not found";
		final base = Git.defaultBranch(project.worktree);
		if (base == null)
			throw "Default branch not found";
		final sep = base.ref.indexOf("/");
		if (base.ref != base.name && sep > 0) {
			final remote = base.ref.substr(0, sep);
			final branch = base.ref.substr(sep + 1);
			final fetched = Git.run(project.worktree, ["fetch", remote, branch]);
			if (fetched.code != 0)
				throw message(fetched, 'Failed to fetch ${base.ref}');
		}
		expect(Git.run(entry.path, ["reset", "--hard", base.ref]), "Failed to reset worktree to target");
		expect(Git.run(entry.path, ["clean", "-ffdx"]), "Failed to clean worktree");
		expect(Git.run(entry.path, ["submodule", "update", "--init", "--recursive", "--force"]), "Failed to update submodules");
		expect(Git.run(entry.path, ["submodule", "foreach", "--recursive", "git", "reset", "--hard"]), "Failed to reset submodules");
		expect(Git.run(entry.path, ["submodule", "foreach", "--recursive", "git", "clean", "-fdx"]), "Failed to clean submodules");
		final status = Git.run(entry.path, ["-c", "core.fsmonitor=false", "status", "--porcelain=v1"]);
		if (status.code != 0)
			throw message(status, "Failed to read git status");
		if (status.stdout.trim() != "")
			throw 'Worktree reset left local changes:\n${status.stdout.trim()}';
		return true;
	}

	static function findEntry(cwd:String, target:String):Null<WorktreeListEntry> {
		final result = Git.run(cwd, ["worktree", "list", "--porcelain"]);
		if (result.code != 0)
			throw message(result, "Failed to read git worktrees");
		for (entry in parseList(result.stdout)) {
			if (canonical(entry.path) == target)
				return entry;
		}
		return null;
	}

	static function parseList(text:String):Array<WorktreeListEntry> {
		final out:Array<WorktreeListEntry> = [];
		var path:Null<String> = null;
		var branch:Null<String> = null;
		function flush():Void {
			if (path != null) {
				out.push({path: path, branch: branch});
				path = null;
				branch = null;
			}
		}
		for (line in text.split("\n")) {
			final value = line.trim();
			if (value == "")
				continue;
			if (value.startsWith("worktree ")) {
				flush();
				path = value.substr("worktree ".length);
			} else if (path != null && value.startsWith("branch ")) {
				branch = value.substr("branch ".length);
			}
		}
		flush();
		return out;
	}

	static function canonical(path:String):String {
		final resolved = NodePath.normalize(NodePath.resolve(path, ""));
		final normalized = Fs.existsSync(resolved) ? NodePath.normalize(Fs.realpathSync(resolved)) : resolved;
		return NodeProcessPlatform.isWindows() ? normalized.toLowerCase() : normalized;
	}

	static function branchExists(project:ProjectInfo, branch:String):Bool {
		return Git.run(project.worktree, ["show-ref", "--verify", "--quiet", 'refs/heads/${branch}']).code == 0;
	}

	static function stopFsmonitor(directory:String):Void {
		if (Fs.existsSync(directory))
			Git.run(directory, ["fsmonitor--daemon", "stop"]);
	}

	static function cleanDirectory(directory:String):Void {
		if (Fs.existsSync(directory))
			Fs.rmSync(directory, {recursive: true, force: true});
	}

	static function runStartScripts(project:ProjectInfo, info:WorktreeInfo, ?extra:String):Void {
		if (project.commands != null && project.commands.start != null)
			runStartScript(project, info, project.commands.start);
		if (extra != null)
			runStartScript(project, info, extra);
	}

	static function runStartScript(project:ProjectInfo, info:WorktreeInfo, command:String):Bool {
		final text = command.trim();
		if (text == "")
			return true;
		final result = NodeProcess.runShell({
			command: text,
			cwd: info.directory,
			env: NodeProcess.env(),
			timeout: 30 * 1000,
			maxBuffer: 1024 * 1024,
		});
		if (result.status == 0)
			return true;
		publish({
			type: Failed,
			name: info.name,
			branch: info.branch,
			message: message(result, 'Failed to run worktree start command for ${project.id.toString()}')
		});
		return false;
	}

	static function expect(result:opencodehx.git.Git.GitRunResult, fallback:String):Void {
		if (result.code != 0)
			throw message(result, fallback);
	}

	static function message(result:{final stdout:String; final stderr:String;}, fallback:String):String {
		final stderr = result.stderr.trim();
		if (stderr != "")
			return stderr;
		final stdout = result.stdout.trim();
		return stdout == "" ? fallback : stdout;
	}

	static function publish(event:WorktreeEvent):Void {
		history.push(event);
		for (listener in listeners.copy()) {
			listener(event);
		}
	}

	static function slugify(input:String):String {
		var value = input.trim().toLowerCase();
		value = new EReg("[^a-z0-9]+", "g").replace(value, "-");
		value = new EReg("^-+", "").replace(value, "");
		value = new EReg("-+$", "").replace(value, "");
		return value == "" ? "workspace" : value;
	}
}

private class NodeProcessPlatform {
	public static function isWindows():Bool {
		return opencodehx.host.node.NodeProcess.platform() == "win32";
	}
}
