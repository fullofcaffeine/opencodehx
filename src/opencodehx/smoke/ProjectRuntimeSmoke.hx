package opencodehx.smoke;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.bus.EventBus;
import opencodehx.command.CommandRuntime.CommandDefaultName;
import opencodehx.command.CommandRuntime.CommandEventType;
import opencodehx.command.CommandRuntime.CommandExecutedEvent;
import opencodehx.file.FileWatcherRuntime;
import opencodehx.file.FileWatcherRuntime.FileWatchBackend;
import opencodehx.file.FileWatcherRuntime.FileWatchCallback;
import opencodehx.file.FileWatcherRuntime.FileWatchChangeKind;
import opencodehx.file.FileWatcherRuntime.FileWatchHandle;
import opencodehx.file.FileWatcherRuntime.FileUpdatedEvent;
import opencodehx.file.FileWatcherRuntime.FileWatchEventType;
import opencodehx.git.Git;
import opencodehx.git.Git.GitChangeKind;
import opencodehx.git.Git.GitItem;
import opencodehx.git.Git.GitStat;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.installation.InstallationRuntime;
import opencodehx.installation.InstallationRuntime.InstallationCommand;
import opencodehx.installation.InstallationRuntime.InstallationDeps;
import opencodehx.installation.InstallationRuntime.InstallationHttpRequest;
import opencodehx.installation.InstallationRuntime.InstallationMethod;
import opencodehx.installation.InstallationRuntime.InstallationProcessResult;
import opencodehx.installation.InstallationRuntime.InstallationReleaseType;
import opencodehx.npm.Npm as NpmRuntime;
import opencodehx.npm.Npm.NpmDeps;
import opencodehx.npm.Npm.NpmHttpResponse;
import opencodehx.npm.Npm.NpmReifyRequest;
import opencodehx.project.InstanceBootstrapRuntime;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime.InstanceEvent;
import opencodehx.project.InstanceRuntime.InstanceEventType;
import opencodehx.project.InstanceRuntime.InstanceServiceFactory;
import opencodehx.project.InstanceRuntime.InstanceServiceHandle;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectEvent;
import opencodehx.project.ProjectRuntime.ProjectEventType;
import opencodehx.project.ProjectRuntime.ProjectID;
import opencodehx.project.ProjectRuntime.ProjectInfo;
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
import opencodehx.sync.SyncEventStore.SyncDefinition;
import opencodehx.sync.SyncEventStore.SyncEventSystem;
import opencodehx.sync.SyncEventStore.SyncPersistence;
import opencodehx.sync.SyncEventStore.SyncStoredEvent;
import opencodehx.sync.SyncSqliteEventPersistence;
import opencodehx.worktree.WorktreeRuntime.WorktreeEvent;
import opencodehx.worktree.WorktreeRuntime.WorktreeEventType;
import opencodehx.worktree.WorktreeRuntime;

using StringTools;

typedef SmokeSyncItem = {
	final id:String;
	final name:String;
}

typedef SmokeSyncSentItem = {
	final itemID:String;
	final to:String;
}

typedef SmokeInstallationDeps = {
	final deps:InstallationDeps;
	final requests:Array<InstallationHttpRequest>;
	final commands:Array<InstallationCommand>;
	final responses:Map<String, String>;
	final outputs:Map<String, InstallationProcessResult>;
}

typedef SmokeNpmDeps = {
	final deps:NpmDeps;
	final requests:Array<NpmReifyRequest>;
	final responses:Map<String, NpmHttpResponse>;
}

class SmokeFileWatchHandle implements FileWatchHandle {
	final backend:SmokeFileWatchBackend;
	final directory:String;

	public function new(backend:SmokeFileWatchBackend, directory:String) {
		this.backend = backend;
		this.directory = directory;
	}

	public function close():Void {
		backend.closed = true;
		backend.unwatch(directory);
	}
}

class SmokeFileWatchBackend implements FileWatchBackend {
	public final watched:Array<String> = [];
	public var closed = false;

	var callbacks = new Map<String, FileWatchCallback>();

	public function new() {}

	public function hasNativeBinding():Bool {
		return true;
	}

	public function watch(directory:String, callback:FileWatchCallback):FileWatchHandle {
		watched.push(directory);
		callbacks.set(directory, callback);
		return new SmokeFileWatchHandle(this, directory);
	}

	public function unwatch(directory:String):Void {
		callbacks.remove(directory);
	}

	public function emit(directory:String, file:String, ?event:FileWatchChangeKind = Change):Bool {
		final callback = callbacks.get(directory);
		if (callback == null)
			return false;
		callback({
			type: FileUpdated,
			directory: directory,
			file: file,
			event: event,
		});
		return true;
	}
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
			worktreePlatformFailures(root);
			instanceBootstrapGraph(root);
			fileWatcherService(root);
			npmSanitize();
			npmRuntime(root);
			installationRuntime();
			syncEvents();
			syncEventSystem();
			syncSqliteEvents(root);
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
		vcsWatcherEvents(dir);

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
			expectFailure(() -> WorktreeRuntime.reset(main, main.worktree), "Cannot reset the primary workspace", "worktree reset primary workspace");
			expectFailure(() -> WorktreeRuntime.reset(main, NodePath.join(dir, "not-a-worktree")), "Worktree not found", "worktree reset missing worktree");

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

