package opencodehx.smoke;

import haxe.DynamicAccess;
import opencodehx.effect.ObservabilityResource;
import opencodehx.effect.RunServiceRuntime;
import opencodehx.effect.RuntimeMemo;

typedef SmokeSharedService = {
	final id:Int;
}

typedef SmokeRuntimeService = {
	final get:Void->Int;
}

class EffectSmoke {
	public static function run():Void {
		observabilityResource();
		runServiceMemoMap();
	}

	static function observabilityResource():Void {
		final decoded = ObservabilityResource.resource({
			env: env({
				OTEL_RESOURCE_ATTRIBUTES: "service.namespace=anomalyco,team=platform%2Cobservability,label=hello%3Dworld,key%2Fname=value%20here",
				OPENCODE_CLIENT: "cli",
			}),
			processRole: "main",
			runID: "run-test",
			instanceID: "instance-test",
			installationChannel: "dev",
		});
		eq(decoded.serviceName, "opencode", "observability service name");
		eq(decoded.attributes.get("service.namespace"), "anomalyco", "observability namespace");
		eq(decoded.attributes.get("team"), "platform,observability", "observability comma decode");
		eq(decoded.attributes.get("label"), "hello=world", "observability equals decode");
		eq(decoded.attributes.get("key/name"), "value here", "observability slash and space decode");

		final invalid = ObservabilityResource.resource({
			env: env({OTEL_RESOURCE_ATTRIBUTES: "service.namespace=anomalyco,broken", OPENCODE_CLIENT: "desktop"}),
			processRole: "main",
			runID: "run-invalid",
			instanceID: "instance-invalid",
		});
		eq(invalid.attributes.exists("service.namespace"), false, "observability invalid entry drops env attributes");
		eq(invalid.attributes.exists("opencode.client"), true, "observability invalid keeps builtin attributes");

		final collision = ObservabilityResource.resource({
			env: env({
				OTEL_RESOURCE_ATTRIBUTES: "opencode.client=web,service.instance.id=override,service.namespace=anomalyco",
				OPENCODE_CLIENT: "cli",
			}),
			processRole: "main",
			runID: "run-collision",
			instanceID: "instance-collision",
		});
		eq(collision.attributes.get("opencode.client"), "cli", "observability builtin client wins");
		eq(collision.attributes.get("service.namespace"), "anomalyco", "observability env namespace kept");
		eq(collision.attributes.get("service.instance.id"), "instance-collision", "observability builtin instance wins");
	}

	static function runServiceMemoMap():Void {
		var initialized = 0;
		final shared = new RuntimeMemo<SmokeSharedService>();
		final sharedLayer = () -> shared.get(() -> {
			initialized += 1;
			return {id: initialized};
		});

		final one:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			final svc = sharedLayer();
			final get = () -> svc.id;
			return {get: get};
		});
		final two:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			final svc = sharedLayer();
			final get = () -> svc.id;
			return {get: get};
		});

		eq(one.run(svc -> svc.get()), 1, "run-service first runtime shared id");
		eq(two.run(svc -> svc.get()), 1, "run-service second runtime shared id");
		eq(initialized, 1, "run-service dependent layer initialized once");
	}

	static function env(values:Dynamic<String>):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		for (field in Reflect.fields(values)) {
			out.set(field, Std.string(Reflect.field(values, field)));
		}
		return out;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
