package opencodehx.smoke;

import haxe.Json;
import opencodehx.config.ConfigInfo;
import opencodehx.harness.TranscriptHarness;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.session.MessageCodec;

class ProviderSmoke {
	public static function run():Void {
		registryEnvAndConfig();
		registryFilters();
		registryModels();
		registryAuthAndBedrock();
		final transcript = TranscriptHarness.oneTurn();
		eq(transcript.provider.id, "openai", "provider id");
		eq(transcript.provider.modelID, "gpt-5.2", "model id");
		eq(transcript.events.length, 3, "event count");
		eq(Reflect.field(transcript.events[1], "text"), "Hello from the fake provider.", "delta text");
		eq(transcript.messages.length, 2, "message count");

		final encoded = TranscriptHarness.oneTurnJson();
		final parsed:Dynamic = Json.parse(encoded);
		final first = Reflect.field(cast parsed.messages[0], "info");
		eq(Reflect.field(first, "role"), "user", "encoded user role");
		MessageCodec.decodeWithParts(parsed.messages[1], "provider-smoke-assistant");
	}

	static function registryEnvAndConfig():Void {
		final envRegistry = registry(config({}), {ANTHROPIC_API_KEY: "test-api-key"});
		final anthropic = envRegistry.getProvider(ProviderID.make("anthropic"));
		eq(anthropic.source, "env", "anthropic env source");
		eq(Reflect.hasField(Reflect.field(anthropic.options, "headers"), "anthropic-beta"), true, "anthropic custom headers");

		final configured = registry(config({
			provider: {
				anthropic: {
					options: {
						apiKey: "config-api-key",
						timeout: 60000,
						chunkTimeout: 15000,
					},
				},
			},
		}));
		final provider = configured.getProvider(ProviderID.make("anthropic"));
		eq(provider.source, "config", "anthropic config source");
		eq(Reflect.field(provider.options, "apiKey"), "config-api-key", "config api key");
		eq(Reflect.field(provider.options, "timeout"), 60000, "config timeout");
	}