	static function worktreePlatformFailures(root:String):Void {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		WorktreeRuntime.resetEvents();
		final dir = directory(root, "worktree-platform-main");
		initCommittedRepo(dir);
		final main = ProjectRuntime.fromDirectory(dir).project;

		final nonGit = directory(root, "worktree-platform-non-git");
		final nonGitProject = ProjectRuntime.fromDirectory(nonGit).project;
		expectFailure(() -> WorktreeRuntime.makeWorktreeInfo(nonGitProject, "No Git"), "Worktrees are only supported for git projects",
			"worktree info non-git project");
		expectFailure(() -> WorktreeRuntime.remove(nonGitProject, nonGit), "Worktrees are only supported for git projects", "worktree remove non-git project");

		final fakeResolved = NodePath.join(root, "CaseSensitiveWorktree");
		final fakeRealpath = fakeResolved.toUpperCase();
		eq(WorktreeRuntime.directoryKeyForPlatform(fakeResolved, "win32", _ -> true, _ -> fakeRealpath), NodePath.normalize(fakeRealpath).toLowerCase(),
			"worktree windows directory key lowercases realpath");
		eq(WorktreeRuntime.directoryKeyForPlatform(fakeResolved, "linux", _ -> true, _ -> fakeRealpath), NodePath.normalize(fakeRealpath),
			"worktree posix directory key preserves realpath case");

		worktreeRemoveNonZeroAfterDetach(root, main);
		worktreeFsmonitorStopIfSupported(main);
	}

	static function worktreeRemoveNonZeroAfterDetach(root:String, main:ProjectInfo):Void {
		if (NodeProcess.platform() == "win32")
			return;
		final realGit = locateGit(main.worktree);
		if (realGit == null)
			throw "worktree remove shim: git executable not found";
		final info = WorktreeRuntime.makeWorktreeInfo(main, "Remove Regression");
		final bin = directory(root, "git-shim-bin");
		final shim = NodePath.join(bin, "git");
		final originalPath = NodeProcess.envValue("PATH");
		try {
			WorktreeRuntime.create(main, info);
			Fs.writeFileSync(shim, removeShimScript(realGit), "utf8");
			Fs.chmodSync(shim, 0x1ed);
			NodeProcess.setEnv("PATH", originalPath == null || originalPath == "" ? bin : bin + ":" + originalPath);
			eq(WorktreeRuntime.remove(main, info.directory), true, "worktree remove ignores detached nonzero");
			eq(Fs.existsSync(info.directory), false, "worktree remove detached directory cleaned");
			eq(Git.run(main.worktree, ["worktree", "list", "--porcelain"]).stdout.indexOf('worktree ${info.directory}'), -1,
				"worktree remove detached list cleaned");
			neq(Git.run(main.worktree, ["show-ref", "--verify", "--quiet", 'refs/heads/${info.branch}']).code, 0, "worktree remove detached branch deleted");
			// Dynamic is required at this JS runtime cleanup boundary because Git
			// failures can arrive as strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			restorePath(originalPath);
			WorktreeRuntime.remove(main, info.directory);
			throw error;
		}
		restorePath(originalPath);
	}

	static function worktreeFsmonitorStopIfSupported(main:ProjectInfo):Void {
		if (NodeProcess.platform() != "win32")
			return;
		final info = WorktreeRuntime.makeWorktreeInfo(main, "Remove Fsmonitor");
		try {
			WorktreeRuntime.create(main, info);
			git(info.directory, ["config", "core.fsmonitor", "true"]);
			Git.run(info.directory, ["fsmonitor--daemon", "stop"]);
			write(info.directory, "tracked.txt", "next\n");
			Git.run(info.directory, ["diff"]);
			final before = Git.run(info.directory, ["fsmonitor--daemon", "status"]);
			if (before.code != 0) {
				WorktreeRuntime.remove(main, info.directory);
				return;
			}
			eq(WorktreeRuntime.remove(main, info.directory), true, "worktree fsmonitor remove");
			eq(Fs.existsSync(info.directory), false, "worktree fsmonitor directory removed");
			neq(Git.run(main.worktree, ["show-ref", "--verify", "--quiet", 'refs/heads/${info.branch}']).code, 0, "worktree fsmonitor branch deleted");
			// Dynamic is required at this JS runtime cleanup boundary because Git
			// failures can arrive as strings, Haxe exceptions, or JS errors.
		} catch (error:Dynamic) {
			WorktreeRuntime.remove(main, info.directory);
			throw error;
		}
	}

	static function locateGit(cwd:String):Null<String> {
		final result = NodeProcess.runShell({
			command: "command -v git",
			cwd: cwd,
			env: NodeProcess.env(),
			timeout: 5000,
			maxBuffer: 1024 * 1024,
		});
		if (result.status != 0 || result.stdout == null)
			return null;
		final value = result.stdout.trim();
		return value == "" ? null : value;
	}

	static function removeShimScript(realGit:String):String {
		final quoted = shellQuote(realGit);
		return [
			"#!/bin/sh",
			'REAL_GIT=${quoted}',
			"previous=''",
			"for arg in \"$@\"; do",
			"  if [ \"$previous\" = \"worktree\" ] && [ \"$arg\" = \"remove\" ]; then",
			"    \"$REAL_GIT\" \"$@\" >/dev/null 2>&1",
			"    echo \"fatal: failed to remove worktree: Directory not empty\" >&2",
			"    exit 1",
			"  fi",
			"  previous=\"$arg\"",
			"done",
			"exec \"$REAL_GIT\" \"$@\"",
			"",
		].join("\n");
	}

	static function shellQuote(value:String):String {
		return "'" + value.split("'").join("'\\''") + "'";
	}

	static function restorePath(value:Null<String>):Void {
		if (value == null)
			NodeProcess.unsetEnv("PATH");
		else
			NodeProcess.setEnv("PATH", value);
	}

