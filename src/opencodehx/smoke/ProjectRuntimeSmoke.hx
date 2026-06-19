package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.git.Git;
import opencodehx.git.Git.GitChangeKind;
import opencodehx.git.Git.GitItem;
import opencodehx.git.Git.GitStat;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.npm.Npm;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectID;
import opencodehx.project.ProjectRuntime.ProjectVcs;
import opencodehx.sync.SyncEventStore;
import opencodehx.worktree.WorktreeRuntime;

using StringTools;

typedef SmokeSyncItem = {
	final id:String;
	final name:String;
}

class ProjectRuntimeSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-project-"));
		try {
			noCommitGitProject(root);
			committedProjectAndGit(root);
			worktreeProject(root);
			npmSanitize();
			syncEvents();
			Fs.rmSync(root, {recursive: true, force: true});
			// Dynamic is required at this JS runtime cleanup boundary because Haxe code,
			// Node externs, and Git helpers may throw strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function noCommitGitProject(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "no-commit");
		git(dir, ["init"]);

		final found = ProjectRuntime.fromDirectory(dir);
		eq(found.project.id.toString(), ProjectID.global().toString(), "no-commit project id");
		eq(found.project.vcs, GitVcs, "no-commit vcs");
		eq(realpath(found.project.worktree), realpath(dir), "no-commit worktree");
		eq(Fs.existsSync(NodePath.join(NodePath.join(dir, ".git"), "opencode")), false, "no-commit cache omitted");
	}

	static function committedProjectAndGit(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "committed");
		initCommittedRepo(dir);

		final first = ProjectRuntime.fromDirectory(dir);
		final second = ProjectRuntime.fromDirectory(dir);
		neq(first.project.id.toString(), ProjectID.global().toString(), "committed project id");
		eq(second.project.id.toString(), first.project.id.toString(), "stable project id");
		eq(Fs.existsSync(NodePath.join(NodePath.join(dir, ".git"), "opencode")), true, "project id cache");
		eq(ProjectRuntime.list().length, 1, "project list count");

		ProjectRuntime.update({projectID: first.project.id, name: "Runtime Project", commands: {start: "npm run dev"}});
		eq(ProjectRuntime.get(first.project.id).name, "Runtime Project", "project update name");
		eq(ProjectRuntime.get(first.project.id).commands.start, "npm run dev", "project update command");
		ProjectRuntime.setInitialized(first.project.id);
		eq(ProjectRuntime.get(first.project.id).time.initialized != null, true, "project initialized time");

		eq(Git.branch(dir), "main", "git branch");
		eq(Git.defaultBranch(dir).name, "main", "git default branch");

		final weird = NodeProcess.platform() == "win32" ? "space file.txt" : "tab\tfile.txt";
		write(dir, weird, "before\n");
		final status = Git.status(dir);
		eq(hasGitItem(status, weird, Added), true, "git status untracked");
		git(dir, ["add", "."]);
		git(dir, [
			"-c",
			"user.email=test@example.com",
			"-c",
			"user.name=OpenCodeHX",
			"commit",
			"--no-gpg-sign",
			"-m",
			"add weird"
		]);
		write(dir, weird, "after\n");
		eq(hasGitItem(Git.diff(dir, "HEAD"), weird, Modified), true, "git diff modified");
		final stat = findStat(Git.stats(dir, "HEAD"), weird);
		eq(stat.additions, 1, "git stat additions");
		eq(stat.deletions, 1, "git stat deletions");
	}

	static function worktreeProject(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "worktree-main");
		initCommittedRepo(dir);
		final main = ProjectRuntime.fromDirectory(dir).project;
		final info = WorktreeRuntime.makeWorktreeInfo(main, "My Feature Branch!");
		eq(info.name, "my-feature-branch", "worktree slug");
		eq(info.branch, "opencode/my-feature-branch", "worktree branch");

		try {
			WorktreeRuntime.create(main, info);
			final child = ProjectRuntime.fromDirectory(info.directory);
			final expectedSandbox = realpath(info.directory);
			eq(child.project.id.toString(), main.id.toString(), "worktree shares project id");
			eq(realpath(child.sandbox), expectedSandbox, "worktree sandbox");
			eq(ProjectRuntime.get(main.id).sandboxes.indexOf(expectedSandbox) != -1, true, "worktree sandbox tracked");
			WorktreeRuntime.remove(main, info.directory);
			eq(Fs.existsSync(info.directory), false, "worktree removed");
			// Dynamic is required at this JS runtime cleanup boundary because Git
			// failures can arrive as strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			WorktreeRuntime.remove(main, info.directory);
			throw error;
		}
	}

	static function npmSanitize():Void {
		eq(Npm.sanitize("@opencode/acme"), "@opencode/acme", "scoped npm sanitize");
		eq(Npm.sanitize("@opencode/acme@1.0.0"), "@opencode/acme@1.0.0", "versioned npm sanitize");
		eq(Npm.sanitize("prettier"), "prettier", "plain npm sanitize");
		final spec = "acme@git+https://github.com/opencode/acme.git";
		final expected = NodeProcess.platform() == "win32" ? "acme@git+https_//github.com/opencode/acme.git" : spec;
		eq(Npm.sanitize(spec), expected, "git https npm sanitize");
	}

	static function syncEvents():Void {
		final store = new SyncEventStore<SmokeSyncItem>({
			type: "item.created",
			version: 1,
			aggregate: item -> item.id,
		});
		final first = store.run({id: "item_1", name: "first"});
		final second = store.run({id: "item_1", name: "second"});
		eq(first.seq, 0, "sync first seq");
		eq(second.seq, 1, "sync second seq");
		eq(store.history("item_1").length, 2, "sync history length");

		final replay = new SyncEventStore<SmokeSyncItem>({
			type: "item.created",
			version: 1,
			aggregate: item -> item.id,
		});
		final source = replay.replayAll([
			{
				id: "evt_a",
				type: "item.created.1",
				seq: 0,
				aggregateID: "item_2",
				data: {id: "item_2", name: "a"}
			},
			{
				id: "evt_b",
				type: "item.created.1",
				seq: 1,
				aggregateID: "item_2",
				data: {id: "item_2", name: "b"}
			},
		]);
		eq(source, "item_2", "sync replay source");
		expectFailure(() -> replay.replay({
			id: "evt_bad",
			type: "unknown.event.1",
			seq: 2,
			aggregateID: "item_2",
			data: {id: "item_2", name: "bad"}
		}), "Unknown event type", "sync unknown type");
		expectFailure(() -> replay.replay({
			id: "evt_gap",
			type: "item.created.1",
			seq: 5,
			aggregateID: "item_2",
			data: {id: "item_2", name: "gap"}
		}), "Sequence mismatch", "sync sequence mismatch");
	}

	static function initCommittedRepo(dir:String):Void {
		git(dir, ["init"]);
		git(dir, ["branch", "-M", "main"]);
		write(dir, "README.md", "# fixture\n");
		git(dir, ["add", "."]);
		git(dir, [
			"-c",
			"user.email=test@example.com",
			"-c",
			"user.name=OpenCodeHX",
			"commit",
			"--no-gpg-sign",
			"-m",
			"initial"
		]);
		git(dir, ["config", "init.defaultBranch", "main"]);
	}

	static function git(cwd:String, args:Array<String>):Void {
		final result = Git.run(cwd, args);
		if (result.code != 0)
			throw result.stderr.trim() == "" ? 'git ${args.join(" ")} failed with code ${result.code}' : result.stderr.trim();
	}

	static function directory(root:String, name:String):String {
		final dir = NodePath.join(root, name);
		Fs.mkdirSync(dir, {recursive: true});
		return dir;
	}

	static function write(dir:String, name:String, data:String):Void {
		final file = NodePath.join(dir, name);
		Fs.mkdirSync(NodePath.dirname(file), {recursive: true});
		Fs.writeFileSync(file, data, "utf8");
	}

	static function realpath(path:String):String {
		final normalized = NodePath.normalize(path);
		return Fs.existsSync(normalized) ? NodePath.normalize(Fs.realpathSync(normalized)) : normalized;
	}

	static function hasGitItem(items:Array<GitItem>, file:String, kind:GitChangeKind):Bool {
		for (item in items) {
			if (item.file == file && item.status == kind)
				return true;
		}
		return false;
	}

	static function findStat(items:Array<GitStat>, file:String):GitStat {
		for (item in items) {
			if (item.file == file)
				return item;
		}
		throw 'missing git stat for ${file}';
	}

	static function expectFailure(run:() -> Void, contains:String, label:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(contains) != -1)
				return;
		}
		throw '${label}: expected failure containing ${contains}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}

	static function neq<T>(actual:T, expected:T, label:String):Void {
		if (actual == expected)
			throw '${label}: did not expect ${expected}';
	}
}
