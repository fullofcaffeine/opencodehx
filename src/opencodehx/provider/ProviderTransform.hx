package opencodehx.provider;

import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

using StringTools;

typedef ProviderTransformOptionsInput = {
	final model:ProviderModel;
	final sessionID:String;
	@:optional final providerOptions:ProviderOptions;
}

class ProviderTransform {
	public static inline final OUTPUT_TOKEN_MAX:Float = 32000;

	public static function options(input:ProviderTransformOptionsInput):ProviderOptions {
		final result = optionMap();
		final model = input.model;
		final providerID = model.providerID.toString();
		final apiID = model.api.id;
		final apiNpm = model.api.npm;
		final lowerApiID = apiID.toLowerCase();

		if (providerID == "openai" || apiNpm == "@ai-sdk/openai" || apiNpm == "@ai-sdk/github-copilot")
			result.set("store", false);

		if (apiNpm == "@ai-sdk/azure") {
			result.set("store", true);
			result.set("promptCacheKey", input.sessionID);
		}

		if (apiNpm == "@openrouter/ai-sdk-provider" || apiNpm == "@llmgateway/ai-sdk-provider") {
			result.set("usage", record1("include", true));
			if (apiID.contains("gemini-3"))
				result.set("reasoning", record1("effort", "high"));
		}

		if (providerID == "baseten" || (providerID == "opencode" && (apiID == "kimi-k2-thinking" || apiID == "glm-4.6")))
			result.set("chat_template_args", record1("enable_thinking", true));

		if ((providerID.contains("zai") || providerID.contains("zhipuai")) && apiNpm == "@ai-sdk/openai-compatible") {
			result.set("thinking", record2("type", "enabled", "clear_thinking", false));
		}

		if (providerID == "openai" || optionBool(input.providerOptions, "setCacheKey"))
			result.set("promptCacheKey", input.sessionID);

		if ((apiNpm == "@ai-sdk/google" || apiNpm == "@ai-sdk/google-vertex") && model.capabilities.reasoning) {
			final thinkingConfig = record1("includeThoughts", true);
			if (apiID.contains("gemini-3"))
				thinkingConfig.set("thinkingLevel", "high");
			result.set("thinkingConfig", thinkingConfig);
		}

		if ((apiNpm == "@ai-sdk/anthropic" || apiNpm == "@ai-sdk/google-vertex/anthropic")
			&& (lowerApiID.contains("k2p") || lowerApiID.contains("kimi-k2.") || lowerApiID.contains("kimi-k2p"))) {
			result.set("thinking", record2("type", "enabled", "budgetTokens", Math.min(16000, Math.floor(model.limit.output / 2 - 1))));
		}

		if (providerID == "alibaba-cn"
			&& model.capabilities.reasoning
			&& apiNpm == "@ai-sdk/openai-compatible"
			&& !lowerApiID.contains("kimi-k2-thinking")) {
			result.set("enable_thinking", true);
		}

		if (apiID.contains("gpt-5") && !apiID.contains("gpt-5-chat")) {
			if (!apiID.contains("gpt-5-pro")) {
				result.set("reasoningEffort", "medium");
				if (apiNpm == "@ai-sdk/openai" || apiNpm == "@ai-sdk/azure" || apiNpm == "@ai-sdk/github-copilot")
					result.set("reasoningSummary", "auto");
			}

			if (apiID.contains("gpt-5.") && !apiID.contains("codex") && !apiID.contains("-chat") && providerID != "azure")
				result.set("textVerbosity", "low");

			if (providerID.startsWith("opencode")) {
				result.set("promptCacheKey", input.sessionID);
				result.set("include", ["reasoning.encrypted_content"]);
				result.set("reasoningSummary", "auto");
			}
		}

		if (providerID == "venice")
			result.set("promptCacheKey", input.sessionID);

		if (providerID == "openrouter")
			result.set("prompt_cache_key", input.sessionID);

		if (apiNpm == "@ai-sdk/gateway")
			result.set("gateway", record1("caching", "auto"));

		return result;
	}

	public static function providerOptions(model:ProviderModel, options:ProviderOptions):ProviderOptions {
		if (model.api.npm == "@ai-sdk/gateway")
			return gatewayProviderOptions(model, options);

		final key = sdkKey(model.api.npm);
		if (model.api.npm == "@ai-sdk/azure") {
			final result = optionMap();
			result.set("openai", options);
			result.set("azure", options);
			return result;
		}
		return record1(key == null ? model.providerID.toString() : key, options);
	}

	public static function maxOutputTokens(model:ProviderModel):Float {
		final capped = Math.min(model.limit.output, OUTPUT_TOKEN_MAX);
		return capped == 0 ? OUTPUT_TOKEN_MAX : capped;
	}

