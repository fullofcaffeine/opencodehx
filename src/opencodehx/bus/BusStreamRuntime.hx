package opencodehx.bus;

import opencodehx.bus.BusRuntime;
import opencodehx.bus.BusRuntime.BusAnyEvent;
import opencodehx.bus.BusRuntime.BusEvent;
import opencodehx.bus.BusRuntime.BusEventDefinition;
import opencodehx.bus.BusRuntime.BusUnsubscribe;

class BusStream<TEvent> {
	final attach:(TEvent->Void)->BusUnsubscribe;

	public function new(attach:(TEvent->Void)->BusUnsubscribe) {
		this.attach = attach;
	}

	public function runForEach(listener:TEvent->Void):BusUnsubscribe {
		return attach(listener);
	}
}

class BusStreamRuntime {
	public static function subscribe<TProperties>(bus:BusRuntime, definition:BusEventDefinition<TProperties>):BusStream<BusEvent<TProperties>> {
		return new BusStream(listener -> bus.subscribe(definition, listener));
	}

	public static function subscribeAll(bus:BusRuntime):BusStream<BusAnyEvent> {
		return new BusStream(listener -> bus.subscribeAll(listener));
	}
}
