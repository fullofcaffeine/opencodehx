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
			await(appRequestRoutes(server));
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
	static function appRequestRoutes(server:OpenCodeServer):Promise<Void> {
		final health = await(jsonResponse(await(server.app.request("/health"))));
		eq(Reflect.field(health, "service"), "opencodehx", "health service");

		final created = await(jsonResponse(await(server.app.request("/session", {
			method: "POST",
			headers: {"content-type": "application/json"},
			body: Json.stringify({prompt: "Say hello from the server.", title: "Server fixture"}),
		}))));
		final sessionID = Std.string(Reflect.field(created, "id"));
		eq(sessionID, "ses_server_one", "created session id");
		eq(Reflect.field(created, "title"), "Server fixture", "created title");

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

		final aborted = await(jsonResponse(await(server.app.request('/session/${sessionID}/abort', {method: "POST"}))));
		eq(aborted, true, "abort route");

		final eventResponse = await(server.app.request("/event"));
		final eventText = await(textResponse(eventResponse));
		eq(eventText.indexOf('"type":"server.connected"') != -1, true, "sse connected event");
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
