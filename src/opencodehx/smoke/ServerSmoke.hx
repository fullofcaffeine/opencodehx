package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.AbortSignal;
import js.html.Request;
import js.html.Response;
import js.lib.Error;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.config.ConfigInfo;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.AbortControllerWithReason;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.externs.web.GlobalFetch.GlobalForwardFetchInit;
import opencodehx.externs.web.WebStreams.WebArrayBuffer;
import opencodehx.externs.web.WebStreams.WebBinary;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.externs.web.WebStreams.WebResponseStreams;
import opencodehx.externs.web.WebStreams.WebTextDecoder;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.externs.ws.WebSocket;
import opencodehx.git.Git;
import opencodehx.host.Clock;
import opencodehx.host.node.NodeBuffer;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.project.InstanceRuntime.InstanceContext;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.ProjectRuntime;
import opencodehx.provider.AiSdkProvider.AiSdkMockModel;
import opencodehx.provider.FakeProvider;
import opencodehx.permission.PermissionAsyncRuntime;
import opencodehx.permission.PermissionAsyncRuntime.PermissionCorrectedError;
import opencodehx.permission.PermissionAsyncRuntime.PermissionRejectedError;
import opencodehx.question.QuestionRuntime;
import opencodehx.question.QuestionRuntime.QuestionAnswer;
import opencodehx.question.QuestionRuntime.QuestionInfo;
import opencodehx.question.QuestionRuntime.QuestionRejectedError;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTrace;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.server.WorkspaceProxy;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageID;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.snapshot.SnapshotRuntime;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.sync.SyncRouteRuntime;
import opencodehx.sync.WorkspaceSyncBackgroundTask;
import opencodehx.sync.WorkspaceSyncBackgroundTask.WorkspaceSyncTaskTimer;
import opencodehx.sync.WorkspaceSyncRemoteHttp;
import opencodehx.sync.WorkspaceSyncRemoteHttp.WorkspaceSyncFetchInit;
import opencodehx.sync.WorkspaceSyncRemoteHttp.WorkspaceSyncHttpError;
import opencodehx.sync.WorkspaceSyncRuntime;
import opencodehx.sync.WorkspaceSyncSse;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;

typedef PtyWebSocketResult = {
	final text:String;
	final cursor:Int;
}

typedef SmokeFetchInit = {
	final method:String;
	final headers:DynamicAccess<String>;
	final body:String;
	@:optional final signal:AbortSignal;
}

typedef WorkspaceHttpCapture = {
	final url:String;
	final init:WorkspaceSyncFetchInit;
}

typedef WorkspaceScheduledTick = {
	final delayMs:Int;
	final callback:Void->Void;
	var canceled:Bool;
}

typedef WorkspaceProxyCapture = {
	final url:String;
	final init:GlobalForwardFetchInit;
}

class ServerSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-server-"));
		serverTraceAttributes();
		final syncRuntime = new SyncRouteRuntime(["item.created.1"]);
		final remoteSync = new SyncRouteRuntime(["item.created.1"]);
		remoteSync.replayAll([
			{
				id: "evt_workspace_remote_1",
				type: "item.created.1",
				seq: 0,
				aggregateID: "workspace_session_1",
				data: Unknown.fromBoundary({id: "remote_item", name: "remote"})
			}
		]);
		final workspaceSync = new WorkspaceSyncRuntime(syncRuntime);
		workspaceSync.register({
			id: "wrk_server_1",
			projectID: "proj_server",
			directory: "/remote/workspace",
			activeSessionIDs: ["workspace_session_1"],
			remote: {
				history: known -> remoteSync.history(known),
				replay: events -> remoteSync.replayAll(events),
			},
		});
		syncRuntime.setStartHandler(() -> workspaceSync.start("proj_server"));
		final server = new OpenCodeServer({
			directory: root,
			dbPath: NodePath.join(root, "opencodehx.db"),
			syncRuntime: syncRuntime,
		});
		var listener:Null<ServerListener> = null;
		try {
			await(appRequestRoutes(server, root, workspaceSync, syncRuntime, remoteSync));
			await(liveAiSdkSessionRoute(root));
			await(liveConfigSessionRoute(root));
			listener = await(server.listen(0, "127.0.0.1"));
			final health = await(fetchJson(listener.url + "/health"));
			eq(Reflect.field(health, "ok"), true, "listener health");
			await(ptyWebSocketRoute(listener.url));
			await(listener.stop(true));
			server.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup catches arbitrary JS/Haxe failures from the route,
			// fetch, and WebSocket host APIs, then rethrows the original error.
			if (listener != null)
				await(listener.stop(true));
			server.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	static function configRoute(server:OpenCodeServer, root:String):Promise<Void> {
		Fs.writeFileSync(NodePath.join(root, "opencode.json"),
			'{"' + "$" + 'schema":"${ConfigInfo.DEFAULT_SCHEMA}","model":"server/model","default_agent":"reviewer","enabled_providers":["server-provider"]}');
		final body = @:await jsonResponse(@:await server.app.request("/config"));
		final config = requiredRecord(Unknown.fromBoundary(body), "server config route");
		eq(requiredString(config, "model", "server config model"), "server/model", "server config model");
		eq(requiredString(config, "default_agent", "server config default agent"), "reviewer", "server config default agent");
		final providers = requiredArray(config.get("enabled_providers"), "server config enabled providers");
		eq(UnknownNarrow.string(providers.get(0)), "server-provider", "server config enabled provider");
	}

	@:async
	static function liveAiSdkSessionRoute(root:String):Promise<Void> {
		final liveRoot = NodePath.join(root, "live-ai-sdk-server");
		Fs.mkdirSync(liveRoot, {recursive: true});
		final provider = new FakeProvider();
		final liveServer = new OpenCodeServer({
			directory: liveRoot,
			dbPath: NodePath.join(liveRoot, "opencodehx-live.db"),
			liveAiSdk: {
				provider: provider.info,
				model: provider.model,
				language: AiSdkMockModel.abortable(),
				system: ["Server-owned live AI SDK fixture."],
			},
		});
		final pending = Promise.resolve(liveServer.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Run behind the server.", title: "Server live AI SDK"}),
		}));
		await(waitForStatus(liveServer, "ses_server_1", "busy"));
		final created = requiredRecord(Unknown.fromBoundary(await(jsonResponse(await(pending)))), "live server create");
		eq(UnknownNarrow.string(created.get("id")), "ses_server_1", "live server session id");
		eq(UnknownNarrow.string(created.get("title")), "Server live AI SDK", "live server session title");
		final idleStatus = UnknownNarrow.record(Unknown.fromBoundary(await(jsonResponse(await(liveServer.app.request("/session/status"))))));
		eq(idleStatus != null && idleStatus.keys().length == 0, true, "live server status idle after completion");
		final messages = UnknownNarrow.array(Unknown.fromBoundary(await(jsonResponse(await(liveServer.app.request("/session/ses_server_1/message"))))));
		eq(messages != null && messages.length == 2, true, "live server persisted message count");
		liveServer.close();

		final abortRoot = NodePath.join(root, "live-ai-sdk-server-abort");
		Fs.mkdirSync(abortRoot, {recursive: true});
		final abortServer = new OpenCodeServer({
			directory: abortRoot,
			dbPath: NodePath.join(abortRoot, "opencodehx-live-abort.db"),
			liveAiSdk: {
				provider: provider.info,
				model: provider.model,
				language: AiSdkMockModel.abortable(),
				system: ["Server-owned live AI SDK fixture."],
			},
		});
		final aborting = Promise.resolve(abortServer.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Abort behind the server.", title: "Server live abort"}),
		}));
		await(waitForStatus(abortServer, "ses_server_1", "busy"));
		final abortResponse = await(jsonResponse(await(abortServer.app.request("/session/ses_server_1/abort", {method: "POST"}))));
		eq(abortResponse, true, "live server active abort route");
		final aborted = requiredRecord(Unknown.fromBoundary(await(jsonResponse(await(aborting)))), "live server aborted create");
		eq(UnknownNarrow.string(aborted.get("id")), "ses_server_1", "live server aborted session id");
		eq(UnknownNarrow.string(aborted.get("title")), "Server live abort", "live server aborted session title");
		final abortedIdle = UnknownNarrow.record(Unknown.fromBoundary(await(jsonResponse(await(abortServer.app.request("/session/status"))))));
		eq(abortedIdle != null && abortedIdle.keys().length == 0, true, "live server status idle after abort");
		final abortedMessages = Unknown.fromBoundary(await(jsonResponse(await(abortServer.app.request("/session/ses_server_1/message")))));
		eq(assistantErrorName(abortedMessages, "live server aborted messages"), "MessageAbortedError", "live server abort persisted error");
		eq(assistantText(abortedMessages, "live server aborted messages"), "Request aborted.", "live server abort persisted text");
		abortServer.close();
	}

	@:async
	static function liveConfigSessionRoute(root:String):Promise<Void> {
		final liveRoot = NodePath.join(root, "live-config-server");
		final configRoot = NodePath.join(liveRoot, "xdg");
		final dataRoot = NodePath.join(liveRoot, "data");
		final projectRoot = NodePath.join(liveRoot, "project");
		final configDir = NodePath.join(configRoot, "opencode");
		Fs.mkdirSync(configDir, {recursive: true});
		Fs.mkdirSync(projectRoot, {recursive: true});
		Fs.writeFileSync(NodePath.join(configDir, "opencode.json"),
			'{"' + "$" +
			'schema":"${ConfigInfo.DEFAULT_SCHEMA}","default_agent":"reviewer","provider":{"local-live":{"npm":"@ai-sdk/openai-compatible","name":"Local Live","options":{"baseURL":"https://local-live.example.com/v1","apiKey":"local-key"},"models":{"chat":{"name":"Chat"}}}},"agent":{"reviewer":{"model":"local-live/chat","prompt":"Server agent prompt from config.","tools":{"write":false}}}}');
		final originalFetch = SmokeFetchStub.installCliLiveSuccess();
		final originalXdgConfig = NodeProcess.envValue("XDG_CONFIG_HOME");
		final originalXdgData = NodeProcess.envValue("XDG_DATA_HOME");
		final originalHome = NodeProcess.envValue("OPENCODE_TEST_HOME");
		NodeProcess.setEnv("XDG_CONFIG_HOME", configRoot);
		NodeProcess.setEnv("XDG_DATA_HOME", dataRoot);
		NodeProcess.setEnv("OPENCODE_TEST_HOME", liveRoot);
		final liveServer = new OpenCodeServer({
			directory: projectRoot,
			dbPath: NodePath.join(liveRoot, "opencodehx-live-config.db"),
			liveConfig: {enabled: true},
		});
		try {
			final response = await(liveServer.app.request("/session", {
				method: "POST",
				headers: {"content-type": "application/json"},
				body: Json.stringify({prompt: "Run with config model.", title: "Server live config"}),
			}));
			final created = requiredRecord(Unknown.fromBoundary(await(jsonResponse(response))), "live config server create");
			eq(UnknownNarrow.string(created.get("id")), "ses_server_1", "live config server session id");
			eq(UnknownNarrow.string(created.get("title")), "Server live config", "live config server session title");
			eq(SmokeFetchStub.liveFetchedUrl(), "https://local-live.example.com/v1/chat/completions", "live config server request URL");
			eq(SmokeFetchStub.liveAuth(), "Bearer local-key", "live config server auth header");
			final requestBody = SmokeFetchStub.liveRequestBody();
			eq(requestBody != null
				&& requestBody.indexOf("Server agent prompt from config.") != -1, true, "live config server agent prompt body");
			eq(requestBody != null && requestBody.indexOf('"name":"write"') == -1, true, "live config server disabled tool omitted");
			final idleStatus = UnknownNarrow.record(Unknown.fromBoundary(await(jsonResponse(await(liveServer.app.request("/session/status"))))));
			eq(idleStatus != null && idleStatus.keys().length == 0, true, "live config server status idle after completion");
			final messages = Unknown.fromBoundary(await(jsonResponse(await(liveServer.app.request("/session/ses_server_1/message")))));
			eq(assistantText(messages, "live config server messages"), "Hello from local live.", "live config server assistant text");
			liveServer.close();
			SmokeFetchStub.restore(originalFetch);
			restoreEnv("XDG_CONFIG_HOME", originalXdgConfig);
			restoreEnv("XDG_DATA_HOME", originalXdgData);
			restoreEnv("OPENCODE_TEST_HOME", originalHome);
		} catch (error:haxe.Exception) {
			liveServer.close();
			SmokeFetchStub.restore(originalFetch);
			restoreEnv("XDG_CONFIG_HOME", originalXdgConfig);
			restoreEnv("XDG_DATA_HOME", originalXdgData);
			restoreEnv("OPENCODE_TEST_HOME", originalHome);
			throw error;
		}
	}

	@:async
	static function appRequestRoutes(server:OpenCodeServer, root:String, workspaceSync:WorkspaceSyncRuntime, syncRuntime:SyncRouteRuntime,
			remoteSync:SyncRouteRuntime):Promise<Void> {
		final health = await(jsonResponse(await(server.app.request("/health"))));
		eq(Reflect.field(health, "service"), "opencodehx", "health service");
		await(configRoute(server, root));
		await(workspaceRemoteHttp());
		await(projectGitInitRoutes(server, root));

		// Parsed PTY route JSON is inspected as a smoke boundary payload here;
		// production PTY request bodies decode through PtyRouteProtocol first.
		final ptyCreated = await(jsonResponse(await(server.app.request("/pty", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({command: "cat", title: "Server PTY"}),
		}))));
		final ptyID = Std.string(Reflect.field(ptyCreated, "id"));
		eq(Reflect.field(ptyCreated, "title"), "Server PTY", "pty created title");
		final ptyList:Dynamic = await(jsonResponse(await(server.app.request("/pty"))));
		eq(Reflect.field(cast ptyList[0], "id"), ptyID, "pty listed id");
		final ptyGet = await(jsonResponse(await(server.app.request('/pty/${ptyID}'))));
		eq(Reflect.field(ptyGet, "status"), "running", "pty get status");
		final ptyUpdated = await(jsonResponse(await(server.app.request('/pty/${ptyID}', {
			method: "PUT",
			headers: {"content-type": "application/json"},
			body: Json.stringify({title: "Renamed PTY", size: {cols: 90, rows: 25}}),
		}))));
		eq(Reflect.field(ptyUpdated, "title"), "Renamed PTY", "pty updated title");
		final ptyDeleted = await(jsonResponse(await(server.app.request('/pty/${ptyID}', {method: "DELETE"}))));
		eq(ptyDeleted, true, "pty delete route");
		final ptyMissing = await(server.app.request('/pty/${ptyID}'));
		eq(Reflect.field(ptyMissing, "status"), 404, "pty missing route");

		final syncReplay = await(jsonResponse(await(server.app.request("/sync/replay", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({
				directory: root,
				events: [
					{
						id: "evt_sync_1",
						type: "item.created.1",
						seq: 0,
						aggregateID: "sync_session_1",
						data: {id: "item_1", name: "one"}
					},
					{
						id: "evt_sync_2",
						type: "item.created.1",
						seq: 1,
						aggregateID: "sync_session_1",
						data: {id: "item_1", name: "two"}
					},
				],
			}),
		}))));
		eq(Reflect.field(syncReplay, "sessionID"), "sync_session_1", "sync replay session id");

		final syncReplayNext = await(jsonResponse(await(server.app.request("/sync/replay", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({
				directory: root,
				events: [
					{
						id: "evt_sync_3",
						type: "item.created.1",
						seq: 2,
						aggregateID: "sync_session_1",
						data: {id: "item_1", name: "three"}
					},
				],
			}),
		}))));
		eq(Reflect.field(syncReplayNext, "sessionID"), "sync_session_1", "sync replay next session id");

		// Parsed sync route JSON is kept as Dynamic only inside this smoke
		// assertion boundary; the production route decodes request JSON into
		// typed SyncRouteRuntime records before using it.
		final syncHistory:Dynamic = await(jsonResponse(await(server.app.request("/sync/history", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({}),
		}))));
		eq(syncHistory.length, 3, "sync history count");
		eq(Reflect.field(cast syncHistory[0], "aggregate_id"), "sync_session_1", "sync history aggregate field");

		final syncTail:Dynamic = await(jsonResponse(await(server.app.request("/sync/history", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({sync_session_1: 1}),
		}))));
		eq(syncTail.length, 1, "sync history known tail count");
		eq(Reflect.field(cast syncTail[0], "seq"), 2, "sync history known tail seq");

		final syncUnknown = await(server.app.request("/sync/replay", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({
				directory: root,
				events: [
					{
						id: "evt_sync_bad",
						type: "unknown.event.1",
						seq: 0,
						aggregateID: "sync_session_bad",
						data: {id: "item_bad"}
					},
				],
			}),
		}));
		eq(Reflect.field(syncUnknown, "status"), 400, "sync unknown status");

		final syncGap = await(server.app.request("/sync/replay", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({
				directory: root,
				events: [
					{
						id: "evt_sync_gap",
						type: "item.created.1",
						seq: 5,
						aggregateID: "sync_session_gap",
						data: {id: "item_gap"}
					},
				],
			}),
		}));
		eq(Reflect.field(syncGap, "status"), 400, "sync gap status");

		final syncStart = await(jsonResponse(await(server.app.request("/sync/start", {method: "POST"}))));
		eq(syncStart, true, "sync start route");
		eq(workspaceSync.isSyncing("wrk_server_1"), true, "workspace sync route started");
		eq(workspaceSync.statuses.length >= 3, true, "workspace sync status transitions");
		eq(workspaceSync.statuses[workspaceSync.statuses.length - 1].status, "connected", "workspace sync connected");
		eq(syncRuntime.events("workspace_session_1").length, 1, "workspace sync pulled remote history");
		eq(workspaceSync.sendLocalHistory("wrk_server_1", "sync_session_1"), "sync_session_1", "workspace sync replay local history");
		eq(remoteSync.events("sync_session_1").length, 3, "workspace sync remote replay count");
		final sseJson = WorkspaceSyncSse.parse('data: {"type":"one","properties":{"ok":true}}\r\n\r\n'
			+ 'data: {"type":"two",\r\ndata: "properties":{"n":2}}\r\n\r\n');
		eq(sseJson.length, 2, "workspace sse json count");
		final sseOne = UnknownNarrow.record(sseJson[0].json);
		final sseOneProperties = sseOne == null ? null : UnknownNarrow.record(sseOne.get("properties"));
		eq(sseOne != null && UnknownNarrow.string(sseOne.get("type")) == "one", true, "workspace sse first json type");
		eq(sseOneProperties != null && UnknownNarrow.bool(sseOneProperties.get("ok")) == true, true, "workspace sse first json property");
		final sseTwo = UnknownNarrow.record(sseJson[1].json);
		final sseTwoProperties = sseTwo == null ? null : UnknownNarrow.record(sseTwo.get("properties"));
		eq(sseTwo != null && UnknownNarrow.string(sseTwo.get("type")) == "two", true, "workspace sse multiline json type");
		eq(sseTwoProperties != null && UnknownNarrow.int32(sseTwoProperties.get("n")) == 2, true, "workspace sse multiline json property");
		final sseFallback = WorkspaceSyncSse.parse("id: abc\nretry: 1500\ndata: hello world\n\n");
		eq(sseFallback.length, 1, "workspace sse fallback count");
		eq(sseFallback[0].fallback != null && sseFallback[0].fallback.data == "hello world", true, "workspace sse fallback data");
		eq(sseFallback[0].fallback != null && sseFallback[0].fallback.id == "abc", true, "workspace sse fallback id");
		eq(sseFallback[0].fallback != null && sseFallback[0].fallback.retry == 1500, true, "workspace sse fallback retry");
		eq(WorkspaceSyncRuntime.reconnectDelayMs(0), 1000, "workspace sync reconnect first delay");
		eq(WorkspaceSyncRuntime.reconnectDelayMs(3), 8000, "workspace sync reconnect exponential delay");
		eq(WorkspaceSyncRuntime.reconnectDelayMs(9), 120000, "workspace sync reconnect capped delay");
		final fenceBefore = workspaceSync.waitForSyncFence("wrk_server_1", [{aggregateID: "workspace_session_1", seq: 1}]);
		eq(fenceBefore.synced, false, "workspace sync fence initially pending");
		eq(fenceBefore.message, 'Timed out waiting for sync fence: {"workspace_session_1":1}', "workspace sync fence timeout message");
		final sseApplied = workspaceSync.applyRemoteSse("wrk_server_1",
			'data: {"directory":"/remote/workspace","project":"proj_server","workspace":"remote_workspace","payload":{"type":"server.heartbeat","properties":{}}}\n\n' +
			'data: {"directory":"/remote/workspace","project":"proj_server","workspace":"remote_workspace","payload":{"type":"sync","syncEvent":{"id":"evt_workspace_remote_2","type":"item.created.1","seq":1,"aggregateID":"workspace_session_1","data":{"id":"remote_item","name":"remote-two"}}}}\n\n');
		eq(sseApplied, 1, "workspace sync sse replay count");
		eq(syncRuntime.events("workspace_session_1").length, 2, "workspace sync sse pulled event");
		eq(workspaceSync.forwardedEvents.length, 2, "workspace sync sse forwarded events");
		eq(workspaceSync.forwardedEvents[0].workspace, "wrk_server_1", "workspace sync sse local workspace id");
		final fenceAfter = workspaceSync.waitForSyncFence("wrk_server_1", [{aggregateID: "workspace_session_1", seq: 1}]);
		eq(fenceAfter.synced, true, "workspace sync fence satisfied after sse replay");
		final sseFailure = workspaceSync.applyRemoteSse("wrk_server_1",
			'data: {"directory":"/remote/workspace","project":"proj_server","workspace":"remote_workspace","payload":{"type":"sync","syncEvent":{"id":"evt_workspace_remote_gap","type":"item.created.1","seq":3,"aggregateID":"workspace_session_1","data":{"id":"remote_item","name":"gap"}}}}\n\n');
		eq(sseFailure, 0, "workspace sync sse failed replay count");
		eq(workspaceSync.failures.length, 1, "workspace sync sse failure recorded");
		eq(workspaceSync.failures[0].message.indexOf("Sequence mismatch") != -1, true, "workspace sync sse failure message");
		final streamApplied = await(workspaceSync.applyRemoteSseStream("wrk_server_1", sseStream([
			'data: {"directory":"/remote/workspace","project":"proj_server","workspace":"remote_workspace","payload":{"type":"sync","syncEvent":{"id":"evt_workspace_remote_3",',
			'"type":"item.created.1","seq":2,"aggregateID":"workspace_session_1","data":{"id":"remote_item","name":"remote-three"}}}}\n\n',
			'data: {"directory":"/remote/workspace","project":"proj_server","workspace":"remote_workspace","payload":{"type":"sync","syncEvent":{"id":"evt_workspace_remote_incomplete","type":"item.created.1","seq":3,"aggregateID":"workspace_session_1","data":{"id":"remote_item","name":"incomplete"}}}}',
		]), new AbortControllerWithReason().signal));
		eq(streamApplied, 1, "workspace sync stream replay count");
		eq(syncRuntime.events("workspace_session_1").length, 3, "workspace sync stream complete frames only");
		eq(workspaceSync.statuses[workspaceSync.statuses.length - 1].status, "disconnected", "workspace sync stream disconnected after end");
		final loopCaptures:Array<WorkspaceHttpCapture> = [];
		final loopRemote = new WorkspaceSyncRemoteHttp((url, init) -> {
			loopCaptures.push({url: url, init: init});
			if (url.indexOf("/global/event") != -1)
				return Promise.resolve(new Response(sseStream([
					'data: {"directory":"/remote/workspace","project":"proj_server","workspace":"remote_workspace","payload":{"type":"sync","syncEvent":{"id":"evt_workspace_loop_stream_1","type":"item.created.1","seq":4,"aggregateID":"workspace_session_1","data":{"id":"remote_item","name":"loop-stream"}}}}\n\n',
				]), {
					status: 200
				}));
			if (url.indexOf("/sync/history") != -1)
				return Promise.resolve(new Response(Json.stringify([
					{
						id: "evt_workspace_loop_history_1",
						type: "item.created.1",
						seq: 3,
						aggregate_id: "workspace_session_1",
						data: {id: "remote_item", name: "loop-history"}
					}
				]), {status: 200}));
			return Promise.resolve(new Response("missing", {status: 404}));
		});
		final loopHeaders = jsonHeaders();
		loopHeaders.set("authorization", "Bearer loop-token");
		final loop = await(workspaceSync.runRemoteLoop("wrk_server_1", loopRemote, {url: "https://workspace.test/base", headers: loopHeaders}, 1,
			new AbortControllerWithReason().signal));
		eq(loop.attempts, 1, "workspace sync loop attempts");
		eq(loop.applied, 1, "workspace sync loop stream applied");
		eq(loop.plannedDelays.length, 1, "workspace sync loop planned delay count");
		eq(loop.plannedDelays[0], 1000, "workspace sync loop first reconnect delay");
		eq(loopCaptures[0].url, "https://workspace.test/base/global/event", "workspace sync loop connects sse first");
		eq(loopCaptures[1].url, "https://workspace.test/base/sync/history", "workspace sync loop syncs history");
		eq(loopCaptures[1].init.body, '{"workspace_session_1":2}', "workspace sync loop known seq body");
		eq(syncRuntime.events("workspace_session_1").length, 5, "workspace sync loop history and stream events");
		eq(workspaceSync.statuses[workspaceSync.statuses.length - 1].status, "disconnected", "workspace sync loop disconnected after stream");
		final taskCaptures:Array<WorkspaceHttpCapture> = [];
		final taskRemote = new WorkspaceSyncRemoteHttp((url, init) -> {
			taskCaptures.push({url: url, init: init});
			if (url.indexOf("/global/event") != -1)
				return Promise.resolve(new Response(sseStream([]), {status: 200}));
			if (url.indexOf("/sync/history") != -1)
				return Promise.resolve(new Response(Json.stringify([]), {status: 200}));
			return Promise.resolve(new Response("missing", {status: 404}));
		});
		final scheduled:Array<WorkspaceScheduledTick> = [];
		final task = new WorkspaceSyncBackgroundTask(workspaceSync, "wrk_server_1", taskRemote, {url: "https://workspace.test/base", headers: loopHeaders}, {
			schedule: (delayMs, callback) -> {
				final entry:WorkspaceScheduledTick = {delayMs: delayMs, callback: callback, canceled: false};
				scheduled.push(entry);
				final timer:WorkspaceSyncTaskTimer = {
					delayMs: delayMs,
					cancel: () -> entry.canceled = true,
				};
				return timer;
			},
		});
		eq(task.start(), true, "workspace sync task starts");
		eq(task.start(), false, "workspace sync task dedupes start");
		eq(scheduled[0].delayMs, 0, "workspace sync task immediate first tick");
		scheduled[0].callback();
		await(waitUntil(() -> scheduled.length == 2, "workspace sync task reconnect scheduled"));
		eq(taskCaptures[0].init.signal == task.signal(), true, "workspace sync task owns fetch signal");
		eq(scheduled.length, 2, "workspace sync task schedules reconnect");
		eq(scheduled[1].delayMs, 1000, "workspace sync task reconnect delay");
		task.stop("fixture stop");
		eq(task.state().running, false, "workspace sync task stopped");
		eq(task.state().aborted, true, "workspace sync task aborted");
		eq(scheduled[1].canceled, true, "workspace sync task clears pending timer");
		await(workspaceProxy(workspaceSync));

		final created = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Say hello from the server.", title: "Server fixture"}),
		}))));
		final sessionID = Std.string(Reflect.field(created, "id"));
		eq(sessionID, "ses_server_1", "created session id");
		eq(Reflect.field(created, "title"), "Server fixture", "created title");
		final statusAfterCreate = UnknownNarrow.record(Unknown.fromBoundary(await(jsonResponse(await(server.app.request("/session/status"))))));
		eq(statusAfterCreate != null && statusAfterCreate.keys().length == 0, true, "session status idle after completed create");
		await(permissionRoutes(server, root));
		await(questionRoutes(server, root));

		final invalidCreate = await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: 7}),
		}));
		eq(Reflect.field(invalidCreate, "status"), 400, "invalid create body status");

		final list:Dynamic = await(jsonResponse(await(server.app.request("/session"))));
		eq(Reflect.field(cast list[0], "id"), sessionID, "listed session id");

		final messagesResponse = await(server.app.request('/session/${sessionID}/message?limit=1'));
		eq(Reflect.field(messagesResponse, "status"), 200, "messages status");
		final cursor:Null<String> = messagesResponse.headers.get("x-next-cursor");
		eq(cursor != null, true, "messages cursor");
		final messages = await(jsonResponse(messagesResponse));
		eq(messages.length, 1, "message page length");
		final firstMessage = requiredRecord(requiredArray(Unknown.fromBoundary(messages), "message page").get(0), "message page first");
		final firstMessageInfo = requiredRecord(firstMessage.get("info"), "message page first info");
		final firstMessageID = requiredString(firstMessageInfo, "id", "message page first id");
		final messageDetailResponse = @:await server.app.request('/session/${sessionID}/message/${firstMessageID}');
		final messageDetailBody = @:await jsonResponse(messageDetailResponse);
		final messageDetail = requiredRecord(Unknown.fromBoundary(messageDetailBody), "message detail");
		final messageDetailInfo = requiredRecord(messageDetail.get("info"), "message detail info");
		eq(requiredString(messageDetailInfo, "id", "message detail id"), firstMessageID, "message detail id");
		final messageDetailParts = requiredArray(messageDetail.get("parts"), "message detail parts");
		eq(messageDetailParts.length > 0, true, "message detail parts");
		final missingMessage:Response = @:await server.app.request('/session/${sessionID}/message/msg_missing');
		eq(missingMessage.status, 404, "missing message detail status");
		final missingSessionMessage:Response = @:await server.app.request('/session/ses_missing/message/${firstMessageID}');
		eq(missingSessionMessage.status, 404, "missing session message detail status");

		final deleteMessage = @:await jsonResponse(@:await server.app.request('/session/${sessionID}/message/${firstMessageID}', {
			method: "DELETE",
		}));
		eq(deleteMessage, true, "delete message route");
		final deletedMessageGet:Response = @:await server.app.request('/session/${sessionID}/message/${firstMessageID}');
		eq(deletedMessageGet.status, 404, "deleted message get status");
		final repeatedMessageDelete:Response = @:await server.app.request('/session/${sessionID}/message/${firstMessageID}', {method: "DELETE"});
		eq(repeatedMessageDelete.status, 404, "delete missing message status");
		final afterMessageDeleteResponse = @:await server.app.request('/session/${sessionID}/message');
		final afterMessageDeleteBody = @:await jsonResponse(afterMessageDeleteResponse);
		final afterMessageDelete = requiredArray(Unknown.fromBoundary(afterMessageDeleteBody), "delete message page after");
		eq(afterMessageDelete.length, 1, "delete message remaining count");

		final badCursor = await(server.app.request('/session/${sessionID}/message?limit=1&before=bad'));
		eq(Reflect.field(badCursor, "status"), 400, "bad cursor status");
		final cursorWithoutLimit = await(server.app.request('/session/${sessionID}/message?before=${StringTools.urlEncode(cursor)}'));
		eq(Reflect.field(cursorWithoutLimit, "status"), 400, "message cursor without limit status");
		final missing = await(server.app.request("/session/ses_missing/message?limit=1"));
		eq(Reflect.field(missing, "status"), 404, "missing session status");
		final legacySessionID = seedHighVolumeMessages(NodePath.join(root, "opencodehx.db"), root);
		final legacyResponse = await(server.app.request('/session/${legacySessionID}/message?limit=510'));
		eq(Reflect.field(legacyResponse, "status"), 200, "legacy message limit status");
		final legacyMessages = await(jsonResponse(legacyResponse));
		eq(legacyMessages.length, 510, "legacy message limit count");
		eq(messageResponseID(legacyMessages[0]), "msg_legacy_10", "legacy message page head");
		eq(messageResponseID(legacyMessages[legacyMessages.length - 1]), "msg_legacy_519", "legacy message page tail");

		final selected = await(jsonResponse(await(server.app.request("/tui/select-session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({sessionID: sessionID}),
		}))));
		eq(selected, true, "select session");

		final invalidSelect = await(server.app.request("/tui/select-session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({sessionID: "invalid_session_id"}),
		}));
		eq(Reflect.field(invalidSelect, "status"), 400, "invalid select status");
		final missingFieldSelect = await(server.app.request("/tui/select-session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({}),
		}));
		eq(Reflect.field(missingFieldSelect, "status"), 400, "missing select field status");
		final missingSelect = await(server.app.request("/tui/select-session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({sessionID: "ses_missing"}),
		}));
		eq(Reflect.field(missingSelect, "status"), 404, "missing select session status");

		final second = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Second", title: "unique-search-term-abc"}),
		}))));
		final third = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Third", title: "other-session-xyz"}),
		}))));
		eq(Reflect.field(second, "id"), "ses_server_2", "second session id");
		eq(Reflect.field(third, "id"), "ses_server_3", "third session id");
		final limited:Dynamic = await(jsonResponse(await(server.app.request("/session?limit=2"))));
		eq(limited.length, 2, "session list limit");
		eq(Reflect.field(cast limited[0], "id"), "ses_server_3", "newest limited session");
		final searched:Dynamic = await(jsonResponse(await(server.app.request("/session?search=unique-search"))));
		eq(searched.length, 1, "session search count");
		eq(Reflect.field(cast searched[0], "id"), "ses_server_2", "session search id");
		final future:Dynamic = await(jsonResponse(await(server.app.request("/session?start=9999999999999"))));
		eq(future.length, 0, "future start filter");

		final globalLimitedResponse = await(server.app.request("/experimental/session?limit=2"));
		final globalCursor:Null<String> = globalLimitedResponse.headers.get("x-next-cursor");
		eq(globalCursor != null, true, "global session cursor");
		final globalLimited:Dynamic = await(jsonResponse(globalLimitedResponse));
		eq(globalLimited.length, 2, "global session list limit");
		eq(Reflect.field(cast globalLimited[0], "id"), "ses_server_3", "global newest session");
		final globalProject = Reflect.field(cast globalLimited[0], "project");
		eq(Reflect.field(globalProject, "id"), "global", "global project id");
		eq(Reflect.field(globalProject, "worktree"), root, "global project worktree");
		final globalNext:Dynamic = await(jsonResponse(await(server.app.request('/experimental/session?limit=10&cursor=${globalCursor}'))));
		eq(globalNext.length, 1, "global cursor page size");
		eq(Reflect.field(cast globalNext[0], "id"), "ses_server_1", "global cursor next id");
		final globalSearch:Dynamic = await(jsonResponse(await(server.app.request("/experimental/session?search=other-session"))));
		eq(globalSearch.length, 1, "global search count");
		eq(Reflect.field(cast globalSearch[0], "id"), "ses_server_3", "global search id");
		final archivedCreated = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Archived", title: "archived-session"}),
		}))));
		final archivedID = Std.string(Reflect.field(archivedCreated, "id"));
		final archivedPatch = await(jsonResponse(await(server.app.request('/session/${archivedID}', {
			method: "PATCH",
			headers: {"content-type": "application/json"},
			body: Json.stringify({time: {archived: 12345}}),
		}))));
		eq(Reflect.field(archivedPatch, "id"), archivedID, "archive patch session id");
		final archivedDefault:Dynamic = await(jsonResponse(await(server.app.request("/experimental/session?search=archived-session"))));
		eq(archivedDefault.length, 0, "global archived excluded by default");
		final archivedIncluded:Dynamic = await(jsonResponse(await(server.app.request("/experimental/session?search=archived-session&archived=true"))));
		eq(archivedIncluded.length, 1, "global archived included when requested");
		eq(Reflect.field(cast archivedIncluded[0], "id"), archivedID, "global archived included id");

		final alternateDirectory = NodePath.join(root, "alternate-workspace");
		final alternateResponse = @:await server.app.request("/session", {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"x-opencode-directory": StringTools.urlEncode(alternateDirectory),
			},
			body: Json.stringify({prompt: "Alternate", title: "alternate-directory-session"}),
		});
		final alternate = @:await jsonResponse(alternateResponse);
		final alternateID = Std.string(Reflect.field(alternate, "id"));
		eq(Reflect.field(alternate, "directory"), alternateDirectory, "create session routing directory");
		final directoryFilteredResponse = @:await server.app.request('/session?directory=${StringTools.urlEncode(root)}');
		final directoryFiltered:Dynamic = @:await jsonResponse(directoryFilteredResponse);
		final directoryIDs = responseIDs(directoryFiltered);
		eq(directoryIDs.indexOf(sessionID) != -1, true, "session directory filter keeps root session");
		eq(directoryIDs.indexOf(alternateID), -1, "session directory filter excludes alternate directory");

		final childResponse = @:await server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Child", title: "child-session", parentID: sessionID}),
		});
		final child = requiredRecord(Unknown.fromBoundary(@:await jsonResponse(childResponse)), "create child session");
		final childID = requiredString(child, "id", "create child session id");
		eq(requiredString(child, "parentID", "create child parent id"), sessionID, "create child parent id");
		final secondChildResponse = @:await server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Second child", title: "second-child-session", parentID: sessionID}),
		});
		final secondChild = requiredRecord(Unknown.fromBoundary(@:await jsonResponse(secondChildResponse)), "create second child session");
		final secondChildID = requiredString(secondChild, "id", "create second child session id");
		final parentDetail = requiredRecord(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request('/session/${sessionID}'))),
			"session get parent");
		eq(requiredString(parentDetail, "id", "session get parent id"), sessionID, "session get parent id");
		eq(requiredString(parentDetail, "title", "session get parent title"), "Server fixture", "session get parent title");
		final childDetail = requiredRecord(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request('/session/${childID}'))), "session get child");
		eq(requiredString(childDetail, "parentID", "session get child parent id"), sessionID, "session get child parent id");
		final children = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request('/session/${sessionID}/children'))),
			"session children");
		final childrenIDs = responseIDsFromArray(children);
		eq(childrenIDs[0], secondChildID, "session children newest first");
		eq(childrenIDs[1], childID, "session children includes first child");
		eq(childrenIDs.indexOf(alternateID), -1, "session children excludes unrelated session");
		final childChildren = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request('/session/${childID}/children'))),
			"session child children");
		eq(childChildren.length, 0, "session child has no children");
		final missingGet:Response = @:await server.app.request("/session/ses_missing");
		eq(missingGet.status, 404, "missing session get status");
		final missingChildren:Response = @:await server.app.request("/session/ses_missing/children");
		eq(missingChildren.status, 404, "missing session children status");
		final rootsResponse = @:await server.app.request("/session?roots=true");
		final roots:Dynamic = @:await jsonResponse(rootsResponse);
		final rootIDs = responseIDs(roots);
		eq(rootIDs.indexOf(sessionID) != -1, true, "root filter keeps root session");
		eq(rootIDs.indexOf(childID), -1, "root filter excludes child session");
		eq(rootIDs.indexOf(secondChildID), -1, "root filter excludes second child session");

		final aborted = await(jsonResponse(await(server.app.request('/session/${sessionID}/abort', {method: "POST"}))));
		eq(aborted, true, "abort route");
		final missingAbort:Response = await(server.app.request("/session/ses_missing/abort", {method: "POST"}));
		eq(missingAbort.status, 404, "missing abort status");
		final deleteParent = requiredRecord(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Delete parent", title: "delete-parent-session"}),
		}))), "delete parent session");
		final deleteParentID = requiredString(deleteParent, "id", "delete parent session id");
		final deleteChild = requiredRecord(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Delete child", title: "delete-child-session", parentID: deleteParentID}),
		}))), "delete child session");
		final deleteChildID = requiredString(deleteChild, "id", "delete child session id");
		eq(requiredString(deleteChild, "parentID", "delete child parent id"), deleteParentID, "delete child parent id");
		final deleted = @:await jsonResponse(@:await server.app.request('/session/${deleteParentID}', {method: "DELETE"}));
		eq(deleted, true, "delete session route");
		final deletedParentGet:Response = @:await server.app.request('/session/${deleteParentID}');
		eq(deletedParentGet.status, 404, "deleted parent get status");
		final deletedChildGet:Response = @:await server.app.request('/session/${deleteChildID}');
		eq(deletedChildGet.status, 404, "deleted child cascade status");
		final deletedMessages:Response = @:await server.app.request('/session/${deleteParentID}/message');
		eq(deletedMessages.status, 404, "deleted session messages status");
		final deletedChildren:Response = @:await server.app.request('/session/${deleteParentID}/children');
		eq(deletedChildren.status, 404, "deleted session children status");
		final repeatedDelete:Response = @:await server.app.request('/session/${deleteParentID}', {method: "DELETE"});
		eq(repeatedDelete.status, 404, "delete missing session status");
		final afterDelete = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/session?limit=200"))),
			"session list after delete");
		final afterDeleteIDs = responseIDsFromArray(afterDelete);
		eq(afterDeleteIDs.indexOf(deleteParentID), -1, "session list excludes deleted parent");
		eq(afterDeleteIDs.indexOf(deleteChildID), -1, "session list excludes deleted child");

		final eventResponse = @:await server.app.request("/event");
		final eventText = @:await readSseUntil(eventResponse, '"type":"server.heartbeat"', 80);
		eq(eventText.indexOf('"type":"server.connected"') != -1, true, "sse connected event");
		eq(eventText.indexOf('"type":"server.heartbeat"') != -1, true, "sse heartbeat event");
		eq(eventText.indexOf('"type":"session.created"') != -1, true, "sse session event");
		eq(eventText.indexOf('"type":"session.status"') != -1, true, "sse session status event");
		eq(eventText.indexOf('"type":"session.idle"') != -1, true, "sse session idle event");

		final liveEventResponse = @:await server.app.request("/event");
		final liveCreateResponse = @:await server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Fourth", title: "live-event-session"}),
		});
		final liveCreated = @:await jsonResponse(liveCreateResponse);
		final liveSessionID = Std.string(Reflect.field(liveCreated, "id"));
		eq(StringTools.startsWith(liveSessionID, "ses_server_"), true, "live event session id");
		final liveEventPattern = '"sessionID":"' + liveSessionID + '"';
		final liveEventText = @:await readSseUntil(liveEventResponse, liveEventPattern, 120);
		eq(liveEventText.indexOf(liveEventPattern) != -1, true, "sse live session event");

		final firstProjectDir = NodePath.join(root, "global-first-project");
		final secondProjectDir = NodePath.join(root, "global-second-project");
		initCommittedRepo(firstProjectDir, "# first\n");
		initCommittedRepo(secondProjectDir, "# second\n");
		final firstProjectSession = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"x-opencode-directory": StringTools.urlEncode(firstProjectDir),
			},
			body: Json.stringify({prompt: "First project", title: "first-project-session"}),
		}))));
		final secondProjectSession = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"x-opencode-directory": StringTools.urlEncode(secondProjectDir),
			},
			body: Json.stringify({prompt: "Second project", title: "second-project-session"}),
		}))));
		final firstProjectSessionID = Std.string(Reflect.field(firstProjectSession, "id"));
		final secondProjectSessionID = Std.string(Reflect.field(secondProjectSession, "id"));
		final multiProjectGlobal:Dynamic = await(jsonResponse(await(server.app.request("/experimental/session?limit=200"))));
		final firstProjectItem = responseByID(multiProjectGlobal, firstProjectSessionID);
		final secondProjectItem = responseByID(multiProjectGlobal, secondProjectSessionID);
		neq(firstProjectItem, null, "global multi-project first session listed");
		neq(secondProjectItem, null, "global multi-project second session listed");
		final firstProjectMeta = Reflect.field(firstProjectItem, "project");
		final secondProjectMeta = Reflect.field(secondProjectItem, "project");
		neq(Reflect.field(firstProjectMeta, "id"), Reflect.field(secondProjectMeta, "id"), "global multi-project distinct project ids");
		eq(Reflect.field(firstProjectMeta, "worktree"), firstProjectDir, "global first project worktree");
		eq(Reflect.field(secondProjectMeta, "worktree"), secondProjectDir, "global second project worktree");
	}

	@:async
	static function permissionRoutes(server:OpenCodeServer, root:String):Promise<Void> {
		final rootContext = InstanceRuntime.fromDirectory(root);
		if (rootContext == null)
			throw "permission route root context";
		final rootService = PermissionAsyncRuntime.forContext(rootContext);
		final rootPromise = rootService.ask({
			sessionID: "ses_permission_root",
			permission: "write",
			patterns: ["server-permission.txt"],
			metadata: ToolPermissionMetadata.empty(),
			always: ["server-permission.txt"],
			ruleset: [],
			tool: {
				messageID: "msg_permission_root",
				callID: "call_permission_root"
			},
		});
		final listRaw = Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/permission")));
		final list = requiredArray(listRaw, "permission route list");
		eq(list.length, 1, "permission route list count");
		final first = requiredRecord(list.get(0), "permission route first");
		final requestID = requiredString(first, "id", "permission route request id");
		eq(requiredString(first, "sessionID", "permission route session"), "ses_permission_root", "permission route session id");
		eq(requiredString(first, "permission", "permission route permission"), "write", "permission route permission kind");
		final patterns = requiredArray(first.get("patterns"), "permission route patterns");
		eq(UnknownNarrow.string(patterns.get(0)), "server-permission.txt", "permission route pattern");
		final tool = requiredRecord(first.get("tool"), "permission route tool");
		eq(requiredString(tool, "callID", "permission route tool call"), "call_permission_root", "permission route tool call id");

		final invalidReply = @:await server.app.request('/permission/${requestID}/reply', {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({reply: 1}),
		});
		eq(invalidReply.status, 400, "permission route invalid reply");
		final unknownRequest = @:await jsonResponse(@:await server.app.request("/permission/per_unknown/reply", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({reply: "once"}),
		}));
		eq(unknownRequest, true, "permission route unknown request no-op");
		final reply = @:await jsonResponse(@:await server.app.request('/permission/${requestID}/reply', {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({reply: "once"}),
		}));
		eq(reply, true, "permission route once response");
		eq(@:await rootPromise, true, "permission route once resolves promise");
		final emptyList = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/permission"))), "permission route empty list");
		eq(emptyList.length, 0, "permission route once clears list");

		final unknownReplyPromise = rootService.ask({
			sessionID: "ses_permission_unknown_reply",
			permission: "bash",
			patterns: ["danger"],
			metadata: ToolPermissionMetadata.empty(),
			always: ["danger"],
			ruleset: [],
		});
		final unknownReplyList = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/permission"))),
			"permission route unknown reply list");
		final unknownReplyID = requiredString(requiredRecord(unknownReplyList.get(0), "permission route unknown reply first"), "id",
			"permission route unknown reply id");
		final unknownReply = @:await jsonResponse(@:await server.app.request('/permission/${unknownReplyID}/reply', {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({reply: "later"}),
		}));
		eq(unknownReply, true, "permission route unknown reply response");
		eq(@:await permissionRejection(unknownReplyPromise), "rejected", "permission route unknown reply rejects pending session");

		final alwaysOne = rootService.ask({
			id: "per_always_1",
			sessionID: "ses_permission_always",
			permission: "write",
			patterns: ["always.txt"],
			metadata: ToolPermissionMetadata.empty(),
			always: ["always.txt"],
			ruleset: [],
		});
		final alwaysTwo = rootService.ask({
			id: "per_always_2",
			sessionID: "ses_permission_always",
			permission: "write",
			patterns: ["always.txt"],
			metadata: ToolPermissionMetadata.empty(),
			always: ["always.txt"],
			ruleset: [],
		});
		final alwaysReply = @:await jsonResponse(@:await server.app.request("/permission/per_always_1/reply", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({reply: "always"}),
		}));
		eq(alwaysReply, true, "permission route always response");
		eq(@:await alwaysOne, true, "permission route always first resolves");
		eq(@:await alwaysTwo, true, "permission route always matching resolves");
		eq(@:await rootService.ask({
			sessionID: "ses_permission_always",
			permission: "write",
			patterns: ["always.txt"],
			metadata: ToolPermissionMetadata.empty(),
			always: ["always.txt"],
			ruleset: [],
		}), true, "permission route always persists approval");

		final alternate = NodePath.join(root, "permission-route-alt");
		Fs.mkdirSync(alternate, {recursive: true});
		final alternateContext = InstanceRuntime.fromDirectory(alternate);
		if (alternateContext == null)
			throw "permission route alternate context";
		final alternateService = PermissionAsyncRuntime.forContext(alternateContext);
		final rejected = alternateService.ask({
			sessionID: "ses_permission_alt",
			permission: "edit",
			patterns: ["alt.txt"],
			metadata: ToolPermissionMetadata.empty(),
			always: ["alt.txt"],
			ruleset: [],
		});
		final rootAfterAlt = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/permission"))),
			"permission route root isolated");
		eq(rootAfterAlt.length, 0, "permission route root isolation");
		final alternateList = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/permission", {
			headers: {"x-opencode-directory": StringTools.urlEncode(alternate)},
		}))), "permission route alternate list");
		eq(alternateList.length, 1, "permission route alternate count");
		final alternateID = requiredString(requiredRecord(alternateList.get(0), "permission route alternate first"), "id", "permission route alternate id");
		final reject = @:await jsonResponse(@:await server.app.request('/permission/${alternateID}/reply', {
			method: "POST",
			headers: {"content-type": "application/json", "x-opencode-directory": StringTools.urlEncode(alternate)},
			body: Json.stringify({reply: "reject", message: "Use a safer file."}),
		}));
		eq(reject, true, "permission route reject response");
		eq(@:await permissionRejection(rejected), "corrected", "permission route reject promise");
	}

	@:async
	static function questionRoutes(server:OpenCodeServer, root:String):Promise<Void> {
		final rootContext = InstanceRuntime.fromDirectory(root);
		if (rootContext == null)
			throw "question route root context";
		final rootService = QuestionRuntime.forContext(rootContext);
		final rootPromise = rootService.ask({
			sessionID: SessionID.make("ses_question_root"),
			questions: [serverQuestion("Root question?", "Root", ["Approve", "Skip"])],
			tool: {messageID: MessageID.make("msg_question_root"), callID: "call_question_root"},
		});
		final listRaw = Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/question")));
		final list = requiredArray(listRaw, "question route list");
		eq(list.length, 1, "question route list count");
		final first = requiredRecord(list.get(0), "question route first");
		final requestID = requiredString(first, "id", "question route request id");
		eq(requiredString(first, "sessionID", "question route session"), "ses_question_root", "question route session id");
		final questions = requiredArray(first.get("questions"), "question route questions");
		final firstQuestion = requiredRecord(questions.get(0), "question route question");
		eq(requiredString(firstQuestion, "question", "question route text"), "Root question?", "question route question text");
		final tool = requiredRecord(first.get("tool"), "question route tool");
		eq(requiredString(tool, "callID", "question route tool call"), "call_question_root", "question route tool call id");

		final invalidReply = @:await server.app.request('/question/${requestID}/reply', {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({answers: "Approve"}),
		});
		eq(invalidReply.status, 400, "question route invalid reply");
		final unknownReply = @:await jsonResponse(@:await server.app.request("/question/que_unknown/reply", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({answers: [["Missing"]]}),
		}));
		eq(unknownReply, true, "question route unknown reply no-op");
		final reply = @:await jsonResponse(@:await server.app.request('/question/${requestID}/reply', {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({answers: [["Approve"]]}),
		}));
		eq(reply, true, "question route reply response");
		eq(questionAnswers(@:await rootPromise), "Approve", "question route reply resolves promise");
		final emptyList = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/question"))), "question route empty list");
		eq(emptyList.length, 0, "question route reply clears list");

		final alternate = NodePath.join(root, "question-route-alt");
		Fs.mkdirSync(alternate, {recursive: true});
		final alternateContext = InstanceRuntime.fromDirectory(alternate);
		if (alternateContext == null)
			throw "question route alternate context";
		final alternateService = QuestionRuntime.forContext(alternateContext);
		final rejected = alternateService.ask({
			sessionID: SessionID.make("ses_question_alt"),
			questions: [serverQuestion("Alt question?", "Alt", ["Reject"])],
		});
		final rootAfterAlt = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/question"))), "question route root isolated");
		eq(rootAfterAlt.length, 0, "question route root isolation");
		final alternateList = requiredArray(Unknown.fromBoundary(@:await jsonResponse(@:await server.app.request("/question", {
			headers: {"x-opencode-directory": StringTools.urlEncode(alternate)},
		}))), "question route alternate list");
		eq(alternateList.length, 1, "question route alternate count");
		final alternateID = requiredString(requiredRecord(alternateList.get(0), "question route alternate first"), "id", "question route alternate id");
		final reject = @:await jsonResponse(@:await server.app.request('/question/${alternateID}/reject', {
			method: "POST",
			headers: {"x-opencode-directory": StringTools.urlEncode(alternate)},
		}));
		eq(reject, true, "question route reject response");
		eq(@:await questionRejection(rejected), "rejected", "question route reject promise");
		final unknownReject = @:await jsonResponse(@:await server.app.request("/question/que_unknown/reject", {
			method: "POST",
			headers: {"x-opencode-directory": StringTools.urlEncode(alternate)},
		}));
		eq(unknownReject, true, "question route unknown reject no-op");
	}

	static function serverQuestion(text:String, header:String, labels:Array<String>):QuestionInfo {
		return {
			question: text,
			header: header,
			options: [for (label in labels) {label: label, description: label}],
		};
	}

	static function questionAnswers(answers:Array<QuestionAnswer>):String {
		final out:Array<String> = [];
		for (answer in answers)
			out.push(answer.join("/"));
		return out.join("|");
	}

	static function questionRejection(promise:Promise<Array<QuestionAnswer>>):Promise<String> {
		return promise.then(_ -> "resolved").catchError(error -> {
			return Std.isOfType(error, QuestionRejectedError) ? "rejected" : "other";
		});
	}

	static function permissionRejection(promise:Promise<Bool>):Promise<String> {
		return promise.then(_ -> "resolved").catchError(error -> {
			if (Std.isOfType(error, PermissionCorrectedError))
				return "corrected";
			return Std.isOfType(error, PermissionRejectedError) ? "rejected" : "other";
		});
	}

	@:async
	static function workspaceRemoteHttp():Promise<Void> {
		eq(WorkspaceSyncRemoteHttp.route("https://workspace.test/base/?query=1#hash", "/sync/history"), "https://workspace.test/base/sync/history",
			"workspace sync route clears query hash");
		final captures:Array<WorkspaceHttpCapture> = [];
		final remote = new WorkspaceSyncRemoteHttp((url, init) -> {
			captures.push({url: url, init: init});
			if (url.indexOf("/global/event") != -1)
				return Promise.resolve(new Response("data: {}\n\n", {status: 200}));
			if (url.indexOf("/sync/history") != -1) {
				if (init.headers.get("x-fail") == "history")
					return Promise.resolve(new Response("bad history", {status: 503}));
				return Promise.resolve(new Response(Json.stringify([
					{
						id: "evt_http_remote_1",
						type: "item.created.1",
						seq: 2,
						aggregate_id: "workspace_session_1",
						data: {id: "remote-http", name: "http"}
					}
				]), {status: 200}));
			}
			if (url.indexOf("/sync/replay") != -1) {
				if (init.headers.get("x-fail") == "replay")
					return Promise.resolve(new Response("bad replay", {status: 502}));
				return Promise.resolve(new Response(Json.stringify({sessionID: "workspace_session_1"}), {status: 200}));
			}
			return Promise.resolve(new Response("missing", {status: 404}));
		});
		final headers = jsonHeaders();
		headers.set("authorization", "Bearer remote-token");
		final controller = new AbortControllerWithReason();
		final stream = await(remote.connectSse("https://workspace.test/base/?stale=1", headers, controller.signal));
		eq(stream != null, true, "workspace sync remote sse body");
		eq(captures[0].url, "https://workspace.test/base/global/event", "workspace sync remote sse url");
		eq(captures[0].init.method, "GET", "workspace sync remote sse method");
		eq(captures[0].init.headers.get("authorization"), "Bearer remote-token", "workspace sync remote sse headers");
		eq(captures[0].init.signal == controller.signal, true, "workspace sync remote sse signal");
		final history = await(remote.syncHistory("https://workspace.test/base/?stale=1", headers, [{aggregateID: "workspace_session_1", seq: 1}],
			controller.signal));
		eq(history.url, "https://workspace.test/base/sync/history", "workspace sync remote history url");
		eq(captures[1].init.method, "POST", "workspace sync remote history method");
		eq(captures[1].init.headers.get("authorization"), "Bearer remote-token", "workspace sync remote history preserves auth");
		eq(captures[1].init.headers.get("content-type"), "application/json", "workspace sync remote history content type");
		eq(captures[1].init.body, '{"workspace_session_1":1}', "workspace sync remote history body");
		eq(captures[1].init.signal == controller.signal, true, "workspace sync remote history signal");
		eq(history.events.length, 1, "workspace sync remote history event count");
		eq(history.events[0].aggregate_id, "workspace_session_1", "workspace sync remote history aggregate");
		final replay = await(remote.replay("https://workspace.test/base/?stale=1", headers, {
			directory: "/remote/workspace",
			events: [
				{
					id: "evt_http_local_1",
					type: "item.created.1",
					seq: 0,
					aggregateID: "workspace_session_1",
					data: Unknown.fromBoundary({id: "local-http", name: "local"})
				}
			],
		}, controller.signal));
		eq(replay.url, "https://workspace.test/base/sync/replay", "workspace sync remote replay url");
		eq(replay.sessionID, "workspace_session_1", "workspace sync remote replay session id");
		eq(captures[2].init.method, "POST", "workspace sync remote replay method");
		eq(captures[2].init.headers.get("authorization"), "Bearer remote-token", "workspace sync remote replay preserves auth");
		eq(captures[2].init.headers.get("content-type"), "application/json", "workspace sync remote replay content type");
		eq(captures[2].init.body.indexOf('"directory":"/remote/workspace"') != -1, true, "workspace sync remote replay directory body");
		eq(captures[2].init.body.indexOf('"aggregateID":"workspace_session_1"') != -1, true, "workspace sync remote replay event body");
		eq(captures[2].init.signal == controller.signal, true, "workspace sync remote replay signal");
		final failingHeaders = jsonHeaders();
		failingHeaders.set("x-fail", "history");
		var failed = false;
		try {
			await(remote.syncHistory("https://workspace.test/base", failingHeaders, []));
		} catch (error:WorkspaceSyncHttpError) {
			failed = true;
			eq(error.status, 503, "workspace sync remote history failure status");
			eq(error.body, "bad history", "workspace sync remote history failure body");
			eq(error.message, "Workspace history HTTP failure: 503 bad history", "workspace sync remote history failure message");
		}
		eq(failed, true, "workspace sync remote history failure thrown");
		final failingReplayHeaders = jsonHeaders();
		failingReplayHeaders.set("x-fail", "replay");
		var replayFailed = false;
		try {
			await(remote.replay("https://workspace.test/base", failingReplayHeaders, {directory: "/remote/workspace", events: []}));
		} catch (error:WorkspaceSyncHttpError) {
			replayFailed = true;
			eq(error.status, 502, "workspace sync remote replay failure status");
			eq(error.body, "bad replay", "workspace sync remote replay failure body");
			eq(error.message, "Workspace replay HTTP failure: 502 bad replay", "workspace sync remote replay failure message");
		}
		eq(replayFailed, true, "workspace sync remote replay failure thrown");
	}

	@:async
	static function workspaceProxy(workspaceSync:WorkspaceSyncRuntime):Promise<Void> {
		eq(WorkspaceProxy.shouldServeLocal("GET", "/session"), true, "workspace proxy local session list");
		eq(WorkspaceProxy.shouldServeLocal("GET", "/session/abc/message"), true, "workspace proxy local session subtree");
		eq(WorkspaceProxy.shouldServeLocal("GET", "/session/status"), false, "workspace proxy forwards session status");
		eq(WorkspaceProxy.shouldServeLocal("POST", "/session"), false, "workspace proxy forwards session writes");
		eq(WorkspaceProxy.proxyUrl("https://workspace.test/base/", "https://local.test/session/abc/message?workspace=wrk_server_1&limit=1#tail"),
			"https://workspace.test/base/session/abc/message?limit=1#tail", "workspace proxy url strips workspace query");
		eq(WorkspaceProxy.websocketUrl("https://workspace.test/base"), "wss://workspace.test/base", "workspace proxy websocket https rewrite");
		eq(WorkspaceProxy.websocketUrl("http://workspace.test/base"), "ws://workspace.test/base", "workspace proxy websocket http rewrite");

		final targetHeaders = new DynamicAccess<String>();
		targetHeaders.set("authorization", "Bearer workspace-target");
		final captures:Array<WorkspaceProxyCapture> = [];
		final request = new Request("https://local.test/session/abc/message?workspace=wrk_server_1&limit=1", {
			method: "POST",
			headers: {
				"content-type": "application/json",
				"connection": "keep-alive",
				"accept-encoding": "gzip",
				"x-opencode-directory": "/local/project",
				"x-opencode-workspace": "wrk_server_1",
			},
			body: '{"ok":true}',
		});
		final response = await(WorkspaceProxy.http(request, "wrk_server_1", {url: "https://workspace.test/base", headers: targetHeaders}, workspaceSync,
			(url, init) -> {
				captures.push({url: url, init: init});
				return Promise.resolve(new Response("proxied", {
					status: 201,
					statusText: "Created",
					headers: {
						"x-opencode-sync": '{"workspace_session_1":4}',
						"content-length": "7",
						"content-encoding": "gzip",
						"x-proxy-result": "ok",
					},
				}));
			}));
		eq(captures[0].url, "https://workspace.test/base/session/abc/message?limit=1", "workspace proxy forwarded url");
		eq(captures[0].init.method, "POST", "workspace proxy forwarded method");
		eq(captures[0].init.body, '{"ok":true}', "workspace proxy forwarded body");
		eq(captures[0].init.headers.get("authorization"), "Bearer workspace-target", "workspace proxy target headers");
		eq(captures[0].init.headers.get("connection"), null, "workspace proxy strips hop header");
		eq(captures[0].init.headers.get("accept-encoding"), null, "workspace proxy strips accept encoding");
		eq(captures[0].init.headers.get("x-opencode-directory"), null, "workspace proxy strips directory header");
		eq(captures[0].init.headers.get("x-opencode-workspace"), null, "workspace proxy strips workspace header");
		eq(Reflect.field(response, "status"), 201, "workspace proxy response status");
		eq(response.headers.get("content-length"), null, "workspace proxy strips response content length");
		eq(response.headers.get("content-encoding"), null, "workspace proxy strips response content encoding");
		eq(response.headers.get("x-proxy-result"), "ok", "workspace proxy preserves response header");
		eq(await(response.text()), "proxied", "workspace proxy response body");

		final timeout = await(WorkspaceProxy.http(new Request("https://local.test/session/abc/action?workspace=wrk_server_1", {method: "POST"}),
			"wrk_server_1", {url: "https://workspace.test/base", headers: null}, workspaceSync, (_, _) -> {
				return Promise.resolve(new Response("late", {
					status: 200,
					headers: {"x-opencode-sync": '{"workspace_session_1":99}'},
				}));
			}));
		eq(Reflect.field(timeout, "status"), 504, "workspace proxy fence timeout status");
		eq(await(timeout.text()), 'Timed out waiting for sync fence: {"workspace_session_1":99}', "workspace proxy fence timeout body");

		final disconnected = new WorkspaceSyncRuntime(new SyncRouteRuntime(["item.created.1"]));
		disconnected.register({
			id: "wrk_disconnected",
			projectID: "proj_server",
			directory: "/remote/workspace",
			activeSessionIDs: ["workspace_session_1"],
		});
		final broken = await(WorkspaceProxy.http(new Request("https://local.test/session/abc/action?workspace=wrk_disconnected", {method: "POST"}),
			"wrk_disconnected", {url: "https://workspace.test/base", headers: null}, disconnected, (_, _) -> {
				return Promise.resolve(new Response("should not fetch", {status: 200}));
			}));
		eq(Reflect.field(broken, "status"), 503, "workspace proxy disconnected status");
		eq(await(broken.text()), "broken sync connection for workspace: wrk_disconnected", "workspace proxy disconnected body");
	}

	@:async
	static function ptyWebSocketRoute(baseUrl:String):Promise<Void> {
		final created = await(fetchJson(baseUrl + "/pty", {
			method: "POST",
			headers: jsonHeaders(),
			body: Json.stringify({command: "cat", title: "Server WebSocket PTY"}),
		}));
		final ptyID = Std.string(Reflect.field(created, "id"));
		final wsUrl = StringTools.replace(baseUrl, "http://", "ws://") + '/pty/${ptyID}/connect';
		final first = await(ptyWebsocket(wsUrl + "?cursor=0", "server-ws\n", "server-ws"));
		eq(first.text.indexOf("server-ws") != -1, true, "pty websocket write output");
		eq(first.cursor >= 0, true, "pty websocket initial cursor");
		final replay = await(ptyWebsocket(wsUrl + "?cursor=0", null, "server-ws"));
		eq(replay.text.indexOf("server-ws") != -1, true, "pty websocket replay output");
		eq(replay.cursor > first.cursor, true, "pty websocket replay cursor advances");
		final tail = await(ptyWebsocket(wsUrl + "?cursor=-1", null, null));
		eq(tail.text.indexOf("server-ws"), -1, "pty websocket tail skips replay");
		eq(tail.cursor >= replay.cursor, true, "pty websocket tail cursor");
		final removed = await(fetchJson(baseUrl + '/pty/${ptyID}', methodInit("DELETE")));
		eq(removed, true, "pty websocket delete route");
	}

	@:async
	static function fetchJson(url:String, ?init:SmokeFetchInit):Promise<Dynamic> {
		final response:Response = init == null ? await(GlobalFetch.response(url)) : await(GlobalFetch.response(url, init));
		return jsonResponse(response);
	}

	@:async
	static function jsonResponse(response:Response):Promise<Dynamic> {
		// Parsed JSON in this smoke is intentionally inspected as an untrusted
		// boundary payload; keep Dynamic local to assertions over response shape.
		return await(response.json());
	}

	@:async
	static function readSseEvents(response:Response, eventCount:Int):Promise<String> {
		final body = WebResponseStreams.body(response);
		if (body == null)
			return "";

		final reader = body.getReader();
		final decoder = new WebTextDecoder();
		var text = "";
		try {
			while (sseEventCount(text) < eventCount) {
				final result = await(reader.read());
				if (result.done)
					break;
				if (result.value != null)
					text += decoder.decode(result.value, {stream: true});
			}
			await(reader.cancel());
			return text;
		} catch (error:Dynamic) {
			// Host stream readers may reject or throw arbitrary JS values.
			// Keep the Dynamic catch inside the smoke SSE boundary, cancel the
			// reader like the old raw finally block, and rethrow the original.
			await(reader.cancel());
			throw error;
		}
	}

	@:async
	static function readSseUntil(response:Response, pattern:String, maxEvents:Int):Promise<String> {
		final body = WebResponseStreams.body(response);
		if (body == null)
			return "";

		final reader = body.getReader();
		final decoder = new WebTextDecoder();
		var text = "";
		try {
			while (text.indexOf(pattern) == -1 && sseEventCount(text) < maxEvents) {
				final result = @:await reader.read();
				if (result.done)
					break;
				if (result.value != null)
					text += decoder.decode(result.value, {stream: true});
			}
			@:await reader.cancel();
			return text;
		} catch (error:Dynamic) {
			@:await reader.cancel();
			throw error;
		}
	}

	static function sseEventCount(text:String):Int {
		var count = 0;
		var offset = 0;
		while (true) {
			final next = text.indexOf("\n\n", offset);
			if (next == -1)
				break;
			count += 1;
			offset = next + 2;
		}
		return count;
	}

	static function waitUntil(check:Void->Bool, label:String, ?timeoutMs:Int):Promise<Void> {
		var timeout = 1000;
		if (timeoutMs != null)
			timeout = timeoutMs;
		return new Promise<Void>((resolve, reject) -> {
			// Promise<Void> needs a zero-arg resolver shape in Haxe, while the
			// JS promise resolves with undefined. Keep the cast in this smoke
			// polling helper.
			final resolveVoid:Void->Void = cast resolve;
			waitUntilTick(check, label, Clock.nowMillis() + timeout, resolveVoid, reject);
		});
	}

	static function waitUntilTick(check:Void->Bool, label:String, end:Float, resolve:Void->Void, reject:Dynamic->Void):Void {
		try {
			if (check()) {
				resolve();
				return;
			}
			if (Clock.nowMillis() > end) {
				reject(new Error('timeout waiting for $label'));
				return;
			}
			WebTimers.setTimeout(() -> waitUntilTick(check, label, end, resolve, reject), 10);
		} catch (error:Dynamic) {
			reject(error);
		}
	}

	@:async
	static function waitForStatus(server:OpenCodeServer, sessionID:String, expected:String):Promise<Void> {
		var attempts = 0;
		while (attempts < 40) {
			final statusRaw = Unknown.fromBoundary(await(jsonResponse(await(server.app.request("/session/status")))));
			final actual = sessionStatus(statusRaw, sessionID);
			if (actual == expected)
				return;
			attempts += 1;
			await(sleep(10));
		}
		throw 'timeout waiting for session ${sessionID} status ${expected}';
	}

	static function sessionStatus(raw:Unknown, sessionID:String):Null<String> {
		final root = UnknownNarrow.record(raw);
		if (root == null)
			return null;
		final item = UnknownNarrow.record(root.get(sessionID));
		if (item == null)
			return null;
		return UnknownNarrow.string(item.get("type"));
	}

	static function requiredRecord(raw:Unknown, label:String):genes.ts.UnknownRecord {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			throw '${label}: expected object';
		return record;
	}

	static function requiredArray(raw:Unknown, label:String):genes.ts.UnknownArray {
		final array = UnknownNarrow.array(raw);
		if (array == null)
			throw '${label}: expected array';
		return array;
	}

	static function requiredString(record:genes.ts.UnknownRecord, field:String, label:String):String {
		final value = UnknownNarrow.string(record.get(field));
		if (value == null)
			throw '${label}: expected string field ${field}';
		return value;
	}

	static function projectListHasWorktree(items:genes.ts.UnknownArray, worktree:String):Bool {
		for (index in 0...items.length) {
			final item = UnknownNarrow.record(items.get(index));
			if (item != null && UnknownNarrow.string(item.get("worktree")) == worktree)
				return true;
		}
		return false;
	}

	static function assistantErrorName(raw:Unknown, label:String):Null<String> {
		final items = UnknownNarrow.array(raw);
		if (items == null)
			throw '${label}: expected message array';
		for (index in 0...items.length) {
			final item = UnknownNarrow.record(items.get(index));
			if (item == null)
				continue;
			final info = UnknownNarrow.record(item.get("info"));
			if (info == null || UnknownNarrow.string(info.get("role")) != "assistant")
				continue;
			final error = UnknownNarrow.record(info.get("error"));
			return error == null ? null : UnknownNarrow.string(error.get("name"));
		}
		return null;
	}

	static function assistantText(raw:Unknown, label:String):Null<String> {
		final items = UnknownNarrow.array(raw);
		if (items == null)
			throw '${label}: expected message array';
		for (itemIndex in 0...items.length) {
			final item = UnknownNarrow.record(items.get(itemIndex));
			if (item == null)
				continue;
			final info = UnknownNarrow.record(item.get("info"));
			if (info == null || UnknownNarrow.string(info.get("role")) != "assistant")
				continue;
			final parts = UnknownNarrow.array(item.get("parts"));
			if (parts == null)
				continue;
			for (partIndex in 0...parts.length) {
				final part = UnknownNarrow.record(parts.get(partIndex));
				if (part != null && UnknownNarrow.string(part.get("type")) == "text")
					return UnknownNarrow.string(part.get("text"));
			}
		}
		return null;
	}

	static function sleep(ms:Int):Promise<Bool> {
		return new Promise<Bool>((resolve, _) -> {
			WebTimers.setTimeout(() -> resolve(true), ms);
		});
	}

	static function restoreEnv(key:String, value:Null<String>):Void {
		if (value == null)
			NodeProcess.unsetEnv(key);
		else
			NodeProcess.setEnv(key, value);
	}

	static function ptyWebsocket(url:String, ?message:String, ?expected:String):Promise<PtyWebSocketResult> {
		return new Promise<PtyWebSocketResult>((resolve, reject) -> {
			final socket = new WebSocket(url);
			var text = "";
			var cursor = -1;
			var done = false;
			final timeout = WebTimers.setTimeout(() -> {
				done = true;
				socket.close();
				reject(new Error("pty websocket timed out"));
			}, 1000);

			function finish():Void {
				if (done)
					return;
				done = true;
				WebTimers.clearTimeout(timeout);
				socket.close();
				resolve({text: text, cursor: cursor});
			}

			socket.onOpen("open", () -> {
				if (message != null)
					socket.send(message);
			});
			socket.onMessage("message", (data, _) -> {
				final payload = websocketPayloadText(data);
				if (payload.length > 0 && payload.charCodeAt(0) == 0)
					cursor = websocketCursor(payload);
				else
					text += payload;
				if (cursor >= 0 && (expected == null || text.indexOf(expected) != -1))
					finish();
			});
			socket.onError("error", error -> {
				done = true;
				WebTimers.clearTimeout(timeout);
				reject(error);
			});
		});
	}

	static function websocketPayloadText(data:Unknown):String {
		if (WebBinary.isString(data))
			return WebBinary.string(data);
		if (WebBinary.isArrayBuffer(data))
			return NodeBuffer.fromBytesUtf8(new Uint8Array(cast WebBinary.arrayBuffer(data)));
		if (WebArrayBuffer.isView(data)) {
			final view = WebBinary.arrayBufferView(data);
			final bytes = new Uint8Array(cast view.buffer).subarray(view.byteOffset, view.byteOffset + view.byteLength);
			return NodeBuffer.fromBytesUtf8(bytes);
		}
		return Std.string(data);
	}

	static function websocketCursor(payload:String):Int {
		final parsed:Dynamic = Json.parse(payload.substr(1));
		// The control frame shape is produced by PtyService as `{cursor:Int}`.
		// Keep Dynamic local to this smoke assertion boundary.
		return Std.int(Reflect.field(parsed, "cursor"));
	}

	static function methodInit(method:String):SmokeFetchInit {
		return {
			method: method,
			headers: new DynamicAccess<String>(),
			body: "",
		};
	}

	static function jsonHeaders():DynamicAccess<String> {
		final headers = new DynamicAccess<String>();
		headers.set("content-type", "application/json");
		return headers;
	}

	static function sseStream(chunks:Array<String>):WebReadableStream<Uint8Array> {
		final encoder = new WebTextEncoder();
		return new WebReadableStream<Uint8Array>({
			start: (controller:WebReadableStreamDefaultController<Uint8Array>) -> {
				for (chunk in chunks)
					controller.enqueue(encoder.encode(chunk));
				controller.close();
			},
		});
	}

	static function responseIDs(items:Dynamic):Array<String> {
		final out:Array<String> = [];
		for (item in cast(items, Array<Dynamic>)) {
			out.push(Std.string(Reflect.field(item, "id")));
		}
		return out;
	}

	static function responseIDsFromArray(items:genes.ts.UnknownArray):Array<String> {
		final out:Array<String> = [];
		for (index in 0...items.length) {
			final item = requiredRecord(items.get(index), "response id item");
			out.push(requiredString(item, "id", "response id item"));
		}
		return out;
	}

	static function responseByID(items:Dynamic, id:String):Null<Dynamic> {
		for (item in cast(items, Array<Dynamic>)) {
			if (Reflect.field(item, "id") == id)
				return item;
		}
		return null;
	}

	static function instanceServiceIDs(context:InstanceContext):String {
		return [for (service in context.services) service.id].join(",");
	}

	static function initCommittedRepo(dir:String, readme:String):Void {
		Fs.mkdirSync(dir, {recursive: true});
		git(dir, ["init"]);
		git(dir, ["branch", "-M", "main"]);
		Fs.writeFileSync(NodePath.join(dir, "README.md"), readme, "utf8");
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
	}

	static function git(cwd:String, args:Array<String>):Void {
		final result = Git.run(cwd, args);
		if (result.code != 0)
			throw StringTools.trim(result.stderr) == "" ? 'git ${args.join(" ")} failed with code ${result.code}' : StringTools.trim(result.stderr);
	}

	@:async
	static function projectGitInitRoutes(server:OpenCodeServer, root:String):Promise<Void> {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		final plain = NodePath.join(root, "project-init-plain");
		Fs.mkdirSync(plain, {recursive: true});
		final plainReal = Fs.realpathSync(plain);
		final before = ProjectRuntime.fromDirectory(plain).project;
		InstanceRuntime.boot({
			directory: plain,
			worktree: plain,
			project: before,
		});
		final events:Array<opencodehx.project.InstanceRuntime.InstanceEvent> = [];
		final unsubscribe = InstanceRuntime.subscribe(event -> events.push(event));
		try {
			final init = await(jsonResponse(await(server.app.request("/project/git/init", {
				method: "POST",
				headers: {"x-opencode-directory": StringTools.urlEncode(plain)},
			}))));
			eq(Reflect.field(init, "id"), "global", "project init id");
			eq(Reflect.field(init, "vcs"), "git", "project init vcs");
			eq(Reflect.field(init, "worktree"), plainReal, "project init worktree");
			eq(Fs.existsSync(NodePath.join(plain, ".git")), true, "project init created git dir");
			eq(Fs.existsSync(NodePath.join(NodePath.join(plain, ".git"), "opencode")), false, "project init does not create opencode git cache");
			eq(events.length, 1, "project init reload disposes previous instance");
			eq(events[0].directory, plainReal, "project init disposed directory");
			eq(Std.string(events[0].type), "server.instance.disposed", "project init disposed event type");

			final current = await(jsonResponse(await(server.app.request("/project/current", {
				headers: {"x-opencode-directory": StringTools.urlEncode(plain)},
			}))));
			eq(Reflect.field(current, "vcs"), "git", "project current vcs");
			eq(Reflect.field(current, "worktree"), plainReal, "project current worktree");
			final committed = NodePath.join(root, "project-list-committed");
			initCommittedRepo(committed, "# committed project");
			final committedReal = Fs.realpathSync(committed);
			final committedCurrentBody = await(jsonResponse(await(server.app.request("/project/current", {
				headers: {"x-opencode-directory": StringTools.urlEncode(committed)},
			}))));
			final committedCurrent = requiredRecord(Unknown.fromBoundary(committedCurrentBody), "committed project current");
			eq(requiredString(committedCurrent, "worktree", "committed project current worktree"), committedReal, "committed project current worktree");
			final committedID = requiredString(committedCurrent, "id", "committed project current id");
			final projectListBody = await(jsonResponse(await(server.app.request("/project"))));
			final projectList = requiredArray(Unknown.fromBoundary(projectListBody), "project list");
			eq(projectList.length >= 2, true, "project list count");
			eq(projectListHasWorktree(projectList, plainReal), true, "project list plain worktree");
			eq(projectListHasWorktree(projectList, committedReal), true, "project list committed worktree");
			final updatedBody = await(jsonResponse(await(server.app.request('/project/${committedID}', {
				method: "PATCH",
				headers: {
					"content-type": "application/json",
				},
				body: Json.stringify({
					name: "Renamed committed project",
					icon: {
						color: "blue",
					},
					commands: {
						start: "npm test",
					},
				}),
			}))));
			final updated = requiredRecord(Unknown.fromBoundary(updatedBody), "project update");
			eq(requiredString(updated, "id", "project update id"), committedID, "project update id");
			eq(requiredString(updated, "name", "project update name"), "Renamed committed project", "project update name");
			final updatedIcon = requiredRecord(updated.get("icon"), "project update icon");
			eq(requiredString(updatedIcon, "color", "project update icon color"), "blue", "project update icon color");
			final updatedCommands = requiredRecord(updated.get("commands"), "project update commands");
			eq(requiredString(updatedCommands, "start", "project update command start"), "npm test", "project update command start");
			final missingUpdate = await(server.app.request("/project/proj_missing", {
				method: "PATCH",
				headers: {
					"content-type": "application/json",
				},
				body: Json.stringify({name: "Missing"}),
			}));
			eq(missingUpdate.status, 404, "project update missing status");
			final invalidUpdate = await(server.app.request('/project/${committedID}', {
				method: "PATCH",
				headers: {
					"content-type": "application/json",
				},
				body: Json.stringify({name: 42}),
			}));
			eq(invalidUpdate.status, 400, "project update invalid status");
			final reloaded = InstanceRuntime.get(plain);
			if (reloaded == null)
				throw "project init reloaded instance: expected instance context";
			eq(instanceServiceIDs(reloaded).indexOf("snapshot") != -1, true, "project init attaches snapshot service");
			eq(SnapshotRuntime.track(reloaded) != "", true, "project init snapshot track");

			final alreadyGit = await(jsonResponse(await(server.app.request("/project/git/init", {
				method: "POST",
				headers: {"x-opencode-directory": StringTools.urlEncode(plain)},
			}))));
			eq(Reflect.field(alreadyGit, "vcs"), "git", "project init already git vcs");
			eq(events.length, 1, "project init already git does not reload");
			unsubscribe();
			InstanceRuntime.reset();
			ProjectRuntime.reset();
		} catch (error:Dynamic) {
			unsubscribe();
			InstanceRuntime.reset();
			ProjectRuntime.reset();
			throw error;
		}
	}

	static function seedHighVolumeMessages(dbPath:String, root:String):String {
		final store = new SqliteSessionStore(dbPath);
		final sessionID = SessionID.make("ses_legacy_limit");
		try {
			store.upsertProject({id: "proj_server", worktree: root, name: "Server fixture"});
			store.createSession(highVolumeSession(sessionID, root));
			for (index in 0...520) {
				final messageID = MessageID.make('msg_legacy_${index}');
				store.upsertMessage(highVolumeUserMessage(sessionID, messageID, index));
				store.upsertPart(highVolumeTextPart(sessionID, messageID, PartID.make('prt_legacy_${index}'), 'legacy message ${index}'), 1000 + index);
			}
			store.close();
			return sessionID.toString();
		} catch (error:Dynamic) {
			// Dynamic is required at this JS runtime cleanup boundary because
			// SQLite and message codec APIs may throw strings, Haxe exceptions,
			// or JS errors. The seeded data itself stays typed above.
			store.close();
			throw error;
		}
	}

	static function highVolumeSession(sessionID:SessionID, root:String):SessionInfo {
		return {
			id: sessionID,
			slug: "legacy-limit",
			projectID: "proj_server",
			directory: root,
			title: "Legacy limit fixture",
			version: "0.0.0-test",
			time: {
				created: 1000,
				updated: 2000,
			},
		};
	}

	static function highVolumeUserMessage(sessionID:SessionID, messageID:MessageID, index:Int):Info {
		return MessageCodec.decodeInfoRecord({
			id: messageID.toString(),
			sessionID: sessionID.toString(),
			role: "user",
			time: {created: 1000 + index},
			agent: "test",
			model: {providerID: "test", modelID: "test-model"},
			tools: {},
		}, 'legacy-info:${messageID.toString()}');
	}

	static function highVolumeTextPart(sessionID:SessionID, messageID:MessageID, partID:PartID, value:String):Part {
		return MessageCodec.decodePartRecord({
			id: partID.toString(),
			sessionID: sessionID.toString(),
			messageID: messageID.toString(),
			type: "text",
			text: value,
		}, 'legacy-part:${partID.toString()}');
	}

	static function messageResponseID(item:Dynamic):String {
		return Std.string(Reflect.field(Reflect.field(item, "info"), "id"));
	}

	static function serverTraceAttributes():Void {
		final idParams = [
			{param: "sessionID", key: "session.id"},
			{param: "messageID", key: "message.id"},
			{param: "partID", key: "part.id"},
			{param: "projectID", key: "project.id"},
			{param: "providerID", key: "provider.id"},
			{param: "ptyID", key: "pty.id"},
			{param: "permissionID", key: "permission.id"},
			{param: "requestID", key: "request.id"},
			{param: "workspaceID", key: "workspace.id"},
		];
		for (entry in idParams) {
			eq(ServerTrace.paramToAttributeKey(entry.param), entry.key, 'trace param key ${entry.param}');
		}
		eq(ServerTrace.paramToAttributeKey("name"), "opencode.name", "trace param name key");
		eq(ServerTrace.paramToAttributeKey("slug"), "opencode.slug", "trace param slug key");

		final empty = new DynamicAccess<String>();
		final basic = ServerTrace.requestAttributes({method: "GET", url: "http://localhost/session", params: empty});
		eq(basic.get("http.method"), "GET", "trace http method");
		eq(basic.get("http.path"), "/session", "trace http path");

		final query = ServerTrace.requestAttributes({method: "GET", url: "http://localhost/file/search?query=foo&limit=10", params: empty});
		eq(query.get("http.path"), "/file/search", "trace strips query string");

		final routeParams = new DynamicAccess<String>();
		routeParams.set("sessionID", "ses_abc");
		routeParams.set("messageID", "msg_def");
		routeParams.set("partID", "prt_ghi");
		final withParams = ServerTrace.requestAttributes({
			method: "GET",
			url: "http://localhost/session/ses_abc/message/msg_def/part/prt_ghi",
			params: routeParams,
		});
		eq(withParams.get("session.id"), "ses_abc", "trace session id attr");
		eq(withParams.get("message.id"), "msg_def", "trace message id attr");
		eq(withParams.get("part.id"), "prt_ghi", "trace part id attr");
		eq(withParams.get("opencode.sessionID") == null, true, "trace omits raw sessionID attr");
		eq(withParams.get("opencode.messageID") == null, true, "trace omits raw messageID attr");
		eq(withParams.get("opencode.partID") == null, true, "trace omits raw partID attr");

		final noParams = ServerTrace.requestAttributes({method: "POST", url: "http://localhost/config", params: empty});
		eq(noParams.keys().length, 2, "trace no route params");

		final named = new DynamicAccess<String>();
		named.set("name", "exa");
		final mcp = ServerTrace.requestAttributes({method: "POST", url: "http://localhost/mcp/exa/connect", params: named});
		eq(mcp.get("opencode.name"), "exa", "trace namespaced route param");
		eq(mcp.get("name") == null, true, "trace omits bare route param");
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}

	static function neq<T>(actual:T, expected:T, label:String):Void {
		if (actual == expected) {
			throw '$label: did not expect ${expected}';
		}
	}
}
