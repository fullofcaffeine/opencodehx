package opencodehx.server;

import haxe.Json;
import opencodehx.server.ServerProtocol.ServerEvent;
import opencodehx.server.ServerProtocol.ServerEventTypes;
import opencodehx.server.ServerProtocol.SessionStatusInfo;
import opencodehx.server.ServerProtocol.SessionStatusType;

/**
	Server-owned session status registry for the first Hono route surface.

	Default deterministic session creation completes synchronously, so public
	reads observe the upstream-shaped empty active-status record there. Injected
	live AI SDK routes keep `busy` visible while the stream is active, and later
	config-backed server execution can reuse the same typed status state.
**/
class ServerSessionStatusRuntime {
	final statuses = new Map<String, SessionStatusInfo>();
	final publish:ServerEvent->Void;

	public function new(publish:ServerEvent->Void) {
		this.publish = publish;
	}

	public function busy(sessionID:String):Void {
		set(sessionID, {type: SessionStatusType.Busy});
	}

	public function retry(sessionID:String, attempt:Int, message:String, next:Float):Void {
		set(sessionID, {
			type: SessionStatusType.Retry,
			attempt: attempt,
			message: message,
			next: next,
		});
	}

	public function idle(sessionID:String):Void {
		set(sessionID, {type: SessionStatusType.Idle});
	}

	public function abort(sessionID:String):Void {
		idle(sessionID);
	}

	public function isActive(sessionID:String):Bool {
		return statuses.exists(sessionID);
	}

	public function activeJsonText():String {
		final fields:Array<String> = [];
		for (sessionID => status in statuses)
			fields.push(Json.stringify(sessionID) + ":" + Json.stringify(status));
		return "{" + fields.join(",") + "}";
	}

	function set(sessionID:String, status:SessionStatusInfo):Void {
		publish(ServerProtocol.sessionStatusEvent(sessionID, status));
		if (status.type == SessionStatusType.Idle) {
			statuses.remove(sessionID);
			publish(ServerProtocol.sessionEvent(ServerEventTypes.known("session.idle"), sessionID));
			return;
		}
		statuses.set(sessionID, status);
	}
}
