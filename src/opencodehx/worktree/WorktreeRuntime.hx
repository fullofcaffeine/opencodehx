package opencodehx.worktree;

import opencodehx.externs.node.Fs;
import opencodehx.git.Git;
import opencodehx.host.node.NodePath;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectInfo;
import opencodehx.project.ProjectRuntime.ProjectVcs;

using StringTools;

typedef WorktreeInfo = {
	final name:String;
	final branch:String;
	final directory:String;
}

private typedef WorktreeListEntry = {
	final path:String;
	@:optional final branch:String;
}

class WorktreeRuntime {
	public static function makeWorktreeInfo(project:ProjectInfo, ?name:String):WorktreeInfo {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final value = name == null || name.trim() == "" ? "workspace" : slugify(name);
		final root = NodePath.join(NodePath.join(NodePath.join(project.worktree, ".opencode"), "worktree"), project.id.toString());
		Fs.mkdirSync(root, {recursive: true});
		final directory = NodePath.join(root, value);
		return {
			name: value,
			branch: 'opencode/${value}',
			directory: directory,
		};
	}

	public static function create(project:ProjectInfo, info:WorktreeInfo):WorktreeInfo {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final result = Git.run(project.worktree, ["worktree", "add", "-b", info.branch, info.directory, "HEAD"]);
		if (result.code != 0)
			throw result.stderr.trim() == "" ? "Failed to create git worktree" : result.stderr.trim();
		ProjectRuntime.addSandbox(project.id, info.directory);
		return info;
	}

	public static function remove(project:ProjectInfo, directory:String):Bool {
		if (project.vcs != GitVcs)
			throw "Worktrees are only supported for git projects";
		final target = canonical(directory);
		final entry = findEntry(project.worktree, target);
		if (entry == null) {
			if (Fs.existsSync(directory))
				Fs.rmSync(directory, {recursive: true, force: true});
			ProjectRuntime.removeSandbox(project.id, directory);
			return true;
		}

		final removed = Git.run(project.worktree, ["worktree", "remove", "--force", entry.path]);
		if (removed.code != 0)
			throw removed.stderr.trim() == "" ? "Failed to remove git worktree" : removed.stderr.trim();
		if (Fs.existsSync(entry.path))
			Fs.rmSync(entry.path, {recursive: true, force: true});
		if (entry.branch != null && entry.branch.startsWith("refs/heads/")) {
			final branch = entry.branch.substr("refs/heads/".length);
			Git.run(project.worktree, ["branch", "-D", branch]);
		}
		ProjectRuntime.removeSandbox(project.id, directory);
		return true;
	}

	static function findEntry(cwd:String, target:String):Null<WorktreeListEntry> {
		for (entry in parseList(Git.run(cwd, ["worktree", "list", "--porcelain"]).stdout)) {
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
