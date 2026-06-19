package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.bus.EventBus;
import opencodehx.file.FileWatcherRuntime.FileUpdatedEvent;
import opencodehx.file.FileWatcherRuntime.FileWatchEventType;
import opencodehx.git.Git;
import opencodehx.git.Git.GitChangeKind;
import opencodehx.git.Git.GitItem;
import opencodehx.git.Git.GitStat;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.npm.Npm;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceEvent;
import opencodehx.project.InstanceRuntime.InstanceEventType;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectEvent;
import opencodehx.project.ProjectRuntime.ProjectEventType;
import opencodehx.project.ProjectRuntime.ProjectID;
import opencodehx.project.ProjectRuntime.ProjectVcs;
import opencodehx.project.VcsRuntime;
import opencodehx.project.VcsRuntime.VcsDiffMode;
import opencodehx.project.VcsRuntime.VcsEvent;
import opencodehx.project.VcsRuntime.VcsEventType;
import opencodehx.project.VcsRuntime.VcsFileDiff;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.sync.SyncEventStore;
import opencodehx.worktree.WorktreeRuntime.WorktreeEvent;
import opencodehx.worktree.WorktreeRuntime.WorktreeEventType;
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
			vcsDiffs(root);
			projectEdges(root);
			projectGlobalMigration(root);
			worktreeProject(root);
			worktreeEdges(root);
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
		vcsEvents(dir);

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

	static function projectEdges(root:String):Void {
		ProjectRuntime.reset();
		final plain = directory(root, "plain-project");
		final global = ProjectRuntime.fromDirectory(plain).project;
		eq(global.id.toString(), ProjectID.global().toString(), "non-git project id");
		final initialized = ProjectRuntime.initGit(plain, global);
		eq(initialized.vcs, GitVcs, "initGit vcs");
		eq(Fs.existsSync(NodePath.join(plain, ".git")), true, "initGit created .git");

		final events:Array<ProjectEvent> = [];
		final unsubscribe = ProjectRuntime.subscribe(event -> events.push(event));
		ProjectRuntime.update({projectID: initialized.id, name: "Evented Project"});
		unsubscribe();
		eq(events.length > 0, true, "project update event emitted");
		eq(events[events.length - 1].type, Updated, "project update event type");
		eq(events[events.length - 1].project.name, "Evented Project", "project update event payload");

		ProjectRuntime.reset();
		final iconDir = directory(root, "icon-project");
		initCommittedRepo(iconDir);
		final iconProject = ProjectRuntime.fromDirectory(iconDir).project;
		write(iconDir, "favicon.png", "png fixture");
		ProjectRuntime.discover(iconProject);
		eq(ProjectRuntime.get(iconProject.id).icon.url.startsWith("data:image/png;base64,"), true, "favicon data url");

		final sandboxDir = NodePath.join(iconDir, "missing-sandbox");
		ProjectRuntime.addSandbox(iconProject.id, sandboxDir);
		eq(ProjectRuntime.get(iconProject.id).sandboxes.indexOf(NodePath.normalize(sandboxDir)) != -1, true, "sandbox added before prune");
		eq(ProjectRuntime.sandboxes(iconProject.id).indexOf(NodePath.normalize(sandboxDir)) == -1, true, "missing sandbox pruned");

		ProjectRuntime.reset();
		final textDir = directory(root, "text-favicon-project");
		initCommittedRepo(textDir, "# text fixture\n");
		final textProject = ProjectRuntime.fromDirectory(textDir).project;
		write(textDir, "favicon.txt", "not an image");
		ProjectRuntime.discover(textProject);
		eq(ProjectRuntime.get(textProject.id).icon == null, true, "non-image favicon ignored");

		cloneProjectIDs(root);
		bareProjectCache(root);
	}

	static function vcsDiffs(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "vcs-diff");
		initCommittedRepo(dir);
		write(dir, "file.txt", "original\n");
		git(dir, ["add", "."]);
		commit(dir, "add file");
		write(dir, "file.txt", "changed\n");
		final vcs = new VcsRuntime(dir);
		eq(hasVcsDiff(vcs.diff(WorkingTree), "file.txt", Modified), true, "vcs working-tree modified diff");

		final weird = NodeProcess.platform() == "win32" ? "space file.txt" : "tab\tfile.txt";
		write(dir, weird, "hello\n");
		eq(hasVcsDiff(vcs.diff(WorkingTree), weird, Added), true, "vcs working-tree special filename diff");

		final branchDir = directory(root, "vcs-branch-diff");
		initCommittedRepo(branchDir);
		git(branchDir, ["checkout", "-b", "feature/test"]);
		write(branchDir, "branch.txt", "hello\n");
		git(branchDir, ["add", "."]);
		commit(branchDir, "branch file");
		final branchVcs = new VcsRuntime(branchDir);
		eq(hasVcsDiff(branchVcs.diff(Branch), "branch.txt", Added), true, "vcs branch diff");
	}

	static function hasVcsDiff(items:Array<VcsFileDiff>, file:String, kind:GitChangeKind):Bool {
		for (item in items) {
			if (item.file == file && item.status == kind)
				return true;
		}
		return false;
	}

	static function projectGlobalMigration(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "migrate-first-project");
		final store = new SqliteSessionStore(NodePath.join(root, "migrate-first.db"));
		try {
			git(dir, ["init"]);
			final pre = ProjectRuntime.fromDirectory(dir, store).project;
			eq(pre.id.toString(), ProjectID.global().toString(), "migration pre-commit global project");
			final sessionID = SessionID.make("ses_migrate_first");
			store.createSession(storageSession(sessionID, ProjectID.global().toString(), pre.worktree));
			commitEmpty(dir, "root");
			final real = ProjectRuntime.fromDirectory(dir, store).project;
			neq(real.id.toString(), ProjectID.global().toString(), "migration real project id");
			eq(store.getSession(sessionID).projectID, real.id.toString(), "global session migrated on first project creation");
			store.close();
			// Dynamic is required at this JS runtime cleanup boundary because SQLite,
			// Node externs, and Git helpers may throw strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			store.close();
			throw error;
		}

		ProjectRuntime.reset();
		final existingDir = directory(root, "migrate-existing-project");
		initCommittedRepo(existingDir);
		final existingStore = new SqliteSessionStore(NodePath.join(root, "migrate-existing.db"));
		try {
			final project = ProjectRuntime.fromDirectory(existingDir, existingStore).project;
			existingStore.upsertProject({id: ProjectID.global().toString(), worktree: "/"});
			final matching = SessionID.make("ses_migrate_existing");
			final empty = SessionID.make("ses_migrate_empty");
			final other = SessionID.make("ses_migrate_other");
			existingStore.createSession(storageSession(matching, ProjectID.global().toString(), project.worktree));
			existingStore.createSession(storageSession(empty, ProjectID.global().toString(), ""));
			existingStore.createSession(storageSession(other, ProjectID.global().toString(), NodePath.join(root, "unrelated")));
			ProjectRuntime.fromDirectory(existingDir, existingStore);
			eq(existingStore.getSession(matching).projectID, project.id.toString(), "global session migrated for existing project");
			eq(existingStore.getSession(empty).projectID, ProjectID.global().toString(), "empty-directory session stays global");
			eq(existingStore.getSession(other).projectID, ProjectID.global().toString(), "unrelated global session stays global");
			existingStore.close();
			// Dynamic is required at this JS runtime cleanup boundary because SQLite,
			// Node externs, and Git helpers may throw strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			existingStore.close();
			throw error;
		}
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

	static function worktreeEdges(root:String):Void {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		WorktreeRuntime.resetEvents();
		final dir = directory(root, "worktree-edges-main");
		initCommittedRepo(dir);
		final base = ProjectRuntime.fromDirectory(dir).project;
		final projectStartCommand = startMarkerCommand("project-started.txt");
		final extraStartCommand = startMarkerCommand("extra-started.txt");
		final main = ProjectRuntime.update({projectID: base.id, commands: {start: projectStartCommand}});
		final first = WorktreeRuntime.makeWorktreeInfo(main, "Repeat Name");
		Fs.mkdirSync(first.directory, {recursive: true});
		final second = WorktreeRuntime.makeWorktreeInfo(main, "Repeat Name");
		neq(second.name, first.name, "worktree unique name");
		Fs.rmSync(first.directory, {recursive: true, force: true});

		final info = WorktreeRuntime.makeWorktreeInfo(main, "Reset Me");
		final events:Array<WorktreeEvent> = [];
		final order:Array<String> = [];
		final unsubscribe = WorktreeRuntime.subscribe(event -> {
			if (event.type == Ready)
				order.push("ready");
			events.push(event);
		});
		final instanceEvents:Array<InstanceEvent> = [];
		final instanceUnsubscribe = InstanceRuntime.subscribe(event -> instanceEvents.push(event));
		final bootstrap = (context:InstanceContext) -> {
			order.push("bootstrap");
			write(context.directory, "bootstrapped.txt", context.project.id.toString());
			true;
		};
		var failedDirectory:Null<String> = null;
		var failedBootstrapDirectory:Null<String> = null;
		try {
			WorktreeRuntime.createFromInfo(main, info, extraStartCommand, bootstrap);
			unsubscribe();
			eq(events.length > 0, true, "worktree ready event emitted");
			eq(order.join(","), "bootstrap,ready", "worktree bootstrap before ready");
			eq(events[events.length - 1].type, Ready, "worktree ready event type");
			eq(events[events.length - 1].branch, info.branch, "worktree ready branch");
			eq(Fs.readFileSync(NodePath.join(info.directory, "bootstrapped.txt"), "utf8"), main.id.toString(), "worktree bootstrap context");
			final cached = InstanceRuntime.get(info.directory);
			if (cached == null)
				throw "worktree instance not cached";
			eq(cached.project.id.toString(), main.id.toString(), "worktree instance project id");
			eq(realpath(cached.worktree), realpath(info.directory), "worktree instance sandbox");
			eq(Fs.existsSync(NodePath.join(info.directory, "project-started.txt")), true, "worktree project start command");
			eq(Fs.existsSync(NodePath.join(info.directory, "extra-started.txt")), true, "worktree extra start command");

			write(info.directory, "scratch.txt", "remove me\n");
			write(info.directory, "README.md", "# changed\n");
			eq(WorktreeRuntime.reset(main, info.directory), true, "worktree reset result");
			eq(Fs.existsSync(NodePath.join(info.directory, "scratch.txt")), false, "worktree reset cleaned untracked");
			eq(Fs.readFileSync(NodePath.join(info.directory, "README.md"), "utf8"), "# fixture\n", "worktree reset restored tracked");

			eq(InstanceRuntime.dispose(info.directory), true, "worktree instance dispose result");
			instanceUnsubscribe();
			eq(instanceEvents.length, 1, "worktree instance disposed event emitted");
			eq(instanceEvents[0].type, Disposed, "worktree instance disposed event type");
			eq(instanceEvents[0].project, main.id.toString(), "worktree instance disposed project");
			eq(WorktreeRuntime.remove(main, NodePath.join(dir, "missing-worktree")), true, "missing worktree remove");
			WorktreeRuntime.remove(main, info.directory);
			final failedInfo = WorktreeRuntime.makeWorktreeInfo(main, "Bad Start");
			failedDirectory = failedInfo.directory;
			WorktreeRuntime.resetEvents();
			WorktreeRuntime.createFromInfo(main, failedInfo, "node -e \"process.exit(7)\"");
			final failure = WorktreeRuntime.events()[WorktreeRuntime.events().length - 1];
			eq(failure.type, Failed, "worktree failed event type");
			eq(failure.branch, failedInfo.branch, "worktree failed event branch");
			WorktreeRuntime.remove(main, failedInfo.directory);
			final failedBootstrapInfo = WorktreeRuntime.makeWorktreeInfo(main, "Bad Bootstrap");
			failedBootstrapDirectory = failedBootstrapInfo.directory;
			WorktreeRuntime.resetEvents();
			WorktreeRuntime.createFromInfo(main, failedBootstrapInfo, null, _ -> false);
			final bootstrapFailure = WorktreeRuntime.events()[WorktreeRuntime.events().length - 1];
			eq(bootstrapFailure.type, Failed, "worktree bootstrap failed event type");
			eq(bootstrapFailure.branch, failedBootstrapInfo.branch, "worktree bootstrap failed event branch");
			eq(InstanceRuntime.get(failedBootstrapInfo.directory) == null, true, "failed bootstrap instance not cached");
			WorktreeRuntime.remove(main, failedBootstrapInfo.directory);
			// Dynamic is required at this JS runtime cleanup boundary because Git
			// failures can arrive as strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			unsubscribe();
			instanceUnsubscribe();
			WorktreeRuntime.remove(main, info.directory);
			if (failedDirectory != null)
				WorktreeRuntime.remove(main, failedDirectory);
			if (failedBootstrapDirectory != null)
				WorktreeRuntime.remove(main, failedBootstrapDirectory);
			throw error;
		}
	}

	static function vcsEvents(dir:String):Void {
		final fileBus = new EventBus<FileUpdatedEvent>();
		final branchBus = new EventBus<VcsEvent>();
		final vcs = new VcsRuntime(dir, branchBus, fileBus);
		final events:Array<VcsEvent> = [];
		final branchEvents:Array<VcsEvent> = [];
		final unsubscribe = vcs.subscribe(event -> events.push(event));
		final branchUnsubscribe = branchBus.subscribe(event -> branchEvents.push(event));
		git(dir, ["branch", "feature/vcs-event"]);
		Fs.writeFileSync(NodePath.join(NodePath.join(dir, ".git"), "HEAD"), "ref: refs/heads/feature/vcs-event\n", "utf8");
		fileBus.publish({
			type: FileUpdated,
			directory: dir,
			file: NodePath.join(NodePath.join(dir, ".git"), "HEAD"),
		});
		eq(vcs.branch(), "feature/vcs-event", "vcs bus refreshed branch");
		eq(vcs.refresh(), "feature/vcs-event", "vcs explicit refresh remains stable");
		unsubscribe();
		branchUnsubscribe();
		vcs.dispose();
		eq(events.length, 1, "vcs branch event emitted");
		eq(events[0].type, BranchUpdated, "vcs branch event type");
		eq(events[0].branch, "feature/vcs-event", "vcs branch event branch");
		final fileHistory = fileBus.snapshot();
		final branchHistory = branchBus.snapshot();
		eq(fileHistory[0].type, FileUpdated, "vcs file bus event type");
		eq(branchHistory.length, 1, "vcs branch bus history count");
		eq(branchHistory[0].type, BranchUpdated, "vcs branch bus event type");
		eq(branchHistory[0].branch, "feature/vcs-event", "vcs branch bus event payload");
		eq(hasVcsEvent(branchEvents, BranchUpdated, "feature/vcs-event"), true, "vcs live branch bus event");
	}

	static function hasVcsEvent(events:Array<VcsEvent>, type:VcsEventType, branch:String):Bool {
		for (event in events) {
			if (event.type == type && event.branch == branch)
				return true;
		}
		return false;
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

	static function initCommittedRepo(dir:String, ?readme:String):Void {
		git(dir, ["init"]);
		git(dir, ["branch", "-M", "main"]);
		write(dir, "README.md", readme == null ? "# fixture\n" : readme);
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

	static function commit(dir:String, message:String):Void {
		git(dir, [
			"-c",
			"user.email=test@example.com",
			"-c",
			"user.name=OpenCodeHX",
			"commit",
			"--no-gpg-sign",
			"-m",
			message
		]);
	}

	static function commitEmpty(dir:String, message:String):Void {
		git(dir, [
			"-c",
			"user.email=test@example.com",
			"-c",
			"user.name=OpenCodeHX",
			"commit",
			"--allow-empty",
			"--no-gpg-sign",
			"-m",
			message
		]);
	}

	static function storageSession(id:SessionID, projectID:String, directory:String):SessionInfo {
		return {
			id: id,
			slug: id.toString(),
			projectID: projectID,
			directory: directory,
			title: "migration fixture",
			version: "0.0.0-test",
			time: {
				created: 1,
				updated: 1,
			},
		};
	}

	static function cloneProjectIDs(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "clone-source");
		initCommittedRepo(dir);
		final bare = NodePath.join(root, "clone-source.git");
		final clone = NodePath.join(root, "clone-copy");
		try {
			git(root, ["clone", "--bare", dir, bare]);
			git(root, ["clone", bare, clone]);
			final source = ProjectRuntime.fromDirectory(dir).project;
			final copied = ProjectRuntime.fromDirectory(clone).project;
			eq(copied.id.toString(), source.id.toString(), "clone project id shared");
			finallyCleanup([bare, clone]);
			// Dynamic is required at this JS runtime cleanup boundary because Git
			// failures can arrive as strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			finallyCleanup([bare, clone]);
			throw error;
		}
	}

	static function bareProjectCache(root:String):Void {
		ProjectRuntime.reset();
		final dir = directory(root, "bare-source");
		initCommittedRepo(dir);
		final bare = NodePath.join(root, "bare-source.git");
		final worktree = NodePath.join(root, "bare-worktree");
		try {
			git(root, ["clone", "--bare", dir, bare]);
			git(bare, ["worktree", "add", worktree, "HEAD"]);
			final project = ProjectRuntime.fromDirectory(worktree).project;
			neq(project.id.toString(), ProjectID.global().toString(), "bare project id");
			eq(realpath(project.worktree), realpath(bare), "bare project worktree");
			eq(Fs.existsSync(NodePath.join(bare, "opencode")), true, "bare project cache");
			eq(Fs.existsSync(NodePath.join(NodePath.join(root, ".git"), "opencode")), false, "bare wrong parent cache");
			finallyCleanup([bare, worktree]);
			// Dynamic is required at this JS runtime cleanup boundary because Git
			// failures can arrive as strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			finallyCleanup([bare, worktree]);
			throw error;
		}
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

	static function startMarkerCommand(name:String):String {
		final escaped = name.split("\\").join("\\\\").split("'").join("\\'");
		return "node -e \"require('fs').writeFileSync('" + escaped + "', 'ok')\"";
	}

	static function finallyCleanup(paths:Array<String>):Void {
		for (path in paths) {
			if (Fs.existsSync(path))
				Fs.rmSync(path, {recursive: true, force: true});
		}
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
