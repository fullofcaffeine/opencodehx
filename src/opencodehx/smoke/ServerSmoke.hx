package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.Response;
import js.lib.Error;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.externs.web.WebStreams.WebArrayBuffer;
import opencodehx.externs.web.WebStreams.WebBinary;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.externs.web.WebStreams.WebResponseStreams;
import opencodehx.externs.web.WebStreams.WebTextDecoder;
import opencodehx.externs.ws.WebSocket;
import opencodehx.host.node.NodeBuffer;
import opencodehx.host.node.NodePath;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.sync.SyncRouteRuntime;
import opencodehx.sync.WorkspaceSyncRuntime;
import opencodehx.sync.WorkspaceSyncSse;

typedef PtyWebSocketResult = {
	final text:String;
	final cursor:Int;
}

typedef SmokeFetchInit = {
	final method:String;
	final headers:DynamicAccess<String>;
	final body:String;
}

class ServerSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-server-"));
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
	static function appRequestRoutes(server:OpenCodeServer, root:String, workspaceSync:WorkspaceSyncRuntime, syncRuntime:SyncRouteRuntime,
			remoteSync:SyncRouteRuntime):Promise<Void> {
		final health = await(jsonResponse(await(server.app.request("/health"))));
		eq(Reflect.field(health, "service"), "opencodehx", "health service");

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

		final created = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Say hello from the server.", title: "Server fixture"}),
		}))));
		final sessionID = Std.string(Reflect.field(created, "id"));
		eq(sessionID, "ses_server_1", "created session id");
		eq(Reflect.field(created, "title"), "Server fixture", "created title");

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

		final badCursor = await(server.app.request('/session/${sessionID}/message?limit=1&before=bad'));
		eq(Reflect.field(badCursor, "status"), 400, "bad cursor status");
		final missing = await(server.app.request("/session/ses_missing/message?limit=1"));
		eq(Reflect.field(missing, "status"), 404, "missing session status");

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
		eq(Reflect.field(globalProject, "id"), "proj_server", "global project id");
		eq(Reflect.field(globalProject, "worktree"), root, "global project worktree");
		final globalNext:Dynamic = await(jsonResponse(await(server.app.request('/experimental/session?limit=10&cursor=${globalCursor}'))));
		eq(globalNext.length, 1, "global cursor page size");
		eq(Reflect.field(cast globalNext[0], "id"), "ses_server_1", "global cursor next id");
		final globalSearch:Dynamic = await(jsonResponse(await(server.app.request("/experimental/session?search=other-session"))));
		eq(globalSearch.length, 1, "global search count");
		eq(Reflect.field(cast globalSearch[0], "id"), "ses_server_3", "global search id");

		final aborted = await(jsonResponse(await(server.app.request('/session/${sessionID}/abort', {method: "POST"}))));
		eq(aborted, true, "abort route");

		final eventResponse = await(server.app.request("/event"));
		final eventText = await(readSseEvents(eventResponse, 6));
		eq(eventText.indexOf('"type":"server.connected"') != -1, true, "sse connected event");
		eq(eventText.indexOf('"type":"server.heartbeat"') != -1, true, "sse heartbeat event");
		eq(eventText.indexOf('"type":"session.created"') != -1, true, "sse session event");

		final liveEventResponse = await(server.app.request("/event"));
		final fourth = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Fourth", title: "live-event-session"}),
		}))));
		eq(Reflect.field(fourth, "id"), "ses_server_4", "live event session id");
		final liveEventText = await(readSseEvents(liveEventResponse, 8));
		eq(liveEventText.indexOf('"sessionID":"ses_server_4"') != -1, true, "sse live session event");
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

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
