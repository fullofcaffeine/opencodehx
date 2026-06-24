package opencodehx.bus;

typedef BusEventDefinition<TProperties> = {
	final type:String;
}

typedef BusEvent<TProperties> = {
	final type:String;
	final properties:TProperties;
}

typedef BusUnsubscribe = Void->Void;

// subscribeAll observes every event type, so its payload shape is necessarily
// open. Typed subscribers should use BusRuntime.subscribe with a definition.
typedef BusAnyEvent = BusEvent<Dynamic>;

private typedef BusListenerEntry = {
	final type:Null<String>;
	final deliver:BusAnyEvent->Void;
}

class BusRuntime {
	public static final InstanceDisposed:BusEventDefinition<{}> = define("instance.disposed");
	static final scoped:Map<String, BusRuntime> = new Map();

	final history:Array<BusAnyEvent> = [];
	final listeners:Array<BusListenerEntry> = [];
	var disposed = false;

	public function new() {}

	public static function define<TProperties>(type:String):BusEventDefinition<TProperties> {
		return {type: type};
	}

	public static function scope(key:String):BusRuntime {
		final existing = scoped.get(key);
		if (existing != null)
			return existing;
		final bus = new BusRuntime();
		scoped.set(key, bus);
		return bus;
	}

	public static function disposeScope(key:String):Bool {
		final bus = scoped.get(key);
		if (bus == null)
			return false;
		scoped.remove(key);
		bus.dispose();
		return true;
	}

	public static function disposeAllScopes():Void {
		final keys:Array<String> = [];
		for (key in scoped.keys())
			keys.push(key);
		for (key in keys)
			disposeScope(key);
	}

	public function publish<TProperties>(definition:BusEventDefinition<TProperties>, properties:TProperties):Void {
		if (disposed)
			return;
		// The bus is intentionally heterogeneous at runtime. Keep the Dynamic
		// payload boxed inside BusAnyEvent, and restore typed properties only
		// for listeners registered with the matching event definition.
		final event:BusAnyEvent = {type: definition.type, properties: cast properties};
		history.push(event);
		for (entry in listeners.copy()) {
			if (entry.type == null || entry.type == event.type)
				entry.deliver(event);
		}
	}

	public function subscribe<TProperties>(definition:BusEventDefinition<TProperties>, listener:BusEvent<TProperties>->Void):BusUnsubscribe {
		final entry:BusListenerEntry = {
			type: definition.type,
			deliver: event -> {
				if (event.type == definition.type)
					listener({type: event.type, properties: cast event.properties});
			},
		};
		return add(entry);
	}

	public function subscribeAll(listener:BusAnyEvent->Void):BusUnsubscribe {
		return add({type: null, deliver: listener});
	}

	public function snapshot():Array<BusAnyEvent> {
		return history.copy();
	}

	public function dispose():Void {
		if (disposed)
			return;
		// Upstream wildcard subscribers observe InstanceDisposed before the
		// instance stream ends. Publish it while listeners are still active, then
		// clear subscriptions so later publishes cannot leak across lifecycles.
		publish(InstanceDisposed, {});
		disposed = true;
		listeners.resize(0);
	}

	function add(entry:BusListenerEntry):BusUnsubscribe {
		if (disposed)
			return () -> {};
		listeners.push(entry);
		var active = true;
		return () -> {
			if (!active)
				return;
			active = false;
			listeners.remove(entry);
		};
	}
}
