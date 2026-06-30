package opencodehx.server;

import genes.js.Async.await;
import genes.ts.Unknown;
import js.html.Response;
import js.lib.Promise;
import opencodehx.externs.hono.Hono;
import opencodehx.externs.hono.Hono.HonoContext;
import opencodehx.externs.hono.NodeWs;
import opencodehx.externs.hono.NodeWs.NodeWebSocketHandlerCallbacks;
import opencodehx.externs.hono.NodeWs.NodeWebSocketMessage;
import opencodehx.externs.hono.NodeWs.NodeWebSocketRuntime;
import opencodehx.externs.web.WebStreams.WebArrayBuffer;
import opencodehx.externs.web.WebStreams.WebBinary;
import opencodehx.project.InstanceBootstrapRuntime;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.ProjectRuntime;
import opencodehx.project.ProjectRuntime.ProjectInfo;
import opencodehx.pty.PtyService;
import opencodehx.pty.PtyTypes.PtyConnectHandler;
import opencodehx.pty.PtyTypes.PtyID;
import opencodehx.pty.PtyTypes.PtySocket;
import opencodehx.pty.PtyTypes.PtySocketMessage;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageError.MessageException;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.server.ServerProtocol.DecodeResult;
import opencodehx.server.ServerProtocol.GlobalSessionResponse;
import opencodehx.server.ServerProtocol.ServerEventTypes;
import opencodehx.server.ServerProtocol.SessionResponse;
import opencodehx.server.ServerSessionStatusRuntime;
import opencodehx.server.ServerTypes.ServerLiveAiSdkOptions;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.server.ServerTypes.ServerOptions;
import opencodehx.storage.SessionStore;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.storage.StorageError.StorageException;
import opencodehx.sync.SyncRouteRuntime;
import opencodehx.sync.SyncRouteRuntime.SyncRouteDecode;

typedef ProjectRouteTime = {
	final created:Float;
	final updated:Float;
	@:optional final initialized:Float;
}

typedef ProjectRouteResponse = {
	final id:String;
	final worktree:String;
	final vcs:Null<String>;
	final name:Null<String>;
	final time:ProjectRouteTime;
	final sandboxes:Array<String>;
}

class OpenCodeServer {
	public final app:Hono;

	final ws:NodeWebSocketRuntime;
	final store:SessionStore;
	final directory:String;
	final eventBus = new ServerEventBus();
	final syncRuntime:SyncRouteRuntime;
	final ptyService:PtyService;
	final sessionStatus:ServerSessionStatusRuntime;
	final liveAiSdk:Null<ServerLiveAiSdkOptions>;
	final sessionOrder:Array<String> = [];
	var createdCount = 0;

	static final INTEGER_PATTERN = ~/^-?\d+$/;
	static inline final MAX_SAFE_INTEGER = 9007199254740991.0;

	public function new(options:ServerOptions) {
		directory = options.directory;
		store = new SqliteSessionStore(options.dbPath);
		syncRuntime = options.syncRuntime == null ? new SyncRouteRuntime(options.syncTypes) : options.syncRuntime;
		ptyService = new PtyService(directory);
		sessionStatus = new ServerSessionStatusRuntime(event -> eventBus.publish(event));
		liveAiSdk = options.liveAiSdk;
		app = new Hono();
		ws = NodeWs.createNodeWebSocket({app: app});
		routes();
	}

