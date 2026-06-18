package opencodehx.server;

import genes.js.Async.await;
import haxe.Json;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.hono.Hono;
import opencodehx.externs.hono.Hono.HonoContext;
import opencodehx.externs.hono.NodeWs;
import opencodehx.externs.hono.NodeWs.NodeWebSocketRuntime;
import opencodehx.session.MessageCodec;
import opencodehx.session.SessionID;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.session.SessionProcessor;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.server.ServerTypes.ServerOptions;
import opencodehx.storage.SessionStore;
import opencodehx.storage.SqliteSessionStore;

typedef ServerEvent = {
	final type:String;
	final properties:ServerEventProperties;
}

typedef ServerEventProperties = {
	@:optional final sessionID:String;
}

class OpenCodeServer {
	public final app:Hono;

	final ws:NodeWebSocketRuntime;
	final store:SessionStore;
	final directory:String;
	final events:Array<ServerEvent> = [];
	final sessionOrder:Array<String> = [];

	public function new(options:ServerOptions) {
		directory = options.directory;
		store = new SqliteSessionStore(options.dbPath);
		app = new Hono();
		ws = NodeWs.createNodeWebSocket({app: app});
		routes();
	}

	public function close():Void {
		store.close();
	}

	public function listen(?port:Int, ?hostname:String):Promise<ServerListener> {
		final nextPort = port == null ? 0 : port;
		final nextHostname = hostname == null ? "127.0.0.1" : hostname;
		return NodeHonoAdapter.listen(app, ws, nextHostname, nextPort);
	}

	function routes():Void {
		app.get("/health", c -> json(c, {ok: true, service: "opencodehx"}));
		app.get("/event", c -> eventStream(c));
		app.get("/session", c -> listSessions(c));
		app.post("/session", c -> createSession(c));
		app.get("/session/:sessionID/message", c -> sessionMessages(c));
		app.post("/session/:sessionID/abort", c -> json(c, true));
		app.post("/tui/select-session", c -> selectSession(c));
		app.get("/ws", ws.upgradeWebSocket(Syntax.code("() => ({ onMessage(event: any, socket: any) { socket.send(event.data); } })")));
	}

	@:async
	function createSession(c:HonoContext):Promise<Dynamic> {
		final body:Dynamic = await(Syntax.code("{0}.req.json().catch(() => ({}))", c));
		final prompt = stringField(body, "prompt", "Say hello from the fixture.");
		final title = stringField(body, "title", prompt);
		final result = SessionProcessor.run({
			prompt: prompt,
			directory: directory,
			sessionID: "ses_server_one",
			projectID: "proj_server",
			store: store,
		});
		final info = store.getSession(SessionID.make(result.request.sessionID));
		final encoded = encodeSession(withTitle(info, title));
		if (sessionOrder.indexOf(result.request.sessionID) == -1)
			sessionOrder.push(result.request.sessionID);
		events.push({type: "session.created", properties: {sessionID: result.request.sessionID}});
		return json(c, encoded);
	}

	function listSessions(c:HonoContext):Dynamic {
		final items:Array<Dynamic> = [];
		for (id in sessionOrder) {
			try {
				items.push(encodeSession(store.getSession(SessionID.make(id))));
			} catch (_:Dynamic) {}
		}
		items.reverse();
		return json(c, items);
	}

	function sessionMessages(c:HonoContext):Dynamic {
		final sessionID = param(c, "sessionID");
		if (!hasSession(sessionID))
			return json(c, {error: "Session not found"}, 404);
		final rawLimit = query(c, "limit");
		final limit = parseLimit(rawLimit);
		final before = query(c, "before");
		try {
			final page = before == null
				|| before == "" ? store.pageMessages(SessionID.make(sessionID), limit) : store.pageMessages(SessionID.make(sessionID), limit, before);
			if (page.more) {
				final cursorValue = page.cursor;
				if (cursorValue != null) {
					Syntax.code("{0}.header('x-next-cursor', {1})", c, cursorValue);
					Syntax.code("{0}.header('link', '<' + {1} + '?before=' + encodeURIComponent({2}) + '>; rel=\"next\"')", c,
						"/session/" + sessionID + "/message", cursorValue);
				}
			}
			final encodedItems:Array<Dynamic> = [];
			for (item in page.items) {
				encodedItems.push(MessageCodec.encodeWithParts(item));
			}
			return json(c, encodedItems);
		} catch (_:Dynamic) {
			return json(c, {error: "Invalid message cursor"}, 400);
		}
	}

	@:async
	function selectSession(c:HonoContext):Promise<Dynamic> {
		final body:Dynamic = await(Syntax.code("{0}.req.json().catch(() => ({}))", c));
		final sessionID = stringField(body, "sessionID", "");
		if (!StringTools.startsWith(sessionID, "ses_"))
			return json(c, {error: "Invalid session ID"}, 400);
		if (!hasSession(sessionID))
			return json(c, {error: "Session not found"}, 404);
		events.push({type: "session.selected", properties: {sessionID: sessionID}});
		return json(c, true);
	}

	function eventStream(c:HonoContext):Dynamic {
		Syntax.code("{0}.header('Cache-Control', 'no-cache, no-transform')", c);
		Syntax.code("{0}.header('X-Accel-Buffering', 'no')", c);
		var lines = "data: " + Json.stringify({type: "server.connected", properties: {}}) + "\n\n";
		for (event in events)
			lines += "data: " + Json.stringify(event) + "\n\n";
		return Syntax.code("new Response({0}, { headers: { 'content-type': 'text/event-stream' } })", lines);
	}

	function hasSession(sessionID:String):Bool {
		try {
			store.getSession(SessionID.make(sessionID));
			return true;
		} catch (_:Dynamic) {
			return false;
		}
	}

	function withTitle(info:SessionInfo, title:String):SessionInfo {
		final updated:Dynamic = info;
		Reflect.setField(updated, "title", title);
		store.updateSession(cast updated);
		return cast updated;
	}

	static function encodeSession(info:SessionInfo):Dynamic {
		final result:Dynamic = {
			id: info.id.toString(),
			projectID: info.projectID,
			slug: info.slug,
			directory: info.directory,
			title: info.title,
			version: info.version,
			time: {
				created: info.time.created,
				updated: info.time.updated,
			},
		};
		if (info.workspaceID != null)
			Reflect.setField(result, "workspaceID", info.workspaceID);
		if (info.parentID != null)
			Reflect.setField(result, "parentID", info.parentID.toString());
		return result;
	}

	static function json(c:HonoContext, payload:Dynamic, ?status:Int):Dynamic {
		if (status == null)
			return Syntax.code("{0}.json({1})", c, payload);
		return Syntax.code("{0}.json({1}, {2})", c, payload, status);
	}

	static function param(c:HonoContext, name:String):String {
		return c.req.param(name);
	}

	static function query(c:HonoContext, name:String):Null<String> {
		return Syntax.code("{0}.req.query({1}) ?? null", c, name);
	}

	static function parseLimit(value:Null<String>):Int {
		if (value == null || value == "")
			return 100000;
		final parsed = Std.parseInt(value);
		if (parsed == null || parsed <= 0)
			return 100000;
		return parsed;
	}

	static function stringField(data:Dynamic, name:String, fallback:String):String {
		final value = Reflect.field(data, name);
		if (value == null)
			return fallback;
		return Std.string(value);
	}
}
