package opencodehx.acp;

import opencodehx.util.Compare.compareString;

enum abstract AcpEventType(String) from String to String {
	var MessagePartDelta = "message.part.delta";
	var MessagePartUpdated = "message.part.updated";
	var PermissionAsked = "permission.asked";
}

enum abstract AcpPermissionOutcome(String) from String to String {
	var Allow = "allow";
	var Deny = "deny";
}

enum AcpSessionUpdateKind {
	AgentMessageChunk(text:String);
	PermissionRequest(permissionID:String);
}

typedef AcpInitializeRequest = {
	@:optional final client:String;
}

typedef AcpInitializeResponse = {
	final protocolVersion:Int;
	final agent:String;
}

typedef AcpNewSessionRequest = {
	final cwd:String;
	@:optional final mcpServers:Array<String>;
}

typedef AcpLoadSessionRequest = {
	final sessionID:String;
	final cwd:String;
}

typedef AcpSessionResponse = {
	final sessionID:String;
}

typedef AcpPromptRequest = {
	final sessionID:String;
	final prompt:String;
}

typedef AcpPromptResponse = {
	final queued:Bool;
}

typedef AcpCancelRequest = {
	final sessionID:String;
}

typedef AcpCancelResponse = {
	final cancelled:Bool;
}

typedef AcpModeRequest = {
	final sessionID:String;
	final mode:String;
}

typedef AcpAuthRequest = {
	final provider:String;
}

typedef AcpAuthResponse = {
	final authenticated:Bool;
}

typedef AcpModelRequest = {
	final sessionID:String;
	final providerID:String;
	final modelID:String;
}

typedef AcpSessionInfo = {
	final sessionID:String;
	final cwd:String;
	@:optional final mode:String;
	@:optional final providerID:String;
	@:optional final modelID:String;
}

typedef AcpListSessionsResponse = {
	final sessions:Array<AcpSessionInfo>;
}

typedef AcpPermissionRequest = {
	final sessionID:String;
	final permissionID:String;
}

typedef AcpPermissionDecision = {
	final outcome:AcpPermissionOutcome;
}

typedef AcpPermissionReply = {
	final sessionID:String;
	final permissionID:String;
	final outcome:AcpPermissionOutcome;
}

typedef AcpSessionUpdate = {
	final sessionID:String;
	final update:AcpSessionUpdateKind;
}

typedef AcpEvent = {
	final type:AcpEventType;
	final sessionID:String;
	@:optional final delta:String;
	@:optional final messageRole:String;
	@:optional final partType:String;
	@:optional final permissionID:String;
}

typedef AcpConnection = {
	function sessionUpdate(update:AcpSessionUpdate):Void;
	function requestPermission(request:AcpPermissionRequest):AcpPermissionDecision;
	function permissionReply(reply:AcpPermissionReply):Void;
}

typedef AcpSessionState = {
	final sessionID:String;
	final cwd:String;
	@:optional var mode:String;
	@:optional var providerID:String;
	@:optional var modelID:String;
}

class AcpAgent {
	final connection:AcpConnection;
	final sessions = new Map<String, AcpSessionState>();
	final subscribed = new Map<String, Bool>();
	var nextSession = 1;

	public var eventSubscribeCount(default, null):Int = 0;

	public function new(connection:AcpConnection) {
		this.connection = connection;
	}

	public function initialize(_request:AcpInitializeRequest):AcpInitializeResponse {
		return {protocolVersion: 1, agent: "opencodehx"};
	}

	public function newSession(request:AcpNewSessionRequest):AcpSessionResponse {
		final sessionID = 'ses_acp_${nextSession++}';
		sessions.set(sessionID, {sessionID: sessionID, cwd: request.cwd});
		subscribe(sessionID);
		return {sessionID: sessionID};
	}

	public function prompt(request:AcpPromptRequest):AcpPromptResponse {
		ensureKnown(request.sessionID, "prompt");
		return {queued: true};
	}

	public function cancel(request:AcpCancelRequest):AcpCancelResponse {
		ensureKnown(request.sessionID, "cancel");
		return {cancelled: true};
	}

	public function loadSession(request:AcpLoadSessionRequest):AcpSessionResponse {
		if (!sessions.exists(request.sessionID))
			sessions.set(request.sessionID, {sessionID: request.sessionID, cwd: request.cwd});
		subscribe(request.sessionID);
		return {sessionID: request.sessionID};
	}

	public function setSessionMode(request:AcpModeRequest):AcpSessionResponse {
		final session = ensureKnown(request.sessionID, "setSessionMode");
		session.mode = request.mode;
		return {sessionID: request.sessionID};
	}

	public function authenticate(_request:AcpAuthRequest):AcpAuthResponse {
		return {authenticated: true};
	}

	public function listSessions():AcpListSessionsResponse {
		final out:Array<AcpSessionInfo> = [];
		for (sessionID in sortedSessionIDs()) {
			final session = sessions.get(sessionID);
			out.push({
				sessionID: session.sessionID,
				cwd: session.cwd,
				mode: session.mode,
				providerID: session.providerID,
				modelID: session.modelID,
			});
		}
		return {sessions: out};
	}

	public function unstable_forkSession(request:AcpLoadSessionRequest):AcpSessionResponse {
		final source = ensureKnown(request.sessionID, "unstable_forkSession");
		final sessionID = 'ses_acp_${nextSession++}';
		sessions.set(sessionID, {
			sessionID: sessionID,
			cwd: request.cwd,
			mode: source.mode,
			providerID: source.providerID,
			modelID: source.modelID,
		});
		subscribe(sessionID);
		return {sessionID: sessionID};
	}

	public function unstable_resumeSession(request:AcpLoadSessionRequest):AcpSessionResponse {
		return loadSession(request);
	}

	public function unstable_setSessionModel(request:AcpModelRequest):AcpSessionResponse {
		final session = ensureKnown(request.sessionID, "unstable_setSessionModel");
		session.providerID = request.providerID;
		session.modelID = request.modelID;
		return {sessionID: request.sessionID};
	}

	public function handleEvent(event:AcpEvent):Void {
		if (!sessions.exists(event.sessionID))
			return;
		switch event.type {
			case MessagePartDelta:
				if (event.delta != null && event.delta != "") {
					connection.sessionUpdate({
						sessionID: event.sessionID,
						update: AgentMessageChunk(event.delta),
					});
				}
			case MessagePartUpdated:
				if (event.messageRole == "user" && event.partType == "text")
					return;
			case PermissionAsked:
				final permissionID = event.permissionID != null ? event.permissionID : "permission";
				connection.sessionUpdate({
					sessionID: event.sessionID,
					update: PermissionRequest(permissionID),
				});
				final decision = connection.requestPermission({
					sessionID: event.sessionID,
					permissionID: permissionID,
				});
				connection.permissionReply({
					sessionID: event.sessionID,
					permissionID: permissionID,
					outcome: decision.outcome,
				});
		}
	}

	function subscribe(sessionID:String):Void {
		if (subscribed.exists(sessionID))
			return;
		subscribed.set(sessionID, true);
		eventSubscribeCount++;
	}

	function ensureKnown(sessionID:String, owner:String):AcpSessionState {
		final session = sessions.get(sessionID);
		if (session == null)
			throw '${owner}: unknown ACP session ${sessionID}';
		return session;
	}

	function sortedSessionIDs():Array<String> {
		final out:Array<String> = [];
		for (sessionID in sessions.keys())
			out.push(sessionID);
		out.sort(compareString);
		return out;
	}
}