	public static function temperature(model:ProviderModel):Null<Float> {
		final id = model.id.toString().toLowerCase();
		if (id.contains("qwen"))
			return 0.55;
		if (id.contains("claude"))
			return null;
		if (id.contains("gemini"))
			return 1.0;
		if (id.contains("glm-4.6") || id.contains("glm-4.7"))
			return 1.0;
		if (id.contains("minimax-m2"))
			return 1.0;
		if (id.contains("kimi-k2")) {
			if (id.contains("thinking") || id.contains("k2.") || id.contains("k2p") || id.contains("k2-5"))
				return 1.0;
			return 0.6;
		}
		return null;
	}

	public static function topP(model:ProviderModel):Null<Float> {
		final id = model.id.toString().toLowerCase();
		if (id.contains("qwen"))
			return 1;
		if (id.contains("minimax-m2") || id.contains("gemini") || id.contains("kimi-k2.5") || id.contains("kimi-k2p5") || id.contains("kimi-k2-5"))
			return 0.95;
		return null;
	}

	public static function topK(model:ProviderModel):Null<Int> {
		final id = model.id.toString().toLowerCase();
		if (id.contains("minimax-m2")) {
			if (id.contains("m2.") || id.contains("m25") || id.contains("m21"))
				return 40;
			return 20;
		}
		if (id.contains("gemini"))
			return 64;
		return null;
	}

	static function gatewayProviderOptions(model:ProviderModel, options:ProviderOptions):ProviderOptions {
		final slug = gatewaySlug(model.api.id);
		final result = optionMap();
		// The Gateway option itself is SDK-owned passthrough data: upstream may
		// provide routing records, booleans, or future provider values here. Keep
		// it Dynamic only inside this boundary, then preserve or merge it after
		// runtime shape checks.
		final gateway:Dynamic = options.exists("gateway") ? options.get("gateway") : null;
		final rest = optionMap();
		for (key in options.keys()) {
			if (key != "gateway")
				rest.set(key, options.get(key));
		}

		if (options.exists("gateway"))
			result.set("gateway", gateway);

		if (!empty(rest)) {
			if (slug != null) {
				result.set(slug, rest);
			} else if (isRecord(gateway)) {
				result.set("gateway", mergeRecord(gateway, rest));
			} else {
				result.set("gateway", rest);
			}
		}
		return result;
	}

	static function gatewaySlug(apiID:String):Null<String> {
		final slash = apiID.indexOf("/");
		if (slash <= 0)
			return null;
		final raw = apiID.substr(0, slash);
		return switch raw {
			case "amazon": "bedrock";
			case _: raw;
		}
	}

	static function sdkKey(npm:String):Null<String> {
		return switch npm {
			case "@ai-sdk/github-copilot": "copilot";
			case "@ai-sdk/azure": "azure";
			case "@ai-sdk/openai": "openai";
			case "@ai-sdk/amazon-bedrock": "bedrock";
			case "@ai-sdk/anthropic" | "@ai-sdk/google-vertex/anthropic": "anthropic";
			case "@ai-sdk/google-vertex": "vertex";
			case "@ai-sdk/google": "google";
			case "@ai-sdk/gateway": "gateway";
			case "@openrouter/ai-sdk-provider": "openrouter";
			case _: null;
		}
	}

	static function optionBool(options:Null<ProviderOptions>, key:String):Bool {
		if (options == null || !options.exists(key))
			return false;
		final value = options.get(key);
		return Std.isOfType(value, Bool) && value == true;
	}

	static function optionMap():ProviderOptions {
		// ProviderOptions mirrors upstream's provider-SDK passthrough record. The
		// transform module owns these open maps only at the SDK request boundary;
		// stable provider-specific fields should graduate to typed facades.
		return new haxe.DynamicAccess<Dynamic>();
	}

	static function record1<T>(key:String, value:T):ProviderOptions {
		final result = optionMap();
		result.set(key, value);
		return result;
	}

	static function record2<A, B>(keyA:String, valueA:A, keyB:String, valueB:B):ProviderOptions {
		final result = optionMap();
		result.set(keyA, valueA);
		result.set(keyB, valueB);
		return result;
	}

	static function empty(options:ProviderOptions):Bool {
		for (_ in options.keys())
			return false;
		return true;
	}

	static function isRecord(value:Dynamic):Bool {
		// Provider transform options are an SDK passthrough boundary. The only
		// dynamic inspection here distinguishes plain option records from
		// primitive/array values before nesting them under AI SDK provider keys.
		if (value == null)
			return false;
		if (Std.isOfType(value, Array) || Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return false;
		return Reflect.isObject(value);
	}

	static function mergeRecord(current:Dynamic, next:ProviderOptions):ProviderOptions {
		// `current` comes from the open ProviderOptions SDK boundary. Reflection is
		// guarded by isRecord(), and the merged value is immediately returned as an
		// SDK passthrough record rather than exposed to core application code.
		final result = optionMap();
		if (isRecord(current)) {
			for (field in Reflect.fields(current))
				result.set(field, Reflect.field(current, field));
		}
		for (field in next.keys())
			result.set(field, next.get(field));
		return result;
	}
}
