package opencodehx.smoke;

import haxe.DynamicAccess;
import opencodehx.provider.ProviderTransform;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderJsonSchema;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTypes.ProviderVariants;

typedef SchemaEntry = {
	final key:String;
	final value:ProviderJsonSchema;
}

class ProviderTransformSmoke {
	static inline final SESSION_ID = "test-session-123";

	public static function run():Void {
		cacheAndStoreOptions();
		zaiThinkingOptions();
		googleThinkingOptions();
		gpt5VerbosityOptions();
		gatewayDefaults();
		providerOptionRouting();
		parameterDefaults();
		variantDefaults();
		schemaSanitizer();
	}

	static function cacheAndStoreOptions():Void {
		final base = model("anthropic", "claude-3-5-sonnet-20241022", "@ai-sdk/anthropic");
		eq(get(ProviderTransform.options({model: base, sessionID: SESSION_ID, providerOptions: record1("setCacheKey", true)}), "promptCacheKey"), SESSION_ID,
			"setCacheKey prompt cache");
		eq(exists(ProviderTransform.options({model: base, sessionID: SESSION_ID, providerOptions: record1("setCacheKey", false)}), "promptCacheKey"), false,
			"false setCacheKey");

		final openai = model("openai", "gpt-4", "@ai-sdk/openai");
		final openaiOptions = ProviderTransform.options({model: openai, sessionID: SESSION_ID, providerOptions: optionMap()});
		eq(get(openaiOptions, "promptCacheKey"), SESSION_ID, "openai prompt cache");
		eq(get(openaiOptions, "store"), false, "openai store false");

		final azure = model("azure", "gpt-4", "@ai-sdk/azure");
		final azureOptions = ProviderTransform.options({model: azure, sessionID: SESSION_ID, providerOptions: optionMap()});
		eq(get(azureOptions, "store"), true, "azure store true");
		eq(get(azureOptions, "promptCacheKey"), SESSION_ID, "azure prompt cache");
	}

	static function zaiThinkingOptions():Void {
		for (providerID in ["zai-coding-plan", "zai", "zhipuai-coding-plan", "zhipuai"]) {
			final result = ProviderTransform.options({
				model: model(providerID, "glm-4.6", "@ai-sdk/openai-compatible", true),
				sessionID: SESSION_ID,
				providerOptions: optionMap(),
			});
			final thinking = object(get(result, "thinking"));
			eq(get(thinking, "type"), "enabled", providerID + " thinking type");
			eq(get(thinking, "clear_thinking"), false, providerID + " thinking clear");
		}
	}