	static function instanceBootstrapGraph(root:String):Void {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		final dir = directory(root, "instance-bootstrap-graph");
		initCommittedRepo(dir);
		final project = ProjectRuntime.fromDirectory(dir).project;
		final commandBus = new EventBus<CommandExecutedEvent>();
		final disposeOrder:Array<String> = [];
		final services = InstanceBootstrapRuntime.upstreamOrder(commandBus, [
			(_:InstanceContext) -> ({
				id: Snapshot,
				dispose: () -> disposeOrder.push("snapshot-extra"),
			} : InstanceServiceHandle)
		]);
		final context = InstanceRuntime.boot({
			directory: dir,
			worktree: dir,
			project: project,
			services: services,
		});
		if (context == null)
			throw "instance bootstrap graph failed";
		eq(serviceIDs(context), "config,plugin,lsp,share,format,file,file-watcher,vcs,snapshot,command,snapshot", "instance bootstrap service order");
		eq(ProjectRuntime.get(project.id).time.initialized == null, true, "project not initialized before command");
		commandBus.publish(commandEvent(CommandDefaultName.Review));
		eq(ProjectRuntime.get(project.id).time.initialized == null, true, "non-init command does not initialize project");
		commandBus.publish(commandEvent(CommandDefaultName.Init));
		final initialized = ProjectRuntime.get(project.id).time.initialized;
		eq(initialized != null, true, "init command initializes project");
		eq(InstanceRuntime.dispose(dir), true, "instance bootstrap graph dispose");
		eq(disposeOrder.join(","), "snapshot-extra", "instance service disposer ran");
		commandBus.publish(commandEvent(CommandDefaultName.Init));
		eq(ProjectRuntime.get(project.id).time.initialized, initialized, "disposed command hook unsubscribed");

		final failedDir = directory(root, "instance-bootstrap-failure");
		initCommittedRepo(failedDir);
		final failedProject = ProjectRuntime.fromDirectory(failedDir).project;
		final failureOrder:Array<String> = [];
		final failed = InstanceRuntime.boot({
			directory: failedDir,
			worktree: failedDir,
			project: failedProject,
			services: failingServices(failureOrder),
		});
		eq(failed == null, true, "failed service graph returns null");
		eq(InstanceRuntime.get(failedDir) == null, true, "failed service graph not cached");
		eq(failureOrder.join(","), "config,dispose-config", "failed service graph disposes started services");
	}

	static function failingServices(order:Array<String>):Array<InstanceServiceFactory> {
		return [
			(_:InstanceContext) -> {
				order.push("config");
				return ({
					id: Config,
					dispose: () -> order.push("dispose-config"),
				} : InstanceServiceHandle);
			},
			(_:InstanceContext) -> null,
		];
	}

	static function serviceIDs(context:InstanceContext):String {
		return [for (service in context.services) service.id].join(",");
	}

