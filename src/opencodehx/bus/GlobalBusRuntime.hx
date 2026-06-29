package opencodehx.bus;

import opencodehx.bus.BusRuntime.BusAnyEvent;

typedef GlobalBusEvent = {
	final directory:Null<String>;
	final project:Null<String>;
	final workspace:Null<String>;
	final payload:BusAnyEvent;
}

typedef GlobalBusUnsubscribe = Void->Void;

/**
	Typed facade for upstream's process-wide `GlobalBus`.

	OpenCode uses a Node `EventEmitter` with one `"event"` channel whose payload
	wraps the instance bus event and optional directory/project/workspace context.
	This Haxe runtime keeps that public shape without exposing a raw JS emitter
	to product code.
**/
class GlobalBusRuntime {
	static final listeners:Array<GlobalBusEvent->Void> = [];
	static final history:Array<GlobalBusEvent> = [];

	public static function on(listener:GlobalBusEvent->Void):GlobalBusUnsubscribe {
		listeners.push(listener);
		var active = true;
		return () -> {
			if (!active)
				return;
			active = false;
			off(listener);
		};
	}

	public static function off(listener:GlobalBusEvent->Void):Void {
		listeners.remove(listener);
	}

	public static function emit(event:GlobalBusEvent):Void {
		history.push(event);
		for (listener in listeners.copy())
			listener(event);
	}

	public static function snapshot():Array<GlobalBusEvent> {
		return history.copy();
	}

	public static function clear():Void {
		listeners.resize(0);
		history.resize(0);
	}
}
