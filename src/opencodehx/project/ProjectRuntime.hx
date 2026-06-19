package opencodehx.project;

import js.Syntax;
import opencodehx.externs.node.Fs;
import opencodehx.git.Git;
import opencodehx.host.node.NodePath;

using StringTools;

abstract ProjectID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):ProjectID {
		return new ProjectID(value);
	}

	public static inline function global():ProjectID {
		return new ProjectID("global");
	}

	public inline function toString():String {
		return this;
	}
}

enum abstract ProjectVcs(String) to String {
	var GitVcs = "git";
}

typedef ProjectIcon = {
	@:optional final url:String;
	@:optional final color:String;
}

typedef ProjectCommands = {
	@:optional final start:String;
}

typedef ProjectTime = {
	final created:Float;
	final updated:Float;
	@:optional final initialized:Float;
}

typedef ProjectInfo = {
	final id:ProjectID;
	final worktree:String;
	@:optional final vcs:ProjectVcs;
	@:optional final name:String;
	@:optional final icon:ProjectIcon;
	@:optional final commands:ProjectCommands;
	final time:ProjectTime;
	final sandboxes:Array<String>;
}

typedef ProjectDiscovery = {
	final project:ProjectInfo;
	final sandbox:String;
}

typedef ProjectUpdate = {
	final projectID:ProjectID;
	@:optional final name:String;
	@:optional final icon:ProjectIcon;
	@:optional final commands:ProjectCommands;
}

private typedef DiscoveryData = {
	final id:ProjectID;
	final worktree:String;
	final sandbox:String;
	final vcs:Null<ProjectVcs>;
}

class ProjectRuntime {
	static final projects:Array<ProjectInfo> = [];

	public static function reset():Void {
		projects.resize(0);
	}

	public static function fromDirectory(directory:String):ProjectDiscovery {
		final data = discover(directory);
		final project = upsertDiscovered(data);
		return {project: project, sandbox: data.sandbox};
	}

	public static function list():Array<ProjectInfo> {
		return projects.copy();
	}

	public static function get(id:ProjectID):Null<ProjectInfo> {
		final index = findIndex(id);
		return index == -1 ? null : projects[index];
	}

	public static function update(input:ProjectUpdate):ProjectInfo {
		final current = get(input.projectID);
		if (current == null)
			throw 'Project not found: ${input.projectID.toString()}';
		final now = timestamp();
		final next:ProjectInfo = {
			id: current.id,
			worktree: current.worktree,
			vcs: current.vcs,
			name: input.name == null ? current.name : input.name,
			icon: input.icon == null ? current.icon : input.icon,
			commands: input.commands == null ? current.commands : input.commands,
			time: {
				created: current.time.created,
				updated: now,
				initialized: current.time.initialized,
			},
			sandboxes: current.sandboxes.copy(),
		};
		replace(next);
		return next;
	}

	public static function setInitialized(id:ProjectID):Void {
		final current = get(id);
		if (current == null)
			throw 'Project not found: ${id.toString()}';
		final now = timestamp();
		replace({
			id: current.id,
			worktree: current.worktree,
			vcs: current.vcs,
			name: current.name,
			icon: current.icon,
			commands: current.commands,
			time: {
				created: current.time.created,
				updated: now,
				initialized: now,
			},
			sandboxes: current.sandboxes.copy(),
		});
	}

	public static function addSandbox(id:ProjectID, directory:String):Void {
		final current = get(id);
		if (current == null)
			throw 'Project not found: ${id.toString()}';
		final normalized = realpath(directory);
		final sandboxes = current.sandboxes.copy();
		if (sandboxes.indexOf(normalized) == -1 && normalized != realpath(current.worktree))
			sandboxes.push(normalized);
		replace({
			id: current.id,
			worktree: current.worktree,
			vcs: current.vcs,
			name: current.name,
			icon: current.icon,
			commands: current.commands,
			time: current.time,
			sandboxes: sandboxes,
		});
	}

	public static function removeSandbox(id:ProjectID, directory:String):Void {
		final current = get(id);
		if (current == null)
			throw 'Project not found: ${id.toString()}';
		final normalized = realpath(directory);
		replace({
			id: current.id,
			worktree: current.worktree,
			vcs: current.vcs,
			name: current.name,
			icon: current.icon,
			commands: current.commands,
			time: current.time,
			sandboxes: current.sandboxes.filter(item -> realpath(item) != normalized),
		});
	}

