package opencodehx.server;

import opencodehx.server.ServerProtocol.ServerEvent;

typedef ServerEventListener = ServerEvent->Void;
typedef ServerEventUnsubscribe = Void->Void;
typedef ServerEventSubscribe = ServerEventListener->ServerEventUnsubscribe;

class ServerEventBus {
	final history:Array<ServerEvent> = [];
	final listeners:Array<ServerEventListener> = [];

	public function new() {}

	public function publish(event:ServerEvent):Void {
		history.push(event);
		for (listener in listeners.copy()) {
			listener(event);
		}
	}

	public function snapshot():Array<ServerEvent> {
		return history.copy();
	}

	public function subscribe(listener:ServerEventListener):ServerEventUnsubscribe {
		listeners.push(listener);
		var active = true;
		return () -> {
			if (!active)
				return;
			active = false;
			listeners.remove(listener);
		};
	}
}