	public function close():Void {
		ptyService.dispose();
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
		app.get("/session/status", c -> sessionStatuses(c));
		app.get("/experimental/session", c -> listGlobalSessions(c));
		app.get("/project/current", c -> currentProject(c));
		app.post("/project/git/init", c -> initGitProject(c));
		app.post("/session", c -> createSession(c));
		app.patch("/session/:sessionID", c -> updateSession(c));
		app.get("/session/:sessionID/message", c -> sessionMessages(c));
		app.post("/session/:sessionID/abort", c -> abortSession(c));
		app.post("/sync/start", c -> json(c, syncRuntime.start()));
		app.post("/sync/replay", c -> syncReplay(c));
		app.post("/sync/history", c -> syncHistory(c));
		app.post("/tui/select-session", c -> selectSession(c));
		app.get("/pty", c -> json(c, ptyService.list()));
		app.post("/pty", c -> createPty(c));
		app.get("/pty/:ptyID", c -> getPty(c));
		app.put("/pty/:ptyID", c -> updatePty(c));
		app.delete("/pty/:ptyID", c -> removePty(c));
		app.get("/pty/:ptyID/connect", ws.upgradeWebSocket(c -> ptyConnect(c)));
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
		final requestDirectory = routingDirectory(c);
		final project = ProjectRuntime.fromDirectory(requestDirectory, store).project;
		if (liveAiSdk != null)
			return @:await createLiveAiSdkSession(c, request, sessionID, requestDirectory, project.id.toString());
		sessionStatus.busy(sessionID);
		final result = SessionProcessor.run({
			prompt: request.prompt,
			directory: requestDirectory,
			sessionID: sessionID,
			projectID: project.id.toString(),
			store: store,
		});
		final info = store.getSession(SessionID.make(result.request.sessionID));
		final updated = ServerProtocol.withCreateRequest(info, request, requestDirectory, 1002 + createdCount);
		store.updateSession(updated);
		final encoded = ServerProtocol.encodeSession(updated);
		if (sessionOrder.indexOf(result.request.sessionID) == -1)
			sessionOrder.push(result.request.sessionID);
		eventBus.publish(ServerProtocol.sessionEvent(ServerEventTypes.known("session.created"), result.request.sessionID));
		sessionStatus.idle(result.request.sessionID);
		return json(c, encoded);
	}

	@:async
	function createLiveAiSdkSession(c:HonoContext, request:opencodehx.server.ServerProtocol.CreateSessionRequest, sessionID:String, requestDirectory:String,
			projectID:String):Promise<Response> {
		final live = liveAiSdk;
		if (live == null)
			return json(c, ServerProtocol.error("Live AI SDK runtime is not configured"), 500);
		sessionStatus.busy(sessionID);
		try {
			final result = @:await SessionProcessor.runAiSdk({
				prompt: request.prompt,
				directory: requestDirectory,
				sessionID: sessionID,
				projectID: projectID,
				store: store,
				provider: live.provider,
				model: live.model,
				language: live.language,
				agent: live.agent,
				system: live.system,
			});
			final info = store.getSession(SessionID.make(result.request.sessionID));
			final updated = ServerProtocol.withCreateRequest(info, request, requestDirectory, 1002 + createdCount);
			store.updateSession(updated);
			final encoded = ServerProtocol.encodeSession(updated);
			if (sessionOrder.indexOf(result.request.sessionID) == -1)
				sessionOrder.push(result.request.sessionID);
			eventBus.publish(ServerProtocol.sessionEvent(ServerEventTypes.known("session.created"), result.request.sessionID));
			sessionStatus.idle(result.request.sessionID);
			return json(c, encoded);
		} catch (error:haxe.Exception) {
			sessionStatus.idle(sessionID);
			return json(c, ServerProtocol.error(error.message), 500);
		}
	}

	function abortSession(c:HonoContext):Response {
		final sessionID = param(c, "sessionID");
		if (!hasSession(sessionID))
			return json(c, ServerProtocol.error("Session not found"), 404);
		sessionStatus.abort(sessionID);
		return json(c, true);
	}