	static function discover(directory:String):DiscoveryData {
		final start = realpath(NodePath.resolve(directory, ""));
		final dotgit = findGitMarker(start);
		if (dotgit == null) {
			return {
				id: ProjectID.global(),
				worktree: "/",
				sandbox: "/",
				vcs: null,
			};
		}

		var sandbox = realpath(NodePath.dirname(dotgit));
		var id = readCachedProjectID(dotgit);

		final commonDir = Git.run(sandbox, ["rev-parse", "--git-common-dir"]);
		if (commonDir.code != 0) {
			return {
				id: id == null ? ProjectID.global() : id,
				worktree: sandbox,
				sandbox: sandbox,
				vcs: null,
			};
		}

		final common = realpath(resolveGitPath(sandbox, commonDir.stdout));
		if (id == null)
			id = readCachedProjectID(common);

		final bareCheck = Git.run(sandbox, ["config", "--bool", "core.bare"]);
		final isBare = bareCheck.code == 0 && bareCheck.stdout.trim() == "true";
		final worktree = common == sandbox ? sandbox : (isBare ? common : realpath(NodePath.dirname(common)));

		if (id == null) {
			final roots = Git.run(sandbox, ["rev-list", "--max-parents=0", "HEAD"])
				.stdout.split("\n")
				.map(item -> item.trim())
				.filter(item -> item != "");
			roots.sort((a, b) -> Reflect.compare(a, b));
			if (roots.length > 0) {
				id = ProjectID.make(roots[0]);
				writeCachedProjectID(common, id);
			}
		}

		if (id == null) {
			return {
				id: ProjectID.global(),
				worktree: sandbox,
				sandbox: sandbox,
				vcs: GitVcs,
			};
		}

		final topLevel = Git.run(sandbox, ["rev-parse", "--show-toplevel"]);
		if (topLevel.code == 0)
			sandbox = realpath(resolveGitPath(sandbox, topLevel.stdout));

		return {
			id: id,
			worktree: worktree,
			sandbox: sandbox,
			vcs: GitVcs,
		};
	}

	static function upsertDiscovered(data:DiscoveryData):ProjectInfo {
		final now = timestamp();
		final existing = get(data.id);
		final sandboxes = existing == null ? [] : existing.sandboxes.copy();
		final worktree = realpath(data.worktree);
		final normalizedSandbox = realpath(data.sandbox);
		if (data.id.toString() != ProjectID.global().toString()
			&& normalizedSandbox != worktree
			&& sandboxes.indexOf(normalizedSandbox) == -1) {
			sandboxes.push(normalizedSandbox);
		}
		final next:ProjectInfo = {
			id: data.id,
			worktree: worktree,
			vcs: data.vcs,
			name: existing == null ? null : existing.name,
			icon: existing == null ? null : existing.icon,
			commands: existing == null ? null : existing.commands,
			time: existing == null ? {
				created: now,
				updated: now
			} : {
				created: existing.time.created,
				updated: now,
				initialized: existing.time.initialized,
			},
			sandboxes: sandboxes,
		};
		replace(next);
		return next;
	}

	static function findGitMarker(directory:String):Null<String> {
		var current = NodePath.resolve(directory, "");
		while (true) {
			final marker = NodePath.join(current, ".git");
			if (Fs.existsSync(marker))
				return marker;
			final parent = NodePath.dirname(current);
			if (parent == current)
				return null;
			current = parent;
		}
	}

	static function readCachedProjectID(dir:String):Null<ProjectID> {
		if (!Fs.existsSync(dir) || !Fs.statSync(dir).isDirectory())
			return null;
		final file = NodePath.join(dir, "opencode");
		if (!Fs.existsSync(file) || !Fs.statSync(file).isFile())
			return null;
		final value = Fs.readFileSync(file, "utf8").trim();
		return value == "" ? null : ProjectID.make(value);
	}

	static function writeCachedProjectID(dir:String, id:ProjectID):Void {
		if (Fs.existsSync(dir) && Fs.statSync(dir).isDirectory())
			Fs.writeFileSync(NodePath.join(dir, "opencode"), id.toString(), "utf8");
	}

	static function resolveGitPath(cwd:String, raw:String):String {
		final name = raw.trim();
		if (name == "")
			return cwd;
		if (NodePath.isAbsolute(name))
			return NodePath.normalize(name);
		return NodePath.normalize(NodePath.resolve(cwd, name));
	}

	static function realpath(path:String):String {
		final normalized = NodePath.normalize(path);
		return Fs.existsSync(normalized) ? NodePath.normalize(Fs.realpathSync(normalized)) : normalized;
	}

	static function replace(project:ProjectInfo):Void {
		final index = findIndex(project.id);
		if (index == -1)
			projects.push(project);
		else
			projects[index] = project;
	}

	static function findIndex(id:ProjectID):Int {
		for (index in 0...projects.length) {
			if (projects[index].id.toString() == id.toString())
				return index;
		}
		return -1;
	}

	static function timestamp():Float {
		return Syntax.code("Date.now()");
	}
}
