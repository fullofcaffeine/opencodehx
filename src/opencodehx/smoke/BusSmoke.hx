package opencodehx.smoke;

import opencodehx.bus.BusRuntime;
import opencodehx.bus.BusRuntime.BusEventDefinition;
import opencodehx.bus.BusStreamRuntime;

typedef PingPayload = {
	final value:Int;
}

typedef PongPayload = {
	final message:String;
}

class BusSmoke {
	public static function run():Void {
		publishSubscribe();
		typeFilter();
		noSubscribers();
		unsubscribeStopsDelivery();
		subscribeAllReceivesEveryType();
		multipleSubscribers();
		streamDelivery();
		instanceIsolation();
		instanceDisposal();
		snapshotCopiesHistory();
	}

	static function publishSubscribe():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.ping");
		final received:Array<Int> = [];
		bus.subscribe(ping, event -> received.push(event.properties.value));
		bus.publish(ping, {value: 42});
		bus.publish(ping, {value: 99});
		eq(received.join(","), "42,99", "bus subscribe matching events");
	}

	static function typeFilter():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.ping");
		final pong:BusEventDefinition<PongPayload> = BusRuntime.define("test.pong");
		final received:Array<Int> = [];
		bus.subscribe(ping, event -> received.push(event.properties.value));
		bus.publish(pong, {message: "ignored"});
		bus.publish(ping, {value: 1});
		eq(received.join(","), "1", "bus subscribe filters type");
	}

	static function noSubscribers():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.no-subscribers");
		bus.publish(ping, {value: 1});
		eq(bus.snapshot().length, 1, "bus publish without subscribers");
	}

	static function unsubscribeStopsDelivery():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.unsubscribe");
		final received:Array<Int> = [];
		final unsubscribe = bus.subscribe(ping, event -> received.push(event.properties.value));
		bus.publish(ping, {value: 1});
		unsubscribe();
		unsubscribe();
		bus.publish(ping, {value: 2});
		eq(received.join(","), "1", "bus unsubscribe stops delivery");
	}

	static function subscribeAllReceivesEveryType():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.all.ping");
		final pong:BusEventDefinition<PongPayload> = BusRuntime.define("test.all.pong");
		final received:Array<String> = [];
		bus.subscribeAll(event -> received.push(event.type));
		bus.publish(ping, {value: 1});
		bus.publish(pong, {message: "hi"});
		eq(received.join(","), "test.all.ping,test.all.pong", "bus subscribeAll types");
	}

	static function multipleSubscribers():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.multiple");
		final a:Array<Int> = [];
		final b:Array<Int> = [];
		bus.subscribe(ping, event -> a.push(event.properties.value));
		bus.subscribe(ping, event -> b.push(event.properties.value));
		bus.publish(ping, {value: 7});
		eq(a.join(","), "7", "bus first subscriber");
		eq(b.join(","), "7", "bus second subscriber");
	}

	static function streamDelivery():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.stream.ping");
		final pong:BusEventDefinition<PongPayload> = BusRuntime.define("test.stream.pong");
		final pings:Array<Int> = [];
		final all:Array<String> = [];
		final a:Array<Int> = [];
		final b:Array<Int> = [];

		BusStreamRuntime.subscribe(bus, ping).runForEach(event -> pings.push(event.properties.value));
		BusStreamRuntime.subscribeAll(bus).runForEach(event -> all.push(event.type));
		BusStreamRuntime.subscribe(bus, ping).runForEach(event -> a.push(event.properties.value));
		BusStreamRuntime.subscribe(bus, ping).runForEach(event -> b.push(event.properties.value));

		bus.publish(pong, {message: "ignored"});
		bus.publish(ping, {value: 1});
		bus.publish(ping, {value: 2});

		eq(pings.join(","), "1,2", "bus stream receives matching events");
		eq(all.join(","), "test.stream.pong,test.stream.ping,test.stream.ping", "bus stream subscribeAll receives all types");
		eq(a.join(","), "1,2", "bus stream first subscriber");
		eq(b.join(","), "1,2", "bus stream second subscriber");
	}

	static function instanceIsolation():Void {
		BusRuntime.disposeAllScopes();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.scoped.ping");
		final busA = BusRuntime.scope("dir-a");
		final busB = BusRuntime.scope("dir-b");
		final receivedA:Array<Int> = [];
		final receivedB:Array<Int> = [];
		busA.subscribe(ping, event -> receivedA.push(event.properties.value));
		busB.subscribe(ping, event -> receivedB.push(event.properties.value));
		BusRuntime.scope("dir-a").publish(ping, {value: 1});
		BusRuntime.scope("dir-b").publish(ping, {value: 2});
		eq(receivedA.join(","), "1", "bus scoped instance a");
		eq(receivedB.join(","), "2", "bus scoped instance b");
		BusRuntime.disposeAllScopes();
	}

	static function instanceDisposal():Void {
		BusRuntime.disposeAllScopes();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.dispose.ping");
		final bus = BusRuntime.scope("disposable");
		final received:Array<Int> = [];
		final types:Array<String> = [];
		var disposed = false;
		var disposedDirectory = "";
		bus.subscribeAll(event -> {
			types.push(event.type);
			if (event.type == BusRuntime.InstanceDisposed.type) {
				disposed = true;
				disposedDirectory = event.properties.directory;
				return;
			}
			received.push(event.properties.value);
		});
		bus.publish(ping, {value: 1});
		eq(BusRuntime.disposeScope("disposable"), true, "bus scoped dispose result");
		bus.publish(ping, {value: 2});
		eq(received.join(","), "1", "bus scoped disposal stops delivery");
		eq(disposed, true, "bus scoped disposal event");
		eq(types.indexOf(BusRuntime.InstanceDisposed.type) != -1, true, "bus scoped disposal type");
		eq(BusRuntime.InstanceDisposed.type, "server.instance.disposed", "bus scoped disposal upstream type");
		eq(disposedDirectory, "disposable", "bus scoped disposal directory payload");
		eq(BusRuntime.disposeScope("disposable"), false, "bus scoped dispose missing");
	}

	static function snapshotCopiesHistory():Void {
		final bus = new BusRuntime();
		final ping:BusEventDefinition<PingPayload> = BusRuntime.define("test.snapshot");
		bus.publish(ping, {value: 3});
		final first = bus.snapshot();
		first.resize(0);
		eq(bus.snapshot().length, 1, "bus snapshot is copy");
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
