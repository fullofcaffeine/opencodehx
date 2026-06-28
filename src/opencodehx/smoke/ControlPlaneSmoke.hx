package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import js.lib.Promise;
import js.html.Response;
import opencodehx.controlplane.WorkspaceAdaptors;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceAdaptor;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceEnv;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceInfo;
import opencodehx.controlplane.WorkspaceAdaptors.WorkspaceTarget;
import opencodehx.controlplane.WorkspaceRestoreRuntime;
import opencodehx.controlplane.WorkspaceRestoreRuntime.WorkspaceRestoreProgress;
import opencodehx.sync.SyncRouteRuntime;
import opencodehx.sync.SyncRouteRuntime.SyncRouteEvent;
import opencodehx.sync.WorkspaceSyncRemoteHttp;
import opencodehx.sync.WorkspaceSyncRemoteHttp.WorkspaceSyncFetchInit;
import opencodehx.plugin.PluginWorkspaceRuntime;
import opencodehx.project.ProjectRuntime.ProjectID;

typedef WorkspaceRestorePost = {
	final url:String;
	final directory:String;
	final events:Array<SyncRouteEvent>;
}

class ControlPlaneSmoke {
	@:async
	public static function run():Promise<Void> {
		WorkspaceAdaptors.reset();
		await(projectScopedAdaptors());
		await(latestAdaptorWins());
		await(pluginWorkspaceRegistration());
		await(workspaceRestoreRemote());
		await(workspaceRestoreLocal());
		WorkspaceAdaptors.reset();
	}

	@:async
	static function projectScopedAdaptors():Promise<Void> {
		final type = "demo-project-scoped";
		final one = ProjectID.make("project-one");
		final two = ProjectID.make("project-two");
		WorkspaceAdaptors.register(one, type, adaptor("/one"));
		WorkspaceAdaptors.register(two, type, adaptor("/two"));

		eq(localDirectory(await(WorkspaceAdaptors.get(one, type).target(info(one, type))), "project scoped one"), "/one", "project scoped one target");
		eq(localDirectory(await(WorkspaceAdaptors.get(two, type).target(info(two, type))), "project scoped two"), "/two", "project scoped two target");
		eq(WorkspaceAdaptors.list(one).length, 1, "project scoped list count");
		eq(WorkspaceAdaptors.list(one)[0].type, type, "project scoped list type");
	}

	@:async
	static function latestAdaptorWins():Promise<Void> {
		final type = "demo-latest-wins";
		final projectID = ProjectID.make("project-latest");
		WorkspaceAdaptors.register(projectID, type, adaptor("/one"));
		eq(localDirectory(await(WorkspaceAdaptors.get(projectID, type).target(info(projectID, type))), "latest first"), "/one", "latest first target");

		WorkspaceAdaptors.register(projectID, type, adaptor("/two"));
		eq(localDirectory(await(WorkspaceAdaptors.get(projectID, type).target(info(projectID, type))), "latest second"), "/two", "latest second target");
	}

