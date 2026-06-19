package opencodehx.provider;

import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTypes.ProviderVariants;
import opencodehx.provider.ProviderTypes.ProviderJsonSchema;

using StringTools;

typedef ProviderTransformOptionsInput = {
	final model:ProviderModel;
	final sessionID:String;
	@:optional final providerOptions:ProviderOptions;
}

class ProviderTransform {
	public static inline final OUTPUT_TOKEN_MAX:Float = 32000;
	static final WIDELY_SUPPORTED_EFFORTS = ["low", "medium", "high"];
	static final OPENAI_EFFORTS = ["none", "minimal", "low", "medium", "high", "xhigh"];

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

	public static function schema(model:ProviderModel, schema:ProviderJsonSchema):ProviderJsonSchema {
		if (model.providerID.toString() == "google" || model.api.id.contains("gemini"))
			sanitizeGeminiSchema(schema);
		return schema;
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

	public static function variants(model:ProviderModel):ProviderVariants {
		final result = variantMap();
		if (!model.capabilities.reasoning)
			return result;

		final id = model.id.toString().toLowerCase();
		final apiID = model.api.id.toLowerCase();
		final adaptiveEfforts = anthropicAdaptiveEfforts(model.api.id);

		if (id.contains("deepseek") || id.contains("minimax") || id.contains("glm") || id.contains("kimi") || id.contains("k2p") || id.contains("qwen")
			|| id.contains("big-pickle"))
			return result;

		if (id.contains("grok") && id.contains("grok-3-mini")) {
			if (model.api.npm == "@openrouter/ai-sdk-provider")
				return variantsFromEfforts(["low", "high"], effort -> record1("reasoning", record1("effort", effort)));
			return variantsFromEfforts(["low", "high"], effort -> record1("reasoningEffort", effort));
		}
		if (id.contains("grok"))
			return result;

		return switch model.api.npm {
			case "@openrouter/ai-sdk-provider":
				if (!id.contains("gpt") && !id.contains("gemini-3") && !id.contains("claude")) result else variantsFromEfforts(OPENAI_EFFORTS,
					effort -> record1("reasoning", record1("effort", effort)));

			case "@ai-sdk/gateway":
				gatewayVariants(model, id, adaptiveEfforts);

			case "@ai-sdk/github-copilot":
				copilotVariants(model, id);

			case "@ai-sdk/cerebras" | "@ai-sdk/togetherai" | "@ai-sdk/deepinfra" | "venice-ai-sdk-provider" | "@ai-sdk/openai-compatible" | "@ai-sdk/xai":
				variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningEffort", effort));

			case "@ai-sdk/azure":
				if (id == "o1-mini") result else {
					final efforts = WIDELY_SUPPORTED_EFFORTS.copy();
					if (id.contains("gpt-5-") || id == "gpt-5")
						efforts.unshift("minimal");
					variantsFromEfforts(efforts, openAiEffortOptions);
				}

			case "@ai-sdk/openai":
				openAiVariants(model, id);

			case "@ai-sdk/anthropic" | "@ai-sdk/google-vertex/anthropic":
				anthropicVariants(model, adaptiveEfforts, true);

			case "@ai-sdk/amazon-bedrock":
				bedrockVariants(model, adaptiveEfforts);

			case "@ai-sdk/google-vertex" | "@ai-sdk/google":
				googleVariants(id);

			case "@ai-sdk/mistral":
				if (apiID.contains("mistral-small-2603")
					|| apiID.contains("mistral-small-latest")) singleVariant("high", record1("reasoningEffort", "high")) else result;

			case "@ai-sdk/cohere" | "@ai-sdk/perplexity":
				result;

			case "@ai-sdk/groq":
				variantsFromEfforts(["none", "low", "medium", "high"], effort -> record1("reasoningEffort", effort));

			case "@jerome-benoit/sap-ai-provider-v2":
				sapVariants(model, id, adaptiveEfforts);

			case _:
				result;
		}
	}

	static function sanitizeGeminiSchema(schema:ProviderJsonSchema):ProviderJsonSchema {
		sanitizeProperties(schema.properties);
		sanitizeProperties(schema.patternProperties);
		sanitizeSchemaArray(schema.prefixItems);
		sanitizeSchemaArray(schema.anyOf);
		sanitizeSchemaArray(schema.oneOf);
		sanitizeSchemaArray(schema.allOf);
		final notSchema = schema.not;
		if (notSchema != null)
			schema.not = sanitizeGeminiSchema(notSchema);
		final initialItems = schema.items;
		if (initialItems != null)
			schema.items = sanitizeGeminiSchema(initialItems);

		normalizeEnumLiterals(schema);

		final schemaProperties = schema.properties;
		final schemaRequired = schema.required;
		if (schema.type == "object" && schemaProperties != null && schemaRequired != null) {
			final filtered:Array<String> = [];
			for (field in schemaRequired) {
				if (schemaProperties.exists(field))
					filtered.push(field);
			}
			schema.required = filtered;
		}

		if (schema.type == "array" && !hasSchemaCombiner(schema)) {
			var schemaItems = schema.items;
			if (schemaItems == null) {
				schemaItems = emptySchema();
				schema.items = schemaItems;
			}
			if (!hasSchemaIntent(schemaItems))
				schemaItems.type = "string";
		}

		if (schema.type != null && schema.type != "object" && !hasSchemaCombiner(schema)) {
			deleteSchemaField(schema, "properties");
			deleteSchemaField(schema, "required");
		}

		return schema;
	}

	static function sanitizeProperties(properties:Null<haxe.DynamicAccess<ProviderJsonSchema>>):Void {
		if (properties == null)
			return;
		for (field in properties.keys())
			sanitizeProperty(properties, field);
	}

	static function sanitizeProperty(properties:haxe.DynamicAccess<ProviderJsonSchema>, field:String):Void {
		final value = properties.get(field);
		if (value != null)
			properties.set(field, sanitizeGeminiSchema(value));
	}

	static function sanitizeSchemaArray(items:Null<Array<ProviderJsonSchema>>):Void {
		if (items == null)
			return;
		for (i in 0...items.length)
			items[i] = sanitizeGeminiSchema(items[i]);
	}

	static function hasSchemaCombiner(schema:ProviderJsonSchema):Bool {
		return schema.anyOf != null || schema.oneOf != null || schema.allOf != null;
	}

	static function hasSchemaIntent(schema:ProviderJsonSchema):Bool {
		return hasSchemaCombiner(schema)
			|| schema.type != null
			|| schema.properties != null
			|| schema.patternProperties != null
			|| schema.items != null
			|| schema.prefixItems != null
			|| schema.required != null
			|| schema.not != null
			|| schema.enumValues != null
			|| Reflect.hasField(schema, "const")
			|| Reflect.hasField(schema, "$ref")
			|| Reflect.hasField(schema, "additionalProperties");
	}

	static function normalizeEnumLiterals(schema:ProviderJsonSchema):Void {
		final values = schema.enumValues;
		if (values == null)
			return;
		// JSON Schema enum values are arbitrary literals. Dynamic is isolated to
		// this normalization step, then converted to strings for Gemini's stricter
		// schema acceptance rules.
		final strings:Array<String> = [];
		for (value in values)
			strings.push(Std.string(value));
		schema.enumValues = strings;
		if (schema.type == "integer" || schema.type == "number")
			schema.type = "string";
	}

	static function deleteSchemaField(schema:ProviderJsonSchema, field:String):Void {
		// Haxe has no typed object-field delete operator. Keep Reflect.deleteField
		// confined to JSON Schema cleanup where Gemini rejects these optional
		// TypeScript object keys on non-object schema nodes.
		Reflect.deleteField(schema, field);
	}

	static function emptySchema():ProviderJsonSchema {
		return {};
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

	static function gatewayVariants(model:ProviderModel, id:String, adaptiveEfforts:Array<String>):ProviderVariants {
		if (id.contains("anthropic")) {
			if (adaptiveEfforts.length > 0)
				return variantsFromEfforts(adaptiveEfforts, effort -> record2("thinking", record1("type", "adaptive"), "effort", effort));
			return thinkingBudgetVariants("thinking");
		}

		if (id.contains("google")) {
			if (id.contains("2.5"))
				return googleBudgetVariants();
			return variantsFromEfforts(["low", "high"], effort -> record2("includeThoughts", true, "thinkingLevel", effort));
		}

		return variantsFromEfforts(OPENAI_EFFORTS, effort -> record1("reasoningEffort", effort));
	}

	static function copilotVariants(model:ProviderModel, id:String):ProviderVariants {
		final result = variantMap();
		if (id.contains("gemini"))
			return result;
		if (id.contains("claude"))
			return variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningEffort", effort));

		final efforts = WIDELY_SUPPORTED_EFFORTS.copy();
		if (id.contains("5.1-codex-max") || id.contains("5.2") || id.contains("5.3")) {
			efforts.push("xhigh");
		} else if (id.contains("gpt-5") && model.release_date >= "2025-12-04") {
			efforts.push("xhigh");
		}
		return variantsFromEfforts(efforts, openAiEffortOptions);
	}

	static function openAiVariants(model:ProviderModel, id:String):ProviderVariants {
		final result = variantMap();
		if (id == "gpt-5-pro")
			return result;

		final efforts = if (id.contains("codex")) {
			final codex = WIDELY_SUPPORTED_EFFORTS.copy();
			if (id.contains("5.2") || id.contains("5.3"))
				codex.push("xhigh");
			codex;
		} else {
			final standard = WIDELY_SUPPORTED_EFFORTS.copy();
			if (id.contains("gpt-5-") || id == "gpt-5")
				standard.unshift("minimal");
			if (model.release_date >= "2025-11-13")
				standard.unshift("none");
			if (model.release_date >= "2025-12-04")
				standard.push("xhigh");
			standard;
		};

		return variantsFromEfforts(efforts, openAiEffortOptions);
	}

	static function anthropicVariants(model:ProviderModel, adaptiveEfforts:Array<String>, includeDisplay:Bool):ProviderVariants {
		if (model.providerID.toString() == "github-copilot" && model.api.id.contains("opus-4.7"))
			return singleVariant("medium", record1("reasoningEffort", "medium"));

		if (adaptiveEfforts.length > 0) {
			final summarized = includeDisplay && (model.api.id.contains("opus-4-7") || model.api.id.contains("opus-4.7"));
			return variantsFromEfforts(adaptiveEfforts, effort -> record2("thinking", adaptiveThinking(summarized), "effort", effort));
		}

		return thinkingBudgetVariants("thinking", Math.min(16000, Math.floor(model.limit.output / 2 - 1)), Math.min(31999, model.limit.output - 1));
	}

	static function bedrockVariants(model:ProviderModel, adaptiveEfforts:Array<String>):ProviderVariants {
		if (adaptiveEfforts.length > 0) {
			final summarized = model.api.id.contains("opus-4-7") || model.api.id.contains("opus-4.7");
			return variantsFromEfforts(adaptiveEfforts, effort -> record1("reasoningConfig", adaptiveReasoningConfig(effort, summarized)));
		}

		if (model.api.id.contains("anthropic"))
			return thinkingBudgetVariants("reasoningConfig", 16000, 31999);

		return variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningConfig", record2("type", "enabled", "maxReasoningEffort", effort)));
	}

	static function googleVariants(id:String):ProviderVariants {
		if (id.contains("2.5"))
			return googleBudgetVariants();

		final levels = id.contains("3.1") ? ["low", "medium", "high"] : ["low", "high"];
		return variantsFromEfforts(levels, effort -> record1("thinkingConfig", record2("includeThoughts", true, "thinkingLevel", effort)));
	}

	static function sapVariants(model:ProviderModel, id:String, adaptiveEfforts:Array<String>):ProviderVariants {
		if (model.api.id.contains("anthropic")) {
			if (adaptiveEfforts.length > 0)
				return variantsFromEfforts(adaptiveEfforts, effort -> record2("thinking", record1("type", "adaptive"), "effort", effort));
			return thinkingBudgetVariants("thinking");
		}
		if (model.api.id.contains("gemini") && id.contains("2.5"))
			return googleBudgetVariants();
		if (model.api.id.contains("gpt") || ~/\bo[1-9]/.match(model.api.id))
			return variantsFromEfforts(WIDELY_SUPPORTED_EFFORTS, effort -> record1("reasoningEffort", effort));
		return variantMap();
	}

	static function anthropicAdaptiveEfforts(apiID:String):Array<String> {
		if (apiID.contains("opus-4-7") || apiID.contains("opus-4.7"))
			return ["low", "medium", "high", "xhigh", "max"];
		if (apiID.contains("opus-4-6") || apiID.contains("opus-4.6") || apiID.contains("sonnet-4-6") || apiID.contains("sonnet-4.6"))
			return ["low", "medium", "high", "max"];
		return [];
	}

	static function variantsFromEfforts(efforts:Array<String>, build:String->ProviderOptions):ProviderVariants {
		final result = variantMap();
		for (effort in efforts)
			result.set(effort, build(effort));
		return result;
	}

	static function singleVariant(name:String, options:ProviderOptions):ProviderVariants {
		final result = variantMap();
		result.set(name, options);
		return result;
	}

	static function openAiEffortOptions(effort:String):ProviderOptions {
		return record3("reasoningEffort", effort, "reasoningSummary", "auto", "include", ["reasoning.encrypted_content"]);
	}

	static function adaptiveThinking(displaySummarized:Bool):ProviderOptions {
		final result = record1("type", "adaptive");
		if (displaySummarized)
			result.set("display", "summarized");
		return result;
	}

	static function adaptiveReasoningConfig(effort:String, displaySummarized:Bool):ProviderOptions {
		final result = record2("type", "adaptive", "maxReasoningEffort", effort);
		if (displaySummarized)
			result.set("display", "summarized");
		return result;
	}

	static function thinkingBudgetVariants(key:String, ?highBudget:Float = 16000, ?maxBudget:Float = 31999):ProviderVariants {
		final result = variantMap();
		result.set("high", record1(key, record2("type", "enabled", "budgetTokens", highBudget)));
		result.set("max", record1(key, record2("type", "enabled", "budgetTokens", maxBudget)));
		return result;
	}

	static function googleBudgetVariants():ProviderVariants {
		final result = variantMap();
		result.set("high", record1("thinkingConfig", record2("includeThoughts", true, "thinkingBudget", 16000)));
		result.set("max", record1("thinkingConfig", record2("includeThoughts", true, "thinkingBudget", 24576)));
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

	static function variantMap():ProviderVariants {
		return new haxe.DynamicAccess<ProviderOptions>();
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

	static function record3<A, B, C>(keyA:String, valueA:A, keyB:String, valueB:B, keyC:String, valueC:C):ProviderOptions {
		final result = optionMap();
		result.set(keyA, valueA);
		result.set(keyB, valueB);
		result.set(keyC, valueC);
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
