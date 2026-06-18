package opencodehx.server;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.Json;
import js.Syntax;
import js.html.Response;
import js.lib.Promise;
import opencodehx.externs.hono.Hono;
import opencodehx.externs.hono.Hono.HonoContext;
import opencodehx.externs.hono.NodeWs;
import opencodehx.externs.hono.NodeWs.NodeWebSocketRuntime;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageError.MessageException;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.server.ServerProtocol.DecodeResult;
import opencodehx.server.ServerProtocol.GlobalSessionResponse;
import opencodehx.server.ServerProtocol.ServerEvent;
import opencodehx.server.ServerProtocol.SessionResponse;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.server.ServerTypes.ServerOptions;
import opencodehx.storage.SessionStore;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.storage.StorageError.StorageException;

class OpenCodeServer {
	public final app:Hono;

	final ws:NodeWebSocketRuntime;
	final store:SessionStore;
	final directory:String;
	final events:Array<ServerEvent> = [];
	final sessionOrder:Array<String> = [];
	var createdCount = 0;

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
		app.get("/experimental/session", c -> listGlobalSessions(c));
		app.post("/session", c -> createSession(c));
		app.get("/session/:sessionID/message", c -> sessionMessages(c));
		app.post("/session/:sessionID/abort", c -> json(c, true));
		app.post("/tui/select-session", c -> selectSession(c));
		app.get("/ws", ws.upgradeWebSocket(Syntax.code("() => ({ onMessage(event: any, socket: any) { socket.send(event.data); } })")));
	}

	@:async
	function createSession(c:HonoContext):Promise<Response> {
		final decoded = ServerProtocol.decodeCreateSession(await(readJson(c)));
		final request = switch decoded {
			case Rejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case Decoded(value):
				value;
		};
		createdCount += 1;
		final sessionID = 'ses_server_${createdCount}';
		final result = SessionProcessor.run({
			prompt: request.prompt,
			directory: directory,
			sessionID: sessionID,
			projectID: "proj_server",
			store: store,
		});
		final info = store.getSession(SessionID.make(result.request.sessionID));
		final updated = ServerProtocol.withTitle(info, request.title, 1002 + createdCount);
		store.updateSession(updated);
		final encoded = ServerProtocol.encodeSession(updated);
		if (sessionOrder.indexOf(result.request.sessionID) == -1)
			sessionOrder.push(result.request.sessionID);
		events.push(ServerProtocol.sessionEvent("session.created", result.request.sessionID));
		return json(c, encoded);
	}

	function listSessions(c:HonoContext):Response {
		final queryOptions = ServerProtocol.decodeSessionListQuery(name -> query(c, name));
		final items:Array<SessionResponse> = [];
		var count = 0;
		final newestFirst = sessionOrder.copy();
		newestFirst.reverse();
		for (id in newestFirst) {
			try {
				final info = store.getSession(SessionID.make(id));
				if (ServerProtocol.matchesSession(info, queryOptions)) {
					items.push(ServerProtocol.encodeSession(info));
					count += 1;
				}
				if (count >= queryOptions.limit)
					break;
			} catch (_:StorageException) {}
		}
		return json(c, items);
	}

	function listGlobalSessions(c:HonoContext):Response {
		final queryOptions = ServerProtocol.decodeSessionListQuery(name -> query(c, name));
		final items:Array<GlobalSessionResponse> = [];
		final newestFirst = sessionOrder.copy();
		newestFirst.reverse();
		for (id in newestFirst) {
			try {
				final info = store.getSession(SessionID.make(id));
				if (ServerProtocol.matchesGlobalSession(info, queryOptions)) {
					items.push(ServerProtocol.encodeGlobalSession(info));
					if (items.length > queryOptions.limit)
						break;
				}
			} catch (_:StorageException) {}
		}
		final hasMore = items.length > queryOptions.limit;
		final page = hasMore ? items.slice(0, queryOptions.limit) : items;
		if (hasMore && page.length > 0) {
			final tail = page[page.length - 1];
			Syntax.code("{0}.header('x-next-cursor', String({1}))", c, tail.time.updated);
		}
		return json(c, page);
	}

	function sessionMessages(c:HonoContext):Response {
		final sessionID = param(c, "sessionID");
		if (!hasSession(sessionID))
			return json(c, ServerProtocol.error("Session not found"), 404);
		final rawLimit = query(c, "limit");
		final limit = ServerProtocol.decodeSessionListQuery(name -> name == "limit" ? rawLimit : null).limit;
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
			// MessageCodec still emits upstream-shaped anonymous JS records.
			// Keep that Dynamic at the serialization boundary for now; route
			// validation and store access above remain typed.
			final encodedItems:Array<Dynamic> = [];
			for (item in page.items) {
				encodedItems.push(MessageCodec.encodeWithParts(item));
			}
			return json(c, encodedItems);
		} catch (_:MessageException) {
			return json(c, ServerProtocol.error("Invalid message cursor"), 400);
		} catch (_:StorageException) {
			return json(c, ServerProtocol.error("Invalid message cursor"), 400);
		}
	}

	@:async
	function selectSession(c:HonoContext):Promise<Response> {
		final decoded = ServerProtocol.decodeSelectSession(await(readJson(c)));
		final request = switch decoded {
			case Rejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case Decoded(value):
				value;
		};
		if (!hasSession(request.sessionID))
			return json(c, ServerProtocol.error("Session not found"), 404);
		events.push(ServerProtocol.sessionEvent("session.selected", request.sessionID));
		return json(c, true);
	}

	function eventStream(c:HonoContext):Response {
		Syntax.code("{0}.header('Cache-Control', 'no-cache, no-transform')", c);
		Syntax.code("{0}.header('X-Accel-Buffering', 'no')", c);
		var lines = sseLine(ServerProtocol.connectedEvent());
		lines += sseLine(ServerProtocol.heartbeatEvent());
		for (event in events)
			lines += sseLine(event);
		return Syntax.code("new Response({0}, { headers: { 'content-type': 'text/event-stream' } })", lines);
	}

	function hasSession(sessionID:String):Bool {
		try {
			store.getSession(SessionID.make(sessionID));
			return true;
		} catch (_:StorageException) {
			return false;
		}
	}

	@:async
	static function readJson(c:HonoContext):Promise<Unknown> {
		try {
			// Hono parses untrusted request JSON at the host boundary; callers
			// immediately pass it to ServerProtocol decoders before using fields.
			return await(c.req.json());
		} catch (_:Dynamic) {
			// JS JSON parsing can throw arbitrary host errors here; treating
			// unreadable bodies as an empty unknown object preserves upstream's
			// tolerant route behavior while keeping field access in decoders.
			return Unknown.fromBoundary({});
		}
	}

	static inline function sseLine(event:ServerEvent):String {
		return "data: " + Json.stringify(event) + "\n\n";
	}

	static function json<T>(c:HonoContext, payload:T, ?status:Int):Response {
		if (status == null)
			return Syntax.code("{0}.json({1})", c, payload);
		return Syntax.code("{0}.json({1}, {2})", c, payload, status);
	}

	static function param(c:HonoContext, name:String):String {
		return c.req.param(name);
	}

	static function query(c:HonoContext, name:String):Null<String> {
		return c.req.query(name).orNull();
	}
}