	@:async
	static function pluginWorkspaceRegistration():Promise<Void> {
		final type = "plug-workspace";
		final projectID = ProjectID.make("project-plugin-workspace");
		final space = "/tmp/opencodehx-plugin-workspace";
		final extra = Unknown.fromBoundary({key: "value"});
		final created:Array<WorkspaceInfo> = [];
		final registry = PluginWorkspaceRuntime.registry(projectID);

		registry.register(type, {
			name: "plug",
			description: "plugin workspace adaptor",
			configure: input -> Promise.resolve({
				id: input.id,
				type: input.type,
				name: "plug",
				branch: "plug/main",
				directory: space,
				extra: input.extra,
				projectID: input.projectID,
			}),
			create: (input, _env, ?_from) -> {
				created.push(input);
				return resolvedVoid();
			},
			remove: _ -> resolvedVoid(),
			target: input -> Promise.resolve(LocalTarget(requireDirectory(input.directory, "plugin workspace target"))),
		});

		final registered = WorkspaceAdaptors.get(projectID, type);
		final configured = await(registered.configure({
			id: "plugin-workspace",
			type: type,
			name: "pending",
			branch: null,
			directory: null,
			extra: extra,
			projectID: projectID,
		}));
		await(registered.create(configured, WorkspaceAdaptors.emptyEnv()));

		eq(configured.type, type, "plugin workspace type");
		eq(configured.name, "plug", "plugin workspace configured name");
		eq(configured.branch, "plug/main", "plugin workspace configured branch");
		eq(configured.directory, space, "plugin workspace configured directory");
		eq(extraString(configured.extra, "key", "plugin workspace configured extra"), "value", "plugin workspace configured extra value");
		eq(created.length, 1, "plugin workspace create call count");
		eq(created[0].directory, space, "plugin workspace create directory");
		eq(extraString(created[0].extra, "key", "plugin workspace create extra"), "value", "plugin workspace create extra value");
		eq(localDirectory(await(registered.target(configured)), "plugin workspace target"), space, "plugin workspace local target");
	}

	@:async
	static function workspaceRestoreRemote():Promise<Void> {
		final sessionID = "restore-session-remote";
		final workspaceID = "workspace-remote";
		final progress:Array<WorkspaceRestoreProgress> = [];
		final posts:Array<WorkspaceRestorePost> = [];
		final remote = new WorkspaceSyncRemoteHttp((url, init) -> captureRestoreReplay(url, init, posts));
		final result = await(WorkspaceRestoreRuntime.sessionRestore({
			workspaceID: workspaceID,
			sessionID: sessionID,
			directory: "/tmp/restore-remote",
			events: restoreEvents(sessionID, 13),
			target: RestoreRemote(remote, {
				url: "https://workspace.test/base",
				headers: null
			}),
			emit: event -> progress.push(event),
		}));

		eq(result.total, 2, "workspace restore remote total");
		eq(posts.length, 2, "workspace restore remote post count");
		eq(posts[0].url, "https://workspace.test/base/sync/replay", "workspace restore remote first url");
		eq(posts[0].directory, "/tmp/restore-remote", "workspace restore remote directory");
		eq(posts[0].events.length, 10, "workspace restore remote first batch");
		eq(posts[1].events.length, 4, "workspace restore remote second batch");
		eq(postSeqs(posts), "0,1,2,3,4,5,6,7,8,9,10,11,12,13", "workspace restore remote seqs");
		final last = posts[1].events[3];
		eq(last.type, WorkspaceRestoreRuntime.SESSION_UPDATED_TYPE, "workspace restore session update type");
		eq(last.aggregateID, sessionID, "workspace restore session update aggregate");
		eq(workspaceIDFromUpdate(last), workspaceID, "workspace restore session update workspace");
		eq(progressSteps(progress), "0,1,2", "workspace restore remote progress steps");
		eq(progressTotals(progress), "2,2,2", "workspace restore remote progress totals");
	}

	@:async
	static function workspaceRestoreLocal():Promise<Void> {
		final sessionID = "restore-session-local";
		final workspaceID = "workspace-local";
		final progress:Array<WorkspaceRestoreProgress> = [];
		final runtime = new SyncRouteRuntime(["message.updated.1", WorkspaceRestoreRuntime.SESSION_UPDATED_TYPE]);
		final result = await(WorkspaceRestoreRuntime.sessionRestore({
			workspaceID: workspaceID,
			sessionID: sessionID,
			directory: "/tmp/restore-local",
			events: restoreEvents(sessionID, 13),
			target: RestoreLocal(runtime),
			emit: event -> progress.push(event),
		}));
		final events = runtime.events(sessionID);

		eq(result.total, 2, "workspace restore local total");
		eq(events.length, 14, "workspace restore local replay count");
		eq(events[13].seq, 13, "workspace restore local appended seq");
		eq(workspaceIDFromUpdate(events[13]), workspaceID, "workspace restore local session update workspace");
		eq(progressSteps(progress), "0,1,2", "workspace restore local progress steps");
	}