	function sessionStatuses(c:HonoContext):Response {
		return jsonText(sessionStatus.activeJsonText());
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
			c.header("x-next-cursor", Std.string(tail.time.updated));
		}
		return json(c, page);
	}

	function currentProject(c:HonoContext):Response {
		final dir = routingDirectory(c);
		final project = ProjectRuntime.fromDirectory(dir, store).project;
		return json(c, projectResponse(project));
	}

	function initGitProject(c:HonoContext):Response {
		final dir = routingDirectory(c);
		final prev = ProjectRuntime.fromDirectory(dir, store).project;
		try {
			ProjectRuntime.initGit(dir, prev);
		} catch (error:Dynamic) {
			return json(c, ServerProtocol.error(Std.string(error)), 400);
		}
		final next = ProjectRuntime.fromDirectory(dir, store).project;
		if (projectChanged(prev, next)) {
			InstanceRuntime.reload({
				directory: dir,
				worktree: dir,
				project: next,
				services: InstanceBootstrapRuntime.upstreamOrder(),
			});
		}
		return json(c, projectResponse(next));
	}

	function sessionMessages(c:HonoContext):Response {
		final sessionID = param(c, "sessionID");
		if (!hasSession(sessionID))
			return json(c, ServerProtocol.error("Session not found"), 404);
		final rawLimit = query(c, "limit");
		final before = query(c, "before");
		if (rawLimit == null && before != null && before != "")
			return json(c, ServerProtocol.error("before requires limit"), 400);
		final limit = ServerProtocol.decodeSessionListQuery(name -> name == "limit" ? rawLimit : null).limit;
		try {
			final page = before == null
				|| before == "" ? store.pageMessages(SessionID.make(sessionID), limit) : store.pageMessages(SessionID.make(sessionID), limit, before);
			if (page.more) {
				final cursorValue = page.cursor;
				if (cursorValue != null) {
					final path = "/session/" + sessionID + "/message";
					c.header("x-next-cursor", cursorValue);
					c.header("link", '<${path}?before=${StringTools.urlEncode(cursorValue)}>; rel="next"');
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
	function updateSession(c:HonoContext):Promise<Response> {
		final sessionID = param(c, "sessionID");
		final decoded = ServerProtocol.decodeUpdateSession(await(readJson(c)));
		final request = switch decoded {
			case Rejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case Decoded(value):
				value;
		};
		try {
			var info = store.getSession(SessionID.make(sessionID));
			if (request.title != null)
				info = ServerProtocol.withTitle(info, request.title, info.time.updated + 1);
			if (request.archived != null)
				info = ServerProtocol.withArchived(info, request.archived, info.time.updated + 1);
			store.updateSession(info);
			return json(c, ServerProtocol.encodeSession(info));
		} catch (_:StorageException) {
			return json(c, ServerProtocol.error("Session not found"), 404);
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
		eventBus.publish(ServerProtocol.sessionEvent(ServerEventTypes.known("session.selected"), request.sessionID));
		return json(c, true);
	}

	@:async
	function syncReplay(c:HonoContext):Promise<Response> {
		final decoded = SyncRouteRuntime.decodeReplay(await(readJson(c)));
		final request = switch decoded {
			case SyncRejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case SyncDecoded(value):
				value;
		};
		try {
			final source = syncRuntime.replayAll(request.events);
			return json(c, {sessionID: source});
		} catch (error:haxe.Exception) {
			return json(c, ServerProtocol.error(error.message), 400);
		}
	}

	@:async
	function syncHistory(c:HonoContext):Promise<Response> {
		final decoded = SyncRouteRuntime.decodeHistory(await(readJson(c)));
		final known = switch decoded {
			case SyncRejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case SyncDecoded(value):
				value;
		};
		return json(c, syncRuntime.history(known));
	}

	@:async
	function createPty(c:HonoContext):Promise<Response> {
		final decoded = PtyRouteProtocol.decodeCreate(await(readJson(c)));
		final request = switch decoded {
			case Rejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case Decoded(value):
				value;
		};
		return json(c, ptyService.create(request));
	}

	function getPty(c:HonoContext):Response {
		final info = ptyService.get(ptyID(c));
		if (info == null)
			return json(c, ServerProtocol.error("Session not found"), 404);
		return json(c, info);
	}

	@:async
	function updatePty(c:HonoContext):Promise<Response> {
		final decoded = PtyRouteProtocol.decodeUpdate(await(readJson(c)));
		final request = switch decoded {
			case Rejected(message):
				return json(c, ServerProtocol.error(message), 400);
			case Decoded(value):
				value;
		};
		final info = ptyService.update(ptyID(c), request);
		if (info == null)
			return json(c, ServerProtocol.error("Session not found"), 404);
		return json(c, info);
	}

	function removePty(c:HonoContext):Response {
		final id = ptyID(c);
		if (ptyService.get(id) == null)
			return json(c, ServerProtocol.error("Session not found"), 404);
		ptyService.remove(id);
		return json(c, true);
	}

	function ptyConnect(c:HonoContext):NodeWebSocketHandlerCallbacks {
		final id = ptyID(c);
		final cursor = parsePtyCursor(query(c, "cursor"));
		var handler:Null<PtyConnectHandler> = null;
		final pending:Array<PtySocketMessage> = [];
		var ready = false;
		return {
			onOpen: (_event, socket) -> {
				final raw = socket.raw;
				if (raw == null) {
					socket.close();
					return;
				}
				final rawSocket:PtySocket = raw;
				handler = ptyService.connect(id, rawSocket, cursor);
				ready = true;
				if (handler == null) {
					socket.close();
					return;
				}
				for (message in pending)
					handler.onMessage(message);
				pending.resize(0);
			},
			onMessage: event -> {
				final message = ptyMessage(event.data);
				if (message == null)
					return;
				final decoded:PtySocketMessage = message;
				if (!ready) {
					pending.push(decoded);
					return;
				}
				final active = handler;
				if (active != null)
					active.onMessage(decoded);
			},
			onClose: () -> {
				if (handler != null)
					handler.onClose();
			},
			onError: () -> {
				if (handler != null)
					handler.onClose();
			},
		};
	}

	function eventStream(c:HonoContext):Response {
		c.header("Cache-Control", "no-cache, no-transform");
		c.header("X-Accel-Buffering", "no");
		c.header("X-Content-Type-Options", "nosniff");
		return ServerEventStream.response(eventBus.snapshot(), eventBus.subscribe);
	}

	function hasSession(sessionID:String):Bool {
		try {
			store.getSession(SessionID.make(sessionID));
			return true;
		} catch (_:StorageException) {
			return false;
		}
	}

	static function projectChanged(prev:ProjectInfo, next:ProjectInfo):Bool {
		return prev.id.toString() != next.id.toString() || prev.vcs != next.vcs || prev.worktree != next.worktree;
	}

	static function projectResponse(project:ProjectInfo):ProjectRouteResponse {
		return {
			id: project.id.toString(),
			worktree: project.worktree,
			vcs: project.vcs == null ? null : Std.string(project.vcs),
			name: project.name,
			time: {
				created: project.time.created,
				updated: project.time.updated,
				initialized: project.time.initialized,
			},
			sandboxes: project.sandboxes.copy(),
		};
	}

	static function ptyID(c:HonoContext):PtyID {
		return PtyID.make(param(c, "ptyID"));
	}

	static function parsePtyCursor(value:Null<String>):Null<Int> {
		if (value == null || value == "")
			return null;
		if (!INTEGER_PATTERN.match(value))
			return null;
		final parsed = Std.parseFloat(value);
		if (Math.isNaN(parsed) || parsed < -1 || parsed > MAX_SAFE_INTEGER)
			return null;
		return Std.int(parsed);
	}

	static function ptyMessage(value:Unknown):Null<PtySocketMessage> {
		// PTY websocket messages can arrive as text, ArrayBuffer, or typed-array
		// views depending on the host websocket implementation. This is a runtime
		// boundary from Unknown; each conversion is guarded before use.
		if (WebBinary.isString(value))
			return WebBinary.string(value);
		if (WebBinary.isArrayBuffer(value))
			return WebBinary.arrayBuffer(value);
		if (WebArrayBuffer.isView(value)) {
			final view = WebBinary.arrayBufferView(value);
			return view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
		}
		return null;
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

	static function json<T>(c:HonoContext, payload:T, ?status:Int):Response {
		if (status == null)
			return c.json(payload);
		return c.json(payload, status);
	}

	static function jsonText(text:String):Response {
		return new Response(text, {headers: {"content-type": "application/json"}});
	}

	static function param(c:HonoContext, name:String):String {
		final value = c.req.param(name).orNull();
		return value == null ? "" : value;
	}

	static function query(c:HonoContext, name:String):Null<String> {
		return c.req.query(name).orNull();
	}

	function routingDirectory(c:HonoContext):String {
		final value = c.req.header("x-opencode-directory").orNull();
		if (value == null || value == "")
			return directory;
		return StringTools.urlDecode(value);
	}
}