	static function registryFilters():Void {
		final disabled = registry(config({disabled_providers: ["anthropic"]}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(disabled.getProvider(ProviderID.make("anthropic")) == null, true, "disabled provider");

		final enabled = registry(config({enabled_providers: ["anthropic"]}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		eq(enabled.getProvider(ProviderID.make("anthropic")) != null, true, "enabled provider present");
		eq(enabled.getProvider(ProviderID.make("openai")) == null, true, "enabled provider excludes openai");

		final whitelist = registry(config({
			provider: {
				anthropic: {
					whitelist: ["claude-sonnet-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(whitelist.getProvider(ProviderID.make("anthropic")).models.exists("claude-sonnet-4-20250514"), true, "whitelist keeps model");
		eq(modelCount(whitelist, "anthropic"), 1, "whitelist count");

		final blacklist = registry(config({
			provider: {
				anthropic: {
					blacklist: ["claude-sonnet-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(blacklist.getProvider(ProviderID.make("anthropic")).models.exists("claude-sonnet-4-20250514"), false, "blacklist removes model");
	}

	static function registryModels():Void {
		final custom = registry(config({
			provider: {
				"custom-provider": {
					name: "Custom Provider",
					npm: "@ai-sdk/openai-compatible",
					api: "https://api.custom.com/v1",
					env: ["CUSTOM_API_KEY"],
					models: {
						"custom-model": {
							name: "Custom Model",
							tool_call: true,
							limit: {context: 128000, output: 4096},
						},
					},
					options: {apiKey: "custom-key"},
				},
				anthropic: {
					models: {
						"my-alias": {
							id: "claude-sonnet-4-20250514",
							name: "My Custom Alias",
						},
						"claude-sonnet-4-20250514": {
							options: {customOption: "custom-value"},
						},
					},
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(custom.getProvider(ProviderID.make("custom-provider")).name, "Custom Provider", "custom provider name");
		eq(custom.getModel(ProviderID.make("custom-provider"), ModelID.make("custom-model")).name, "Custom Model", "custom model name");
		eq(custom.getModel(ProviderID.make("anthropic"), ModelID.make("my-alias")).name, "My Custom Alias", "alias model name");
		eq(Reflect.field(custom.getModel(ProviderID.make("anthropic"), ModelID.make("claude-sonnet-4-20250514")).options, "customOption"), "custom-value",
			"model option merge");

		final parsed = ProviderRegistry.parseModel("openrouter/anthropic/claude-3-opus");
		eq(parsed.providerID.toString(), "openrouter", "parse provider");
		eq(parsed.modelID.toString(), "anthropic/claude-3-opus", "parse slash model");

		final configuredDefault = registry(config({model: "anthropic/claude-sonnet-4-20250514"}), {ANTHROPIC_API_KEY: "test-api-key"}).defaultModel();
		eq(configuredDefault.providerID.toString(), "anthropic", "default model provider");
		eq(configuredDefault.modelID.toString(), "claude-sonnet-4-20250514", "default model id");

		final small = custom.smallModel(ProviderID.make("anthropic"));
		if (small == null)
			throw "small model: expected model";
		eq(small.id.toString(), "claude-haiku-4-5", "small model priority");

		expectProviderFailure(() -> custom.getModel(ProviderID.make("anthropic"), ModelID.make("missing-model")), "missing model", function(failure) {
			return switch failure {
				case ModelNotFound(providerID, modelID, _): providerID.toString() == "anthropic" && modelID.toString() == "missing-model";
				case _: false;
			}
		});
	}

	static function registryAuthAndBedrock():Void {
		final authRegistry = registry(config({}), {}, {"openai": {type: "api", key: "auth-key"}});
		final openai = authRegistry.getProvider(ProviderID.make("openai"));
		eq(openai.source, "api", "api auth source");
		eq(openai.key, "auth-key", "api auth key");

		final bedrockConfig = registry(config({
			provider: {
				"amazon-bedrock": {
					options: {
						region: "eu-west-1",
						profile: "config-profile",
						endpoint: "https://bedrock-runtime.example.com",
					},
				},
			},
		}), {AWS_REGION: "us-east-1", AWS_PROFILE: "default"});
		final bedrock = bedrockConfig.getProvider(ProviderID.make("amazon-bedrock"));
		eq(Reflect.field(bedrock.options, "region"), "eu-west-1", "bedrock config region");
		eq(Reflect.field(bedrock.options, "profile"), "config-profile", "bedrock config profile");
		eq(Reflect.field(bedrock.options, "baseURL"), "https://bedrock-runtime.example.com", "bedrock endpoint baseURL");

		final bedrockEnv = registry(config({}), {AWS_REGION: "eu-west-1", AWS_PROFILE: "default"});
		eq(Reflect.field(bedrockEnv.getProvider(ProviderID.make("amazon-bedrock")).options, "region"), "eu-west-1", "bedrock env region");

		final bedrockAuth = registry(config({
			provider: {
				"amazon-bedrock": {options: {region: "us-east-1"}},
			},
		}), {}, {"amazon-bedrock": {type: "api", key: "bearer"}});
		eq(bedrockAuth.getProvider(ProviderID.make("amazon-bedrock")) != null, true, "bedrock auth bearer");
	}

	static function registry(config:ConfigInfo, ?env:Dynamic, ?auth:Dynamic):ProviderRegistry {
		return new ProviderRegistry({config: config, env: env == null ? {} : env, auth: auth == null ? {} : auth});
	}

	static function config(data:Dynamic):ConfigInfo {
		final info = ConfigInfo.empty("fixture-user");
		info.disabledProviders = strings(Reflect.field(data, "disabled_providers"));
		info.enabledProviders = strings(Reflect.field(data, "enabled_providers"));
		info.model = stringField(data, "model");
		info.smallModel = stringField(data, "small_model");
		// Fixture boundary: test object literals mirror JSON config and are narrowed by the app types.
		info.provider = cast Reflect.field(data, "provider");
		return info;
	}

	static function strings(value:Dynamic):Null<Array<String>> {
		if (!Std.isOfType(value, Array))
			return null;
		final result:Array<String> = [];
		final arr:Array<Dynamic> = cast value;
		for (item in arr)
			result.push(Std.string(item));
		return result;
	}

	static function stringField(data:Dynamic, field:String):Null<String> {
		final value = Reflect.field(data, field);
		return Std.isOfType(value, String) ? Std.string(value) : null;
	}

	static function modelCount(registry:ProviderRegistry, providerID:String):Int {
		var count = 0;
		for (_ in registry.getProvider(ProviderID.make(providerID)).models.keys())
			count++;
		return count;
	}

	static function expectProviderFailure(run:() -> Void, label:String, matches:ProviderFailure->Bool):Void {
		try {
			run();
		} catch (error:ProviderException) {
			if (matches(error.failure))
				return;
			throw '${label}: unexpected failure ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
