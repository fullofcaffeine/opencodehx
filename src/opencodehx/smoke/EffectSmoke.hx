package opencodehx.smoke;

import haxe.DynamicAccess;
import opencodehx.effect.ObservabilityResource;

class EffectSmoke {
	public static function run():Void {
		observabilityResource();
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