	static function commandEvent(name:String):CommandExecutedEvent {
		return {
			type: CommandEventType.Executed,
			name: name,
			sessionID: "ses_bootstrap",
			arguments: "",
			messageID: "msg_bootstrap",
		};
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

	static function vcsWatcherEvents(dir:String):Void {
		final fileBus = new EventBus<FileUpdatedEvent>();
		final branchBus = new EventBus<VcsEvent>();
		final backend = new SmokeFileWatchBackend();
		final watcher = new FileWatcherRuntime(dir, fileBus, backend);
		final vcs = new VcsRuntime(dir, branchBus, fileBus);
		try {
			eq(watcher.init(false, true), true, "native watcher seam subscribed git dir");
			final gitDir = NodePath.join(dir, ".git");
			eq(backend.watched.indexOf(gitDir) != -1, true, "native watcher seam watches git dir");
			git(dir, ["branch", "feature/vcs-watch"]);
			Fs.writeFileSync(NodePath.join(gitDir, "HEAD"), "ref: refs/heads/feature/vcs-watch\n", "utf8");
			backend.emit(gitDir, "HEAD");
			eq(vcs.branch(), "feature/vcs-watch", "vcs watcher refreshed branch");
			eq(hasVcsEvent(branchBus.snapshot(), BranchUpdated, "feature/vcs-watch"), true, "vcs watcher branch bus event");
			eq(fileBus.snapshot()[0].file, NodePath.join(gitDir, "HEAD"), "native watcher bus publishes HEAD path");
			// Dynamic is required at this JS runtime cleanup boundary because Haxe
			// code, Node externs, and Git helpers may throw strings, Haxe
			// exceptions, or JS errors.
		} catch (error:Dynamic) {
			watcher.dispose();
			vcs.dispose();
			throw error;
		}
		watcher.dispose();
		vcs.dispose();
		eq(backend.closed, true, "native watcher handle closed");
	}

	static function fileWatcherService(root:String):Void {
		final gitDir = directory(root, "file-watcher-git");
		git(gitDir, ["init"]);
		final fileBus = new EventBus<FileUpdatedEvent>();
		final backend = new SmokeFileWatchBackend();
		final watcher = new FileWatcherRuntime(gitDir, fileBus, backend);
		try {
			eq(watcher.init(true, true), true, "file watcher service subscribed roots");
			final watchedGit = NodePath.join(gitDir, ".git");
			eq(backend.watched.indexOf(gitDir) != -1, true, "file watcher watches root");
			eq(backend.watched.indexOf(watchedGit) != -1, true, "file watcher watches git dir");
			backend.emit(gitDir, "watch.txt", Add);
			backend.emit(gitDir, "watch.txt", Change);
			backend.emit(gitDir, "watch.txt", Unlink);
			final rootEvents = fileBus.snapshot();
			eq(rootEvents.length, 3, "file watcher root event count");
			eq(rootEvents[0].file, NodePath.join(gitDir, "watch.txt"), "file watcher root add path");
			eq(rootEvents[0].event, Add, "file watcher root add");
			eq(rootEvents[1].event, Change, "file watcher root change");
			eq(rootEvents[2].event, Unlink, "file watcher root unlink");
			backend.emit(watchedGit, "index", Change);
			eq(fileBus.snapshot().length, 3, "file watcher ignores git index");
			backend.emit(watchedGit, "HEAD", Change);
			final afterHead = fileBus.snapshot();
			eq(afterHead.length, 4, "file watcher publishes git HEAD");
			eq(afterHead[3].file, NodePath.join(watchedGit, "HEAD"), "file watcher HEAD path");
			eq(afterHead[3].event, Change, "file watcher HEAD event");
			watcher.dispose();
			eq(backend.closed, true, "file watcher service closed handles");
			eq(backend.emit(gitDir, "after-dispose.txt", Add), false, "file watcher cleanup stops root events");
			eq(fileBus.snapshot().length, 4, "file watcher no event after dispose");
		} catch (error:Dynamic) {
			watcher.dispose();
			throw error;
		}

		final plainDir = directory(root, "file-watcher-plain");
		final plainBus = new EventBus<FileUpdatedEvent>();
		final plainBackend = new SmokeFileWatchBackend();
		final plainWatcher = new FileWatcherRuntime(plainDir, plainBus, plainBackend);
		try {
			eq(plainWatcher.init(true, true), true, "file watcher non-git root subscribed");
			eq(plainBackend.watched.indexOf(plainDir) != -1, true, "file watcher non-git watches root");
			plainBackend.emit(plainDir, "plain.txt", Add);
			eq(plainBus.snapshot().length, 1, "file watcher non-git add count");
			eq(plainBus.snapshot()[0].file, NodePath.join(plainDir, "plain.txt"), "file watcher non-git add path");
			eq(plainBus.snapshot()[0].event, Add, "file watcher non-git add event");
		} catch (error:Dynamic) {
			plainWatcher.dispose();
			throw error;
		}
		plainWatcher.dispose();
	}

	static function hasVcsEvent(events:Array<VcsEvent>, type:VcsEventType, branch:String):Bool {
		for (event in events) {
			if (event.type == type && event.branch == branch)
				return true;
		}
		return false;
	}

	static function npmSanitize():Void {
		eq(NpmRuntime.sanitize("@opencode/acme"), "@opencode/acme", "scoped npm sanitize");
		eq(NpmRuntime.sanitize("@opencode/acme@1.0.0"), "@opencode/acme@1.0.0", "versioned npm sanitize");
		eq(NpmRuntime.sanitize("prettier"), "prettier", "plain npm sanitize");
		final spec = "acme@git+https://github.com/opencode/acme.git";
		final expected = NodeProcess.platform() == "win32" ? "acme@git+https_//github.com/opencode/acme.git" : spec;
		eq(NpmRuntime.sanitize(spec), expected, "git https npm sanitize");
	}

	static function npmRuntime(root:String):Void {
		final fixture = npmFixture(NodePath.join(root, "npm-runtime"));
		eq(NpmRuntime.packageName("@scope/pkg@1.2.3"), "@scope/pkg", "npm packageName scoped version");
		eq(NpmRuntime.packageName("prettier@git+https://github.com/prettier/prettier.git"), "prettier", "npm packageName git spec");

		final cachedPkg = NodePath.join(NodePath.join(NpmRuntime.cacheDirectory(fixture.deps, "prettier"), "node_modules"), "prettier");
		Fs.mkdirSync(cachedPkg, {recursive: true});
		final cached = NpmRuntime.add(fixture.deps, "prettier");
		eq(cached.directory, cachedPkg, "npm add cached package directory");
		eq(cached.entrypoint, NodePath.join(cachedPkg, "index.js"), "npm add cached entrypoint");
		eq(fixture.requests.length, 0, "npm add cached skips reify");

		final uncached = NpmRuntime.add(fixture.deps, "@scope/tool@1.0.0");
		eq(uncached.directory.endsWith(NodePath.join(NodePath.join("node_modules", "@scope"), "tool")), true, "npm add uncached edge directory");
		eq(fixture.requests[0].add.join(","), "@scope/tool@1.0.0", "npm add reify package spec");

		final readonlyDir = NodePath.join(root, "npm-readonly");
		Fs.mkdirSync(readonlyDir, {recursive: true});
		final beforeReadonly = fixture.requests.length;
		NpmRuntime.install(fixture.deps, readonlyDir, {add: []});
		eq(fixture.requests.length, beforeReadonly, "npm install skips non-writable dir");

		final installDir = directory(root, "npm-install-missing-node-modules");
		NpmRuntime.install(fixture.deps, installDir, {add: [{name: "eslint", version: "9.0.0"}]});
		eq(fixture.requests[fixture.requests.length - 1].dir, installDir, "npm install missing node_modules reify dir");
		eq(fixture.requests[fixture.requests.length - 1].add.join(","), "eslint@9.0.0", "npm install add spec");

		final cleanDir = directory(root, "npm-install-clean");
		Fs.mkdirSync(NodePath.join(cleanDir, "node_modules"), {recursive: true});
		write(cleanDir, "package.json", '{"dependencies":{"typescript":"5.0.0"},"devDependencies":{"eslint":"9.0.0"}}');
		write(cleanDir, "package-lock.json", '{"packages":{"":{"dependencies":{"typescript":"5.0.0"},"devDependencies":{"eslint":"9.0.0"}}}}');
		final beforeClean = fixture.requests.length;
		NpmRuntime.install(fixture.deps, cleanDir, {add: []});
		eq(fixture.requests.length, beforeClean, "npm install clean lock skips reify");

		final dirtyDir = directory(root, "npm-install-dirty");
		Fs.mkdirSync(NodePath.join(dirtyDir, "node_modules"), {recursive: true});
		write(dirtyDir, "package.json", '{"dependencies":{"typescript":"5.0.0"},"optionalDependencies":{"prettier":"3.0.0"}}');
		write(dirtyDir, "package-lock.json", '{"packages":{"":{"dependencies":{"typescript":"5.0.0"}}}}');
		NpmRuntime.install(fixture.deps, dirtyDir, {add: [{name: "prettier"}]});
		eq(fixture.requests[fixture.requests.length - 1].dir, dirtyDir, "npm install dirty lock reify dir");
		eq(fixture.requests[fixture.requests.length - 1].add.join(","), "prettier", "npm install dirty lock add spec");

		final singleBinDir = NpmRuntime.cacheDirectory(fixture.deps, "single-bin");
		final singleBin = NodePath.join(NodePath.join(singleBinDir, "node_modules"), ".bin");
		Fs.mkdirSync(singleBin, {recursive: true});
		writeFile(NodePath.join(singleBin, "single-bin"), "#!/bin/sh\n");
		eq(NpmRuntime.which(fixture.deps, "single-bin"), NodePath.join(singleBin, "single-bin"), "npm which single bin");

		final multiBinDir = NpmRuntime.cacheDirectory(fixture.deps, "@scope/multi");
		final multiBin = NodePath.join(NodePath.join(multiBinDir, "node_modules"), ".bin");
		final multiPkg = NodePath.join(NodePath.join(multiBinDir, "node_modules"), NodePath.join("@scope", "multi"));
		Fs.mkdirSync(multiBin, {recursive: true});
		Fs.mkdirSync(multiPkg, {recursive: true});
		writeFile(NodePath.join(multiBin, "fallback"), "#!/bin/sh\n");
		writeFile(NodePath.join(multiBin, "multi"), "#!/bin/sh\n");
		writeFile(NodePath.join(multiPkg, "package.json"), '{"bin":{"multi":"./cli.js","fallback":"./fallback.js"}}');
		eq(NpmRuntime.which(fixture.deps, "@scope/multi"), NodePath.join(multiBin, "multi"), "npm which prefers unscoped bin");

		final missingBinDir = NpmRuntime.cacheDirectory(fixture.deps, "installed-later");
		Fs.mkdirSync(missingBinDir, {recursive: true});
		writeFile(NodePath.join(missingBinDir, "package-lock.json"), "{}");
		final installedLater = NpmRuntime.which(fixture.deps, "installed-later");
		eq(installedLater, null, "npm which existing cache without bin stays missing");
		eq(Fs.existsSync(NodePath.join(missingBinDir, "package-lock.json")), false, "npm which removes stale package lock");

		final freshBinDir = NpmRuntime.cacheDirectory(fixture.deps, "fresh-bin");
		final freshBin = NpmRuntime.which(fixture.deps, "fresh-bin");
		eq(freshBin, NodePath.join(NodePath.join(NodePath.join(freshBinDir, "node_modules"), ".bin"), "fresh-bin"), "npm which installs absent cache");

		fixture.responses.set("https://registry.npmjs.org/prettier", {ok: true, body: '{"dist-tags":{"latest":"3.0.0"}}'});
		eq(NpmRuntime.outdated(fixture.deps, "prettier", "2.9.0"), true, "npm outdated exact older");
		eq(NpmRuntime.outdated(fixture.deps, "prettier", "3.0.0"), false, "npm outdated exact current");
		eq(NpmRuntime.outdated(fixture.deps, "prettier", "^2.8.0"), true, "npm outdated range escaped major");
		fixture.responses.set("https://registry.npmjs.org/prettier", {ok: true, body: '{"dist-tags":{"latest":"2.9.0"}}'});
		eq(NpmRuntime.outdated(fixture.deps, "prettier", "^2.8.0"), false, "npm outdated range satisfied");
		fixture.responses.set("https://registry.npmjs.org/prettier", {ok: false, body: ""});
		eq(NpmRuntime.outdated(fixture.deps, "prettier", "1.0.0"), false, "npm outdated registry failure");
	}

	static function installationRuntime():Void {
		final fixture = installationFixture();
		fixture.responses.set("https://api.github.com/repos/anomalyco/opencode/releases/latest", '{"tag_name":"v4.0.0-beta.1"}');
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Curl), "4.0.0-beta.1", "installation github latest strips v");

