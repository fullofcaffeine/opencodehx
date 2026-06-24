package opencodehx.effect;

import haxe.DynamicAccess;
import opencodehx.BuildInfo;
import opencodehx.externs.web.UriCodec;
import opencodehx.host.node.NodeProcess;

typedef ObservabilityResourceInfo = {
	final serviceName:String;
	final serviceVersion:String;
	final attributes:DynamicAccess<String>;
}

typedef ObservabilityResourceOptions = {
	@:optional final env:DynamicAccess<String>;
	@:optional final processRole:String;
	@:optional final runID:String;
	@:optional final instanceID:String;
	@:optional final installationChannel:String;
}

class ObservabilityResource {
	static inline final SERVICE_NAME = "opencode";

	public static function resource(?options:ObservabilityResourceOptions):ObservabilityResourceInfo {
		final opts:ObservabilityResourceOptions = options == null ? {} : options;
		final env = opts.env == null ? NodeProcess.env() : opts.env;
		final attributes = parseAttributes(env.get("OTEL_RESOURCE_ATTRIBUTES"));
		attributes.set("deployment.environment.name", opts.installationChannel == null ? "latest" : opts.installationChannel);
		attributes.set("opencode.client", env.get("OPENCODE_CLIENT") == null ? "" : env.get("OPENCODE_CLIENT"));
		attributes.set("opencode.process_role", opts.processRole == null ? "main" : opts.processRole);
		attributes.set("opencode.run_id", opts.runID == null ? "" : opts.runID);
		attributes.set("service.instance.id", opts.instanceID == null ? "" : opts.instanceID);
		return {
			serviceName: SERVICE_NAME,
			serviceVersion: BuildInfo.version,
			attributes: attributes,
		};
	}

	static function parseAttributes(value:Null<String>):DynamicAccess<String> {
		final attributes = new DynamicAccess<String>();
		if (value == null || value == "")
			return attributes;
		try {
			for (entry in value.split(",")) {
				final index = entry.indexOf("=");
				if (index < 1)
					throw "Invalid OTEL_RESOURCE_ATTRIBUTES entry";
				attributes.set(UriCodec.decodeComponent(entry.substr(0, index)), UriCodec.decodeComponent(entry.substr(index + 1)));
			}
		} catch (_:Dynamic) {
			return new DynamicAccess<String>();
		}
		return attributes;
	}
}