	static function info(projectID:ProjectID, type:String):WorkspaceInfo {
		return {
			id: "workspace-test",
			type: type,
			name: "workspace-test",
			branch: null,
			directory: null,
			extra: null,
			projectID: projectID,
		};
	}

	static function adaptor(directory:String):WorkspaceAdaptor {
		return {
			name: directory,
			description: directory,
			configure: input -> Promise.resolve(input),
			create: createNoop,
			remove: _ -> resolvedVoid(),
			target: _ -> Promise.resolve(LocalTarget(directory)),
		};
	}

	static function createNoop(_info:WorkspaceInfo, _env:WorkspaceEnv, ?_from:WorkspaceInfo):Promise<Void> {
		return resolvedVoid();
	}

	static function restoreEvents(sessionID:String, count:Int):Array<SyncRouteEvent> {
		final out:Array<SyncRouteEvent> = [];
		for (index in 0...count) {
			out.push({
				id: 'evt_restore_${index}',
				type: "message.updated.1",
				seq: index,
				aggregateID: sessionID,
				data: Unknown.fromBoundary(genes.ts.Json.value({index: index})),
			});
		}
		return out;
	}

	static function captureRestoreReplay(url:String, init:WorkspaceSyncFetchInit, posts:Array<WorkspaceRestorePost>):Promise<Response> {
		if (url.indexOf("/sync/replay") == -1)
			return Promise.resolve(new Response("missing", {status: 404}));
		switch SyncRouteRuntime.decodeReplay(Unknown.fromBoundary(Json.parse(init.body))) {
			case SyncDecoded(request):
				posts.push({url: url, directory: request.directory, events: request.events});
				return Promise.resolve(new Response(Json.stringify({sessionID: request.events[0].aggregateID}), {status: 200}));
			case SyncRejected(message):
				return Promise.resolve(new Response(message, {status: 400}));
		}
	}

	static function postSeqs(posts:Array<WorkspaceRestorePost>):String {
		final seqs:Array<String> = [];
		for (post in posts) {
			for (event in post.events)
				seqs.push(Std.string(event.seq));
		}
		return seqs.join(",");
	}

	static function progressSteps(progress:Array<WorkspaceRestoreProgress>):String {
		return progress.map(event -> Std.string(event.step)).join(",");
	}

	static function progressTotals(progress:Array<WorkspaceRestoreProgress>):String {
		return progress.map(event -> Std.string(event.total)).join(",");
	}

	static function workspaceIDFromUpdate(event:SyncRouteEvent):String {
		final data = UnknownNarrow.record(event.data);
		if (data == null)
			throw "workspace restore update data should be an object";
		final info = UnknownNarrow.record(data.get("info"));
		if (info == null)
			throw "workspace restore update info should be an object";
		final workspaceID = UnknownNarrow.string(info.get("workspaceID"));
		if (workspaceID == null)
			throw "workspace restore update workspaceID should be a string";
		return workspaceID;
	}

	static function resolvedVoid():Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			final done:Void->Void = cast resolve;
			done();
		});
	}

	static function localDirectory(target:WorkspaceTarget, label:String):String {
		return switch target {
			case LocalTarget(directory):
				directory;
			case RemoteTarget(_, _):
				throw '${label}: expected local target';
		}
	}

	static function requireDirectory(directory:Null<String>, label:String):String {
		if (directory == null)
			throw '${label}: expected directory';
		return directory;
	}

	static function extraString(extra:Null<Unknown>, field:String, label:String):String {
		if (extra == null)
			throw '${label}: expected extra';
		final record = UnknownNarrow.record(extra);
		if (record == null)
			throw '${label}: expected record extra';
		final value = UnknownNarrow.string(record.get(field));
		if (value == null)
			throw '${label}: expected string field ${field}';
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
