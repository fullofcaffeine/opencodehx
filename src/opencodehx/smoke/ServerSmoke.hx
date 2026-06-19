package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import haxe.Json;
import js.Syntax;
import js.html.Response;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.ws.WebSocket;
import opencodehx.host.node.NodePath;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTypes.ServerListener;

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
		final server = new OpenCodeServer({
			directory: root,
			dbPath: NodePath.join(root, "opencodehx.db"),
			syncTypes: ["item.created.1"],
		});
		var listener:Null<ServerListener> = null;
		try {
			await(appRequestRoutes(server, root));
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
	static function appRequestRoutes(server:OpenCodeServer, root:String):Promise<Void> {
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

		final syncStart = await(jsonResponse(await(server.app.request("/sync/start", {method: "POST"}))));
		eq(syncStart, true, "sync start route");

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
		final cursor = Syntax.code("{0}.headers.get('x-next-cursor')", messagesResponse);
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
		final globalCursor = Syntax.code("{0}.headers.get('x-next-cursor')", globalLimitedResponse);
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
		final response:Response = init == null ? await(Syntax.code("fetch({0})", url)) : await(Syntax.code("fetch({0}, {1})", url, init));
		return jsonResponse(response);
	}

	@:async
	static function jsonResponse(response:Response):Promise<Dynamic> {
		// Parsed JSON in this smoke is intentionally inspected as an untrusted
		// boundary payload; keep Dynamic local to assertions over response shape.
		return await(Syntax.code("{0}.json()", response));
	}

	static function readSseEvents(response:Response, eventCount:Int):Promise<String> {
		return Syntax.code("(async () => {
			const reader = {0}.body?.getReader();
			if (!reader) return '';
			const decoder = new TextDecoder();
			let text = '';
			try {
				while ((text.match(/\\n\\n/g)?.length ?? 0) < {1}) {
					const result = await reader.read();
					if (result.done) break;
					text += decoder.decode(result.value, { stream: true });
				}
				return text;
			} finally {
				await reader.cancel();
			}
		})()", response, eventCount);
	}

	static function ptyWebsocket(url:String, ?message:String, ?expected:String):Promise<PtyWebSocketResult> {
		return Syntax.code("new Promise((resolve: (value: PtyWebSocketResult) => void, reject: (reason?: unknown) => void) => {
			const socket = new {0}({1});
			let text = '';
			let cursor = -1;
			let done = false;
			const timeout = setTimeout(() => {
				done = true;
				socket.close();
				reject(new Error('pty websocket timed out'));
			}, 1000);
			const finish = () => {
				if (done) return;
				done = true;
				clearTimeout(timeout);
				socket.close();
				resolve({ text, cursor });
			};
			socket.on('open', () => {
				if ({2} !== null) socket.send({2});
			});
			socket.on('message', (data: unknown) => {
				let payload: string;
				if (typeof data === 'string') {
					payload = data;
				} else if (data instanceof ArrayBuffer) {
					payload = Buffer.from(data).toString('utf8');
				} else if (ArrayBuffer.isView(data)) {
					payload = Buffer.from(data.buffer, data.byteOffset, data.byteLength).toString('utf8');
				} else {
					payload = String(data);
				}
				if (payload.charCodeAt(0) === 0) {
					cursor = JSON.parse(payload.slice(1)).cursor;
				} else {
					text += payload;
				}
				if (cursor >= 0 && ({3} === null || text.includes({3}))) finish();
			});
			socket.on('error', (error: Error) => {
				done = true;
				clearTimeout(timeout);
				reject(error);
			});
		})", WebSocket, url, message, expected);
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
