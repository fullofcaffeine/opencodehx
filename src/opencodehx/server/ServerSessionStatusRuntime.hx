package opencodehx.server;

import opencodehx.server.ServerProtocol.ServerEvent;
import opencodehx.server.ServerProtocol.ServerEventTypes;
import opencodehx.server.ServerProtocol.SessionStatusInfo;
import opencodehx.server.ServerProtocol.SessionStatusType;

/**
	Server-owned session status registry for the first Hono route surface.

	The current server route runs the local session processor synchronously, so
	public reads only observe the upstream-shaped empty active-status record.
	The typed registry still publishes busy/retry/idle status events and keeps
	the active state ready for the later async live-session loop.
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
