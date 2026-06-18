package opencodehx.smoke;

import genes.js.Async.await;
import haxe.Json;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.ws.WebSocket;
import opencodehx.host.node.NodePath;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTypes.ServerListener;

class ServerSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-server-"));
		final server = new OpenCodeServer({
			directory: root,
			dbPath: NodePath.join(root, "opencodehx.db"),
		});
		var listener:Null<ServerListener> = null;
		try {
			await(appRequestRoutes(server, root));
			listener = await(server.listen(0, "127.0.0.1"));
			final health = await(fetchJson(listener.url + "/health"));
			eq(Reflect.field(health, "ok"), true, "listener health");
			final echo = await(websocketEcho(StringTools.replace(listener.url, "http://", "ws://") + "/ws", "server-smoke"));
			eq(echo, "server-smoke", "websocket echo");
			await(listener.stop(true));
			server.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
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
		final eventText = await(textResponse(eventResponse));
		eq(eventText.indexOf('"type":"server.connected"') != -1, true, "sse connected event");
		eq(eventText.indexOf('"type":"server.heartbeat"') != -1, true, "sse heartbeat event");
		eq(eventText.indexOf('"type":"session.created"') != -1, true, "sse session event");
	}

	@:async
	static function fetchJson(url:String):Promise<Dynamic> {
		final response:Dynamic = await(Syntax.code("fetch({0})", url));
		return jsonResponse(response);
	}

	@:async
	static function jsonResponse(response:Dynamic):Promise<Dynamic> {
		return await(Syntax.code("{0}.json()", response));
	}

	@:async
	static function textResponse(response:Dynamic):Promise<String> {
		return await(Syntax.code("{0}.text()", response));
	}

	static function websocketEcho(url:String, message:String):Promise<String> {
		return Syntax.code("new Promise((resolve: (value: string) => void, reject: (reason?: any) => void) => {
			const socket: any = new {0}({1});
			const timeout = setTimeout(() => {
				socket.close();
				reject(new Error('websocket echo timed out'));
			}, 1000);
			socket.on('open', () => socket.send({2}));
			socket.on('message', (data: any) => {
				clearTimeout(timeout);
				const text = typeof data === 'string' ? data : data.toString();
				socket.close();
				resolve(text);
			});
			socket.on('error', (error: Error) => {
				clearTimeout(timeout);
				reject(error);
			});
		})", WebSocket, url, message);
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
