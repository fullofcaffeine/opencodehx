package opencodehx.bus;

typedef EventListener<TEvent> = TEvent->Void;
typedef EventUnsubscribe = Void->Void;

class EventBus<TEvent> {
	final history:Array<TEvent> = [];
	final listeners:Array<EventListener<TEvent>> = [];

	public function new() {}

	public function publish(event:TEvent):Void {
		history.push(event);
		for (listener in listeners.copy()) {
			listener(event);
		}
	}

	public function snapshot():Array<TEvent> {
		return history.copy();
	}

	public function subscribe(listener:EventListener<TEvent>):EventUnsubscribe {
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