	static function googleThinkingOptions():Void {
		final noReasoning = ProviderTransform.options({
			model: model("google", "gemini-2.0-flash", "@ai-sdk/google", false),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(exists(noReasoning, "thinkingConfig"), false, "google no reasoning");

		final reasoning = ProviderTransform.options({
			model: model("google", "gemini-2.0-flash", "@ai-sdk/google", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		final thinkingConfig = object(get(reasoning, "thinkingConfig"));
		eq(get(thinkingConfig, "includeThoughts"), true, "google include thoughts");
	}

	static function gpt5VerbosityOptions():Void {
		final gpt52 = ProviderTransform.options({
			model: model("openai", "gpt-5.2", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(gpt52, "textVerbosity"), "low", "gpt-5.2 verbosity");

		final chatLatest = ProviderTransform.options({
			model: model("openai", "gpt-5.2-chat-latest", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(exists(chatLatest, "textVerbosity"), false, "gpt-5 chat verbosity");

		final codex = ProviderTransform.options({
			model: model("openai", "gpt-5.2-codex", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(exists(codex, "textVerbosity"), false, "gpt-5 codex verbosity");
	}

	static function gatewayDefaults():Void {
		final result = ProviderTransform.options({
			model: model("vercel", "anthropic/claude-sonnet-4", "@ai-sdk/gateway", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		final gateway = object(get(result, "gateway"));
		eq(get(gateway, "caching"), "auto", "gateway caching");
	}

	static function providerOptionRouting():Void {
		final bedrock = ProviderTransform.providerOptions(model("my-bedrock", "anthropic.claude-sonnet-4", "@ai-sdk/amazon-bedrock"),
			record1("cachePoint", record1("type", "default")));
		eq(exists(bedrock, "bedrock"), true, "bedrock sdk key");

		final gatewayAnthropic = ProviderTransform.providerOptions(model("vercel", "anthropic/claude-sonnet-4", "@ai-sdk/gateway"),
			record1("thinking", record2("type", "enabled", "budgetTokens", 12000)));
		eq(exists(gatewayAnthropic, "anthropic"), true, "gateway anthropic slug");
		eq(exists(gatewayAnthropic, "gateway"), false, "gateway no routing options");

		final gatewayFallback = ProviderTransform.providerOptions(model("vercel", "claude-sonnet-4", "@ai-sdk/gateway"), record1("reasoningEffort", "high"));
		eq(exists(gatewayFallback, "gateway"), true, "gateway fallback key");

		final split = record2("gateway", record1("order", ["vertex", "anthropic"]), "thinking", record2("type", "enabled", "budgetTokens", 12000));
		final gatewaySplit = ProviderTransform.providerOptions(model("vercel", "anthropic/claude-sonnet-4", "@ai-sdk/gateway"), split);
		eq(exists(gatewaySplit, "gateway"), true, "gateway routing kept");
		eq(exists(gatewaySplit, "anthropic"), true, "gateway provider split");

		final amazon = ProviderTransform.providerOptions(model("vercel", "amazon/nova-2-lite", "@ai-sdk/gateway"),
			record1("reasoningConfig", record1("type", "enabled")));
		eq(exists(amazon, "bedrock"), true, "gateway amazon slug maps to bedrock");

		final groq = ProviderTransform.providerOptions(model("vercel", "groq/llama-3.3-70b-versatile", "@ai-sdk/gateway"),
			record1("reasoningFormat", "parsed"));
		eq(exists(groq, "groq"), true, "gateway groq slug");
	}

	static function parameterDefaults():Void {
		eq(ProviderTransform.temperature(model("qwen", "qwen3-coder", "@ai-sdk/openai-compatible")), 0.55, "qwen temperature");
		eq(ProviderTransform.temperature(model("anthropic", "claude-sonnet-4", "@ai-sdk/anthropic")), null, "claude temperature");
		eq(ProviderTransform.topP(model("google", "gemini-3-pro", "@ai-sdk/google")), 0.95, "gemini topP");
		eq(ProviderTransform.topK(model("google", "gemini-3-pro", "@ai-sdk/google")), 64, "gemini topK");
	}

	static function variantDefaults():Void {
		eq(countVariants(ProviderTransform.variants(model("openai", "gpt-4o", "@ai-sdk/openai", false))), 0, "no reasoning variants");
		eq(countVariants(ProviderTransform.variants(model("deepseek", "deepseek-r1", "@ai-sdk/openai-compatible", true))), 0, "deepseek variants");

		final openrouter = ProviderTransform.variants(model("openrouter", "gpt-4", "@openrouter/ai-sdk-provider", true));
		hasVariants(openrouter, ["none", "minimal", "low", "medium", "high", "xhigh"], "openrouter gpt efforts");
		eq(get(object(get(variant(openrouter, "low"), "reasoning")), "effort"), "low", "openrouter reasoning effort");

		final gatewayAdaptive = ProviderTransform.variants(model("gateway", "anthropic/claude-opus-4-7", "@ai-sdk/gateway", true));
		hasVariants(gatewayAdaptive, ["low", "medium", "high", "xhigh", "max"], "gateway adaptive efforts");
		eq(get(object(get(variant(gatewayAdaptive, "xhigh"), "thinking")), "type"), "adaptive", "gateway adaptive thinking");

		final copilot = ProviderTransform.variants(modelWithRelease("github-copilot", "gpt-5.2", "@ai-sdk/github-copilot", "2025-12-01", true));
		hasVariants(copilot, ["low", "medium", "high", "xhigh"], "copilot gpt-5.2 variants");
		eq(get(variant(copilot, "xhigh"), "reasoningSummary"), "auto", "copilot reasoning summary");

		final azure = ProviderTransform.variants(model("azure", "gpt-5", "@ai-sdk/azure", true));
		hasVariants(azure, ["minimal", "low", "medium", "high"], "azure gpt-5 variants");
		eq(get(variant(azure, "minimal"), "reasoningEffort"), "minimal", "azure minimal effort");

		final openai = ProviderTransform.variants(modelWithRelease("openai", "gpt-5-nano", "@ai-sdk/openai", "2025-12-05", true));
		hasVariants(openai, ["none", "minimal", "low", "medium", "high", "xhigh"], "openai dated variants");

		final anthropic = ProviderTransform.variants(model("anthropic", "claude-opus-4-7", "@ai-sdk/anthropic", true));
		eq(get(object(get(variant(anthropic, "xhigh"), "thinking")), "display"), "summarized", "anthropic opus display");

		final bedrock = ProviderTransform.variants(model("bedrock", "anthropic.claude-opus-4-7", "@ai-sdk/amazon-bedrock", true));
		eq(get(object(get(variant(bedrock, "xhigh"), "reasoningConfig")), "maxReasoningEffort"), "xhigh", "bedrock adaptive effort");

		final google25 = ProviderTransform.variants(model("google", "gemini-2.5-pro", "@ai-sdk/google", true));
		eq(get(object(get(variant(google25, "max"), "thinkingConfig")), "thinkingBudget"), 24576, "google 2.5 budget");

		final google31 = ProviderTransform.variants(model("google", "gemini-3.1-pro", "@ai-sdk/google", true));
		hasVariants(google31, ["low", "medium", "high"], "google 3.1 levels");

		final groq = ProviderTransform.variants(model("groq", "llama-4", "@ai-sdk/groq", true));
		hasVariants(groq, ["none", "low", "medium", "high"], "groq efforts");

		final mistral = ProviderTransform.variants(model("mistral", "mistral-small-latest", "@ai-sdk/mistral", true));
		hasVariants(mistral, ["high"], "mistral small reasoning");
		eq(countVariants(ProviderTransform.variants(model("mistral", "mistral-large-latest", "@ai-sdk/mistral", true))), 0, "mistral large variants");

		final sapGpt = ProviderTransform.variants(model("sap-ai-core", "azure-openai--gpt-4o", "@jerome-benoit/sap-ai-provider-v2", true));
		hasVariants(sapGpt, ["low", "medium", "high"], "sap gpt variants");
		eq(countVariants(ProviderTransform.variants(model("sap-ai-core", "perplexity--sonar-pro", "@jerome-benoit/sap-ai-provider-v2", true))), 0,
			"sap sonar variants");
	}

	static function schemaSanitizer():Void {
		final gemini = model("google", "gemini-3-pro", "@ai-sdk/google", true);
		final arrayRoot = objectSchema([
			{key: "nodes", value: arraySchema()},
			{key: "edges", value: arraySchema({type: "string"})},
		]);
		final arrayResult = ProviderTransform.schema(gemini, arrayRoot);
		eq(items(property(arrayResult, "nodes")).type, "string", "gemini array default items");
		eq(items(property(arrayResult, "edges")).type, "string", "gemini array preserves items");

		final nestedRoot = objectSchema([{key: "matrix", value: arraySchema(arraySchema(arraySchema()))},]);
		final nested = ProviderTransform.schema(gemini, nestedRoot);
		eq(items(items(items(property(nested, "matrix")))).type, "string", "gemini nested array default");

		final anyOfRoot = objectSchema([
			{key: "edits", value: arraySchema({anyOf: [{type: "string"}, {type: "number"}]})},
		]);
		final anyOfItems = items(property(ProviderTransform.schema(gemini, anyOfRoot), "edits"));
		eq(anyOf(anyOfItems).length, 2, "gemini anyOf preserved");
		eq(anyOfItems.type, null, "gemini anyOf no sibling type");

		final invalidRoot = objectSchema([
			{key: "data", value: {type: "string", properties: properties([{key: "bad", value: {type: "string"}}]), required: ["bad"]}},
		]);
		final invalidData = property(ProviderTransform.schema(gemini, invalidRoot), "data");
		eq(invalidData.properties, null, "gemini strips non-object properties");
		eq(invalidData.required, null, "gemini strips non-object required");

		final requiredRoot = objectSchema([
			{key: "config", value: objectSchema([{key: "name", value: {type: "string"}}], ["name", "missing"])},
		]);
		final requiredConfig = property(ProviderTransform.schema(gemini, requiredRoot), "config");
		eq(required(requiredConfig).length, 1, "gemini filters required count");
		eq(required(requiredConfig)[0], "name", "gemini filters required field");

		final enumRoot = objectSchema([{key: "rank", value: enumSchema("integer", [1, 2])},]);
		final enumResult = property(ProviderTransform.schema(gemini, enumRoot), "rank");
		eq(enumResult.type, "string", "gemini enum type stringified");
		eq(enumValue(enumResult, 0), "1", "gemini enum value stringified");

		final openaiRoot = objectSchema([
			{key: "data", value: {type: "string", properties: properties([{key: "stillHere", value: {type: "string"}}])}},
		]);
		final openaiResult = ProviderTransform.schema(model("openai", "gpt-4", "@ai-sdk/openai"), openaiRoot);
		eq(propertiesOf(property(openaiResult, "data")).exists("stillHere"), true, "non-gemini schema unchanged");
	}

	static function model(providerID:String, apiID:String, npm:String, ?reasoning:Bool = false):ProviderModel {
		return modelWithRelease(providerID, apiID, npm, "2024-01-01", reasoning);
	}

	static function modelWithRelease(providerID:String, apiID:String, npm:String, releaseDate:String, ?reasoning:Bool = false):ProviderModel {
		return {
			id: ModelID.make(apiID),
			providerID: ProviderID.make(providerID),
			name: apiID,
			api: {id: apiID, url: "https://api.example.test", npm: npm},
			status: "active",
			capabilities: {
				temperature: true,
				reasoning: reasoning,
				attachment: true,
				toolcall: true,
				input: {
					text: true,
					audio: false,
					image: true,
					video: false,
					pdf: true
				},
				output: {
					text: true,
					audio: false,
					image: false,
					video: false,
					pdf: false
				},
				interleaved: false,
			},
			cost: {input: 0.001, output: 0.002, cache: {read: 0.0001, write: 0.0002}},
			limit: {context: 200000, output: 8192},
			options: optionMap(),
			headers: new DynamicAccess<String>(),
			release_date: releaseDate,
			variants: new DynamicAccess<ProviderOptions>(),
		};
	}

	static function optionMap():ProviderOptions {
		// ProviderOptions is intentionally open SDK passthrough data. Smoke
		// fixtures keep values to stable upstream option shapes and assert only
		// known keys produced by ProviderTransform.
		return new DynamicAccess<Dynamic>();
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

	static function get(options:ProviderOptions, key:String):Dynamic {
		// ProviderOptions values are the documented SDK passthrough boundary; each
		// assertion immediately narrows a known key from the transform under test.
		return options.get(key);
	}

	static function exists(options:ProviderOptions, key:String):Bool {
		return options.exists(key);
	}

	static function variant(variants:ProviderVariants, key:String):ProviderOptions {
		final found = variants.get(key);
		if (found == null)
			throw 'Missing variant ${key}';
		return found;
	}

	static function countVariants(variants:ProviderVariants):Int {
		var count = 0;
		for (_ in variants.keys())
			count++;
		return count;
	}

	static function hasVariants(variants:ProviderVariants, expected:Array<String>, label:String):Void {
		eq(countVariants(variants), expected.length, label + " count");
		for (key in expected) {
			if (!variants.exists(key))
				throw '${label}: missing ${key}';
		}
	}

	static function objectSchema(entries:Array<SchemaEntry>, ?required:Array<String>):ProviderJsonSchema {
		final out:ProviderJsonSchema = {type: "object", properties: properties(entries)};
		if (required != null)
			out.required = required;
		return out;
	}

	static function arraySchema(?schemaItems:ProviderJsonSchema):ProviderJsonSchema {
		final out:ProviderJsonSchema = {type: "array"};
		if (schemaItems != null)
			out.items = schemaItems;
		return out;
	}

	static function properties(entries:Array<SchemaEntry>):haxe.DynamicAccess<ProviderJsonSchema> {
		final result = new haxe.DynamicAccess<ProviderJsonSchema>();
		for (entry in entries)
			result.set(entry.key, entry.value);
		return result;
	}

	static function property(schema:ProviderJsonSchema, key:String):ProviderJsonSchema {
		final schemaProperties = propertiesOf(schema);
		final found = schemaProperties.get(key);
		if (found == null)
			throw 'Missing schema property ${key}';
		return found;
	}

	static function items(schema:ProviderJsonSchema):ProviderJsonSchema {
		if (schema.items == null)
			throw "Missing schema items";
		return schema.items;
	}

	static function propertiesOf(schema:ProviderJsonSchema):haxe.DynamicAccess<ProviderJsonSchema> {
		final schemaProperties = schema.properties;
		if (schemaProperties == null)
			throw "Missing schema properties";
		return schemaProperties;
	}

	static function required(schema:ProviderJsonSchema):Array<String> {
		final schemaRequired = schema.required;
		if (schemaRequired == null)
			throw "Missing schema required";
		return schemaRequired;
	}

	static function anyOf(schema:ProviderJsonSchema):Array<ProviderJsonSchema> {
		final value = schema.anyOf;
		if (value == null)
			throw "Missing schema anyOf";
		return value;
	}

	static function enumSchema(type:String, values:Array<Int>):ProviderJsonSchema {
		final schema:ProviderJsonSchema = {type: type};
		// JSON Schema enum literals are arbitrary runtime values; keep the test
		// fixture values inside the explicit schema-boundary enum field.
		final enumValues:Array<Dynamic> = [];
		for (value in values)
			enumValues.push(value);
		schema.enumValues = enumValues;
		return schema;
	}

	static function enumValue(schema:ProviderJsonSchema, index:Int):String {
		// The sanitizer stringifies enum literals; values are read from the
		// explicit schema-boundary enum field and compared as strings.
		final values = schema.enumValues;
		if (values == null)
			throw "Missing enum values";
		return Std.string(values[index]);
	}

	static function object(value:Dynamic):ProviderOptions {
		// ProviderTransform emits nested SDK option records through the open
		// ProviderOptions boundary. This cast is confined to smoke assertions for
		// keys that this fixture just created or that ProviderTransform produced.
		return cast value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