		fixture.outputs.set("npm config get registry", processOk("https://registry.example/\n"));
		fixture.responses.set("https://registry.example/opencode-ai/latest", '{"version":"1.5.0"}');
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Npm), "1.5.0", "installation npm latest");
		eq(fixture.requests[fixture.requests.length - 1].url, "https://registry.example/opencode-ai/latest", "installation npm registry url");

		fixture.outputs.set("npm config get registry", processOk(""));
		fixture.responses.set("https://registry.npmjs.org/opencode-ai/latest", '{"version":"1.6.0"}');
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Bun), "1.6.0", "installation bun latest via npm registry");

		fixture.responses.set("https://raw.githubusercontent.com/ScoopInstaller/Main/master/bucket/opencode.json", '{"version":"2.3.4"}');
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Scoop), "2.3.4", "installation scoop latest");

		fixture.responses.set("https://community.chocolatey.org/api/v2/Packages?$filter=Id%20eq%20%27opencode%27%20and%20IsLatestVersion&$select=Version",
			'{"d":{"results":[{"Version":"3.4.5"}]}}');
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Choco), "3.4.5", "installation choco latest");

		fixture.outputs.set("brew list --formula anomalyco/tap/opencode", processOk(""));
		fixture.outputs.set("brew list --formula opencode", processOk("opencode\n"));
		fixture.responses.set("https://formulae.brew.sh/api/formula/opencode.json", '{"versions":{"stable":"2.0.0"}}');
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Brew), "2.0.0", "installation brew core latest");

		fixture.outputs.set("brew list --formula anomalyco/tap/opencode", processOk("opencode\n"));
		fixture.outputs.set("brew info --json=v2 anomalyco/tap/opencode", processOk('{"formulae":[{"versions":{"stable":"2.1.0"}}]}'));
		eq(InstallationRuntime.latest(fixture.deps, InstallationMethod.Brew), "2.1.0", "installation brew tap latest");

		final methodFixture = installationFixture("/usr/local/bin/npm");
		methodFixture.outputs.set("npm list -g --depth=0", processOk("opencode-ai@0.1.0\n"));
		methodFixture.outputs.set("yarn global list", processOk("opencode-ai@0.1.0\n"));
		eq(InstallationRuntime.method(methodFixture.deps), InstallationMethod.Npm, "installation method prefers exec path");
		eq(InstallationRuntime.method(installationFixture("/Users/me/.opencode/bin/opencode").deps), InstallationMethod.Curl,
			"installation method curl opencode path");

		final upgradeFixture = installationFixture("/usr/local/bin/opencode");
		eq(InstallationRuntime.upgrade(upgradeFixture.deps, InstallationMethod.Npm, "9.9.9").code, 0, "installation npm upgrade");
		eq(commandKey(upgradeFixture.commands[0]), "npm install -g opencode-ai@9.9.9", "installation npm upgrade command");

		final brewUpgrade = installationFixture("/usr/local/bin/opencode");
		brewUpgrade.outputs.set("brew list --formula anomalyco/tap/opencode", processOk("opencode\n"));
		brewUpgrade.outputs.set("brew --repo anomalyco/tap", processOk("/tmp/homebrew-tap\n"));
		eq(InstallationRuntime.upgrade(brewUpgrade.deps, InstallationMethod.Brew, "9.9.9").code, 0, "installation brew upgrade");
		eq(commandKey(brewUpgrade.commands[0]), "brew list --formula anomalyco/tap/opencode", "installation brew checks tap formula");
		eq(commandKey(brewUpgrade.commands[1]), "brew tap anomalyco/tap", "installation brew taps before upgrade");
		eq(commandKey(brewUpgrade.commands[2]), "brew --repo anomalyco/tap", "installation brew repo command");
		eq(commandKey(brewUpgrade.commands[3]), "git pull --ff-only", "installation brew tap pull");
		eq(brewUpgrade.commands[3].cwd, "/tmp/homebrew-tap", "installation brew pull cwd");
		eq(commandKey(brewUpgrade.commands[4]), "brew upgrade anomalyco/tap/opencode", "installation brew upgrade command");

		final chocoUpgrade = installationFixture("/usr/local/bin/opencode");
		chocoUpgrade.outputs.set("choco upgrade opencode --version=9.9.9 -y", {code: 1, stdout: "", stderr: "denied"});
		eq(InstallationRuntime.upgrade(chocoUpgrade.deps, InstallationMethod.Choco, "9.9.9").stderr, "not running from an elevated command shell",
			"installation choco failure message");

		final uninstallFixture = installationFixture("/usr/local/bin/opencode");
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Npm);
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Pnpm);
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Bun);
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Yarn);
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Brew);
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Choco);
		InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Scoop);
		eq(commandKey(uninstallFixture.commands[0]), "npm uninstall -g opencode-ai", "installation npm uninstall command");
		eq(commandKey(uninstallFixture.commands[1]), "pnpm uninstall -g opencode-ai", "installation pnpm uninstall command");
		eq(commandKey(uninstallFixture.commands[2]), "bun remove -g opencode-ai", "installation bun uninstall command");
		eq(commandKey(uninstallFixture.commands[3]), "yarn global remove opencode-ai", "installation yarn uninstall command");
		eq(commandKey(uninstallFixture.commands[4]), "brew uninstall opencode", "installation brew uninstall command");
		eq(commandKey(uninstallFixture.commands[5]), "choco uninstall opencode -y -r", "installation choco uninstall command");
		eq(commandKey(uninstallFixture.commands[6]), "scoop uninstall opencode", "installation scoop uninstall command");
		final beforeCurlUninstall = uninstallFixture.commands.length;
		eq(InstallationRuntime.uninstallPackage(uninstallFixture.deps, InstallationMethod.Curl).code, 0, "installation curl uninstall package noop");
		eq(uninstallFixture.commands.length, beforeCurlUninstall, "installation curl uninstall package no command");

		eq(InstallationRuntime.getReleaseType("1.2.3", "1.2.4"), InstallationReleaseType.Patch, "installation patch release type");
		eq(InstallationRuntime.getReleaseType("1.2.3", "1.3.0"), InstallationReleaseType.Minor, "installation minor release type");
		eq(InstallationRuntime.getReleaseType("1.2.3", "2.0.0"), InstallationReleaseType.Major, "installation major release type");
	}

	static function installationFixture(?execPath:String):SmokeInstallationDeps {
		final requests:Array<InstallationHttpRequest> = [];
		final commands:Array<InstallationCommand> = [];
		final responses = new Map<String, String>();
		final outputs = new Map<String, InstallationProcessResult>();
		final fixture:SmokeInstallationDeps = {
			requests: requests,
			commands: commands,
			responses: responses,
			outputs: outputs,
			deps: {
				execPath: execPath == null ? "/usr/local/bin/opencode" : execPath,
				channel: "latest",
				http: request -> {
					requests.push(request);
					return {
						status: responses.exists(request.url) ? 200 : 404,
						body: responses.exists(request.url) ? responses.get(request.url) : "",
					};
				},
				run: command -> {
					commands.push(command);
					final key = commandKey(command);
					return outputs.exists(key) ? outputs.get(key) : processOk("");
				},
			},
		};
		return fixture;
	}

	static function processOk(stdout:String):InstallationProcessResult {
		return {code: 0, stdout: stdout, stderr: ""};
	}

	static function commandKey(command:InstallationCommand):String {
		return [command.command].concat(command.args).join(" ");
	}

	static function npmFixture(root:String):SmokeNpmDeps {
		final requests:Array<NpmReifyRequest> = [];
		final responses = new Map<String, NpmHttpResponse>();
		Fs.mkdirSync(root, {recursive: true});
		final fixture:SmokeNpmDeps = {
			requests: requests,
			responses: responses,
			deps: {
				cache: root,
				http: url -> responses.exists(url) ? responses.get(url) : {ok: false, body: ""},
				canWrite: dir -> !dir.endsWith("readonly"),
				resolveEntryPoint: (name, dir) -> NodePath.join(dir, "index.js"),
				reify: request -> {
					requests.push(request);
					Fs.mkdirSync(request.dir, {recursive: true});
					final edges = [];
					for (spec in request.add) {
						final name = NpmRuntime.packageName(spec);
						final packageDir = NodePath.join(NodePath.join(request.dir, "node_modules"), name);
						final binDir = NodePath.join(NodePath.join(request.dir, "node_modules"), ".bin");
						Fs.mkdirSync(packageDir, {recursive: true});
						Fs.mkdirSync(binDir, {recursive: true});
						writeFile(NodePath.join(binDir,
							NpmRuntime.packageName(spec).startsWith("@") ? NpmRuntime.packageName(spec).split("/")[1] : NpmRuntime.packageName(spec)),
							"#!/bin/sh\n");
						edges.push({name: name, path: packageDir});
					}
					return {edges: edges};
				},
			},
		};
		return fixture;
	}

	static function syncEvents():Void {
		final persisted:Array<SyncStoredEvent<SmokeSyncItem>> = [];
		final published:Array<SyncStoredEvent<SmokeSyncItem>> = [];
		final persistence:SyncPersistence<SmokeSyncItem> = {
			load: () -> persisted.copy(),
			save: event -> {
				persisted.push(event);
			},
			remove: aggregateID -> {
				var index = persisted.length - 1;
				while (index >= 0) {
					if (persisted[index].aggregateID == aggregateID)
						persisted.splice(index, 1);
					index -= 1;
				}
			},
		};
		final store = new SyncEventStore<SmokeSyncItem>({
			type: "item.created",
			version: 1,
			aggregate: item -> item.id,
		}, {
			persistence: persistence,
			publisher: event -> {
				published.push(event);
			},
		});
		final first = store.run({id: "item_1", name: "first"});
		final second = store.run({id: "item_1", name: "second"});
		eq(first.seq, 0, "sync first seq");
		eq(second.seq, 1, "sync second seq");
		eq(store.history("item_1").length, 2, "sync history length");
		eq(persisted.length, 2, "sync persisted run count");
		eq(published.length, 2, "sync published run count");

		final sent = new SyncEventStore<SmokeSyncSentItem>({
			type: "item.sent",
			version: 1,
			aggregate: item -> item.itemID,
		});
		eq(sent.run({itemID: "item_custom", to: "james"}, false).aggregateID, "item_custom", "sync custom aggregate");

		final restarted = new SyncEventStore<SmokeSyncItem>({
			type: "item.created",
			version: 1,
			aggregate: item -> item.id,
		}, {
			persistence: persistence,
			publisher: event -> {
				published.push(event);
			},
		});
		eq(restarted.history("item_1").length, 2, "sync restart history length");
		final third = restarted.run({id: "item_1", name: "third"});
		eq(third.id, "evt_3", "sync restart next id");
		eq(third.seq, 2, "sync restart next seq");
		eq(restarted.historyAfter([{aggregateID: "item_1", seq: 1}]).length, 1, "sync history after known seq");
		restarted.remove("item_1");
		eq(restarted.history("item_1").length, 0, "sync remove store history");
		eq(persisted.length, 0, "sync remove persisted history");

		final replayPublished:Array<SyncStoredEvent<SmokeSyncItem>> = [];
		final replay = new SyncEventStore<SmokeSyncItem>({
			type: "item.created",
			version: 1,
			aggregate: item -> item.id,
		}, {
			publisher: event -> {
				replayPublished.push(event);
			},
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
		], true);
		eq(source, "item_2", "sync replay source");
		eq(replayPublished.length, 2, "sync replay publish count");
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

	static function syncEventSystem():Void {
		final system = new SyncEventSystem<SmokeSyncItem>();
		final createdV1:SyncDefinition<SmokeSyncItem> = system.define({
			type: "item.created",
			version: 1,
			aggregateName: "id",
			aggregate: item -> item.id,
		});
		final createdV2:SyncDefinition<SmokeSyncItem> = system.define({
			type: "item.created",
			version: 2,
			aggregateName: "id",
			aggregate: item -> item.id,
		});
		final projected:Array<String> = [];
		system.init({
			projectors: [
				{
					definition: createdV2,
					project: event -> {
						projected.push(event.data.name);
					},
				}
			],
			convertEvent: item -> {
				return {id: item.id, name: item.name.toUpperCase()};
			},
			directory: "/workspace/project",
			project: "project_1",
			workspace: "workspace_1",
		});
		expectFailure(() -> system.define({
			type: "item.deleted",
			version: 1,
			aggregateName: "id",
			aggregate: item -> item.id,
		}), "sync system has been frozen", "sync define after init");
		expectFailure(() -> system.run(createdV1, {id: "item_1", name: "old"}), "running old versions", "sync old version run");

		final event = system.run(createdV2, {id: "item_1", name: "first"});
		eq(event.type, "item.created.2", "sync system versioned type");
		eq(projected[0], "first", "sync system projector");
		eq(system.busEvents.length, 1, "sync system bus event count");
		eq(system.busEvents[0].type, "item.created", "sync system bus type");
		eq(system.busEvents[0].properties.name, "FIRST", "sync system converted bus data");
		eq(system.globalEvents.length, 1, "sync system global event count");
		eq(system.globalEvents[0].directory, "/workspace/project", "sync system global directory");
		eq(system.globalEvents[0].project, "project_1", "sync system global project");
		eq(system.globalEvents[0].workspace, "workspace_1", "sync system global workspace");
		eq(system.globalEvents[0].payload.type, "sync", "sync system global payload type");
		eq(system.globalEvents[0].payload.syncEvent.id, event.id, "sync system global event id");
		final payloads = system.payloads();
		eq(payloads.length, 2, "sync system payload count");
		eq(payloads[0].type, "sync", "sync system payload descriptor type");
		eq(payloads[0].aggregate, "id", "sync system payload aggregate");

		final missing = new SyncEventSystem<SmokeSyncItem>();
		final missingDefinition = missing.define({
			type: "item.missing",
			version: 1,
			aggregateName: "id",
			aggregate: item -> item.id,
		});
		expectFailure(() -> missing.run(missingDefinition, {id: "item_1", name: "missing"}), "No projectors available", "sync system missing init");
		missing.init({projectors: []});
		expectFailure(() -> missing.run(missingDefinition, {id: "item_1", name: "missing"}), "Projector not found", "sync system missing projector");

		system.reset();
		eq(system.payloads().length, 0, "sync system reset payloads");
	}

	static function syncSqliteEvents(root:String):Void {
		final dbPath = NodePath.join(root, "sync-events.db");
		final firstPersistence = new SyncSqliteEventPersistence<SmokeSyncItem>(dbPath, {
			encode: encodeSyncItem,
			decode: decodeSyncItem,
		});
		final created = syncDefinition("item.created", 1);
		final renamed = syncDefinition("item.renamed", 1);
		final projected:Array<String> = [];
		final first = new SyncEventSystem<SmokeSyncItem>();
		first.define(created);
		first.define(renamed);
		first.init({
			projectors: [
				{
					definition: created,
					project: event -> projected.push('created:${event.seq}:${event.data.name}'),
				},
				{
					definition: renamed,
					project: event -> projected.push('renamed:${event.seq}:${event.data.name}'),
				}
			],
			persistence: firstPersistence.persistence(),
		});
		final createdEvent = first.run(created, {id: "item_sqlite", name: "first"});
		final renamedEvent = first.run(renamed, {id: "item_sqlite", name: "second"});
		eq(createdEvent.seq, 0, "sync sqlite created seq");
		eq(renamedEvent.seq, 1, "sync sqlite renamed seq");
		eq(projected.join(","), "created:0:first,renamed:1:second", "sync sqlite projectors");
		eq(firstPersistence.persistedSeq("item_sqlite"), 1, "sync sqlite sequence table");
		eq(firstPersistence.persistedEventCount("item_sqlite"), 2, "sync sqlite event table count");
		firstPersistence.close();

		final restartedPersistence = new SyncSqliteEventPersistence<SmokeSyncItem>(dbPath, {
			encode: encodeSyncItem,
			decode: decodeSyncItem,
		});
		final restarted = new SyncEventSystem<SmokeSyncItem>();
		restarted.define(created);
		restarted.define(renamed);
		restarted.init({
			projectors: [
				{
					definition: created,
					project: _ -> {},
				},
				{
					definition: renamed,
					project: _ -> {},
				}
			],
			persistence: restartedPersistence.persistence(),
		});
		eq(restarted.history(created, "item_sqlite").length, 1, "sync sqlite restart created history");
		eq(restarted.history(renamed, "item_sqlite").length, 1, "sync sqlite restart renamed history");
		eq(restarted.run(renamed, {id: "item_sqlite", name: "third"}).seq, 2, "sync sqlite restart sequence");
		eq(restartedPersistence.persistedSeq("item_sqlite"), 2, "sync sqlite restart sequence table");
		eq(restartedPersistence.persistedEventCount("item_sqlite"), 3, "sync sqlite restart event table count");
		restarted.remove("item_sqlite");
		eq(restartedPersistence.persistedSeq("item_sqlite"), null, "sync sqlite remove sequence");
		eq(restartedPersistence.persistedEventCount("item_sqlite"), 0, "sync sqlite remove cascades events");
		restartedPersistence.close();
	}

	static function syncDefinition(type:String, version:Int):SyncDefinition<SmokeSyncItem> {
		return {
			type: type,
			version: version,
			aggregateName: "id",
			aggregate: item -> item.id,
		};
	}

	static function encodeSyncItem(item:SmokeSyncItem):String {
		return Json.stringify({id: item.id, name: item.name});
	}

	static function decodeSyncItem(text:String):SmokeSyncItem {
		final record = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(text)));
		if (record == null)
			throw "sync sqlite item: expected object";
		final id = UnknownNarrow.string(record.get("id"));
		final name = UnknownNarrow.string(record.get("name"));
		if (id == null || name == null)
			throw "sync sqlite item: expected id/name";
		return {id: id, name: name};
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

	static function writeFile(file:String, data:String):Void {
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
