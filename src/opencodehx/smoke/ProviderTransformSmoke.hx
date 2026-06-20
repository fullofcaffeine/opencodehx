package opencodehx.smoke;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.provider.ProviderTransform;
import opencodehx.provider.ProviderTypes.ProviderInterleaved;
import opencodehx.provider.ProviderTypes.ProviderInterleavedField;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderJsonSchema;
import opencodehx.provider.ProviderTypes.ProviderMessage;
import opencodehx.provider.ProviderTypes.ProviderMessageContent;
import opencodehx.provider.ProviderTypes.ProviderMessagePart;
import opencodehx.provider.ProviderTypes.ProviderMessagePartType;
import opencodehx.provider.ProviderTypes.ProviderMessageRole;
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
		requestOptionEdgeCases();
		smallOptionDefaults();
		providerOptionRouting();
		parameterDefaults();
		variantDefaults();
		schemaSanitizer();
		messageTransforms();
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

		final vertexNoReasoning = ProviderTransform.options({
			model: model("google-vertex", "gemini-2.0-flash", "@ai-sdk/google-vertex", false),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(exists(vertexNoReasoning, "thinkingConfig"), false, "vertex no reasoning");
	}

	static function gpt5VerbosityOptions():Void {
		final gpt52 = ProviderTransform.options({
			model: model("openai", "gpt-5.2", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(gpt52, "textVerbosity"), "low", "gpt-5.2 verbosity");
		eq(get(gpt52, "reasoningEffort"), "medium", "gpt-5.2 effort");
		eq(get(gpt52, "reasoningSummary"), "auto", "gpt-5.2 summary");

		final gpt51 = ProviderTransform.options({
			model: model("openai", "gpt-5.1", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(gpt51, "textVerbosity"), "low", "gpt-5.1 verbosity");

		final chatLatest = ProviderTransform.options({
			model: model("openai", "gpt-5.2-chat-latest", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(exists(chatLatest, "textVerbosity"), false, "gpt-5 chat verbosity");

		final chat = ProviderTransform.options({
			model: model("openai", "gpt-5-chat", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(exists(chat, "textVerbosity"), false, "gpt-5-chat verbosity");

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

	static function requestOptionEdgeCases():Void {
		final openrouter = ProviderTransform.options({
			model: model("openrouter", "google/gemini-3-pro", "@openrouter/ai-sdk-provider", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(object(get(openrouter, "usage")), "include"), true, "openrouter usage include");
		eq(get(object(get(openrouter, "reasoning")), "effort"), "high", "openrouter gemini-3 reasoning");
		eq(get(openrouter, "prompt_cache_key"), SESSION_ID, "openrouter prompt cache key");

		final llmGateway = ProviderTransform.options({
			model: model("llmgateway", "anthropic/claude-sonnet-4", "@llmgateway/ai-sdk-provider", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(object(get(llmGateway, "usage")), "include"), true, "llmgateway usage include");

		final baseten = ProviderTransform.options({
			model: model("baseten", "kimi-k2", "@ai-sdk/openai-compatible", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(object(get(baseten, "chat_template_args")), "enable_thinking"), true, "baseten chat template thinking");

		final opencodeKimi = ProviderTransform.options({
			model: model("opencode", "glm-4.6", "@ai-sdk/openai-compatible", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(object(get(opencodeKimi, "chat_template_args")), "enable_thinking"), true, "opencode glm chat template thinking");

		final anthropicKimi = ProviderTransform.options({
			model: model("anthropic", "kimi-k2p", "@ai-sdk/anthropic", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		final anthropicThinking = object(get(anthropicKimi, "thinking"));
		eq(get(anthropicThinking, "type"), "enabled", "anthropic kimi thinking type");
		eq(get(anthropicThinking, "budgetTokens"), 4095, "anthropic kimi thinking budget");

		final alibaba = ProviderTransform.options({
			model: model("alibaba-cn", "qwen3-plus", "@ai-sdk/openai-compatible", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(alibaba, "enable_thinking"), true, "alibaba-cn reasoning enable_thinking");

		final opencodeGpt5 = ProviderTransform.options({
			model: model("opencode", "gpt-5.2", "@ai-sdk/openai", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(opencodeGpt5, "promptCacheKey"), SESSION_ID, "opencode gpt-5 prompt cache");
		eq(get(opencodeGpt5, "reasoningSummary"), "auto", "opencode gpt-5 reasoning summary");
		eq(stringArray(get(opencodeGpt5, "include"))[0], "reasoning.encrypted_content", "opencode gpt-5 encrypted reasoning include");

		final venice = ProviderTransform.options({
			model: model("venice", "qwen3-coder", "venice-ai-sdk-provider", true),
			sessionID: SESSION_ID,
			providerOptions: optionMap(),
		});
		eq(get(venice, "promptCacheKey"), SESSION_ID, "venice prompt cache");
	}

	static function smallOptionDefaults():Void {
		final openai52 = ProviderTransform.smallOptions(model("openai", "gpt-5.2", "@ai-sdk/openai", true));
		eq(get(openai52, "store"), false, "small openai store");
		eq(get(openai52, "reasoningEffort"), "low", "small gpt-5.2 effort");

		final openai5 = ProviderTransform.smallOptions(model("openai", "gpt-5", "@ai-sdk/openai", true));
		eq(get(openai5, "reasoningEffort"), "minimal", "small gpt-5 effort");

		final copilotMini = ProviderTransform.smallOptions(model("github-copilot", "gpt-5-mini", "@ai-sdk/github-copilot", true));
		eq(get(copilotMini, "store"), false, "small copilot store");
		eq(get(copilotMini, "reasoningEffort"), "low", "small copilot mini effort");

		final openaiNonReasoning = ProviderTransform.smallOptions(model("openai", "gpt-4o-mini", "@ai-sdk/openai"));
		eq(get(openaiNonReasoning, "store"), false, "small openai non-gpt5 store");
		eq(exists(openaiNonReasoning, "reasoningEffort"), false, "small openai non-gpt5 no effort");

		final google3 = ProviderTransform.smallOptions(model("google", "gemini-3-pro", "@ai-sdk/google", true));
		eq(get(object(get(google3, "thinkingConfig")), "thinkingLevel"), "minimal", "small google gemini-3 thinking level");

		final google25 = ProviderTransform.smallOptions(model("google", "gemini-2.5-flash", "@ai-sdk/google", true));
		eq(get(object(get(google25, "thinkingConfig")), "thinkingBudget"), 0, "small google gemini-2.5 budget");

		final openrouterGoogle = ProviderTransform.smallOptions(model("openrouter", "google/gemini-3-pro", "@openrouter/ai-sdk-provider", true));
		eq(get(object(get(openrouterGoogle, "reasoning")), "enabled"), false, "small openrouter google disables reasoning");

		final llmGateway = ProviderTransform.smallOptions(model("llmgateway", "anthropic/claude-sonnet-4", "@llmgateway/ai-sdk-provider", true));
		eq(get(llmGateway, "reasoningEffort"), "minimal", "small llmgateway effort");

		final venice = ProviderTransform.smallOptions(model("venice", "qwen3-coder", "venice-ai-sdk-provider", true));
		eq(get(object(get(venice, "veniceParameters")), "disableThinking"), true, "small venice disables thinking");

		eq(empty(ProviderTransform.smallOptions(model("anthropic", "claude-sonnet-4", "@ai-sdk/anthropic"))), true, "small unsupported provider empty");
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
		eq(ProviderTransform.temperature(model("google", "gemini-3-pro", "@ai-sdk/google")), 1.0, "gemini temperature");
		eq(ProviderTransform.temperature(model("zai", "glm-4.7", "@ai-sdk/openai-compatible")), 1.0, "glm temperature");
		eq(ProviderTransform.temperature(model("moonshot", "kimi-k2", "@ai-sdk/openai-compatible")), 0.6, "kimi k2 base temperature");
		eq(ProviderTransform.temperature(model("moonshot", "kimi-k2-thinking", "@ai-sdk/openai-compatible")), 1.0, "kimi k2 thinking temperature");
		eq(ProviderTransform.topP(model("google", "gemini-3-pro", "@ai-sdk/google")), 0.95, "gemini topP");
		eq(ProviderTransform.topP(model("moonshot", "kimi-k2.5", "@ai-sdk/openai-compatible")), 0.95, "kimi k2.5 topP");
		eq(ProviderTransform.topK(model("google", "gemini-3-pro", "@ai-sdk/google")), 64, "gemini topK");
		eq(ProviderTransform.topK(model("minimax", "minimax-m2", "@ai-sdk/openai-compatible")), 20, "minimax m2 topK");
		eq(ProviderTransform.topK(model("minimax", "minimax-m2.1", "@ai-sdk/openai-compatible")), 40, "minimax m2 point topK");
		eq(ProviderTransform.maxOutputTokens(modelWithOutputLimit("openai", "gpt-4o", "@ai-sdk/openai", 128000)), ProviderTransform.OUTPUT_TOKEN_MAX,
			"max output token cap");
		eq(ProviderTransform.maxOutputTokens(modelWithOutputLimit("test", "tiny", "@ai-sdk/openai-compatible", 8192)), 8192, "max output under cap");
		eq(ProviderTransform.maxOutputTokens(modelWithOutputLimit("test", "unknown-output", "@ai-sdk/openai-compatible", 0)),
			ProviderTransform.OUTPUT_TOKEN_MAX, "max output zero fallback");
	}

	static function variantDefaults():Void {
		eq(countVariants(ProviderTransform.variants(model("openai", "gpt-4o", "@ai-sdk/openai", false))), 0, "no reasoning variants");
		eq(countVariants(ProviderTransform.variants(model("deepseek", "deepseek-r1", "@ai-sdk/openai-compatible", true))), 0, "deepseek variants");

		final openrouter = ProviderTransform.variants(model("openrouter", "gpt-4", "@openrouter/ai-sdk-provider", true));
		hasVariants(openrouter, ["none", "minimal", "low", "medium", "high", "xhigh"], "openrouter gpt efforts");
		eq(get(object(get(variant(openrouter, "low"), "reasoning")), "effort"), "low", "openrouter reasoning effort");

		final openrouterGrok = ProviderTransform.variants(model("openrouter", "grok-3-mini", "@openrouter/ai-sdk-provider", true));
		hasVariants(openrouterGrok, ["low", "high"], "openrouter grok mini efforts");
		eq(get(object(get(variant(openrouterGrok, "high"), "reasoning")), "effort"), "high", "openrouter grok mini reasoning effort");
		eq(countVariants(ProviderTransform.variants(model("openrouter", "grok-4", "@openrouter/ai-sdk-provider", true))), 0, "openrouter grok-4 variants");

		final gatewayAdaptive = ProviderTransform.variants(model("gateway", "anthropic/claude-opus-4-7", "@ai-sdk/gateway", true));
		hasVariants(gatewayAdaptive, ["low", "medium", "high", "xhigh", "max"], "gateway adaptive efforts");
		eq(get(object(get(variant(gatewayAdaptive, "xhigh"), "thinking")), "type"), "adaptive", "gateway adaptive thinking");

		final gatewayGoogle25 = ProviderTransform.variants(model("gateway", "google/gemini-2.5-pro", "@ai-sdk/gateway", true));
		hasVariants(gatewayGoogle25, ["high", "max"], "gateway google 2.5 budgets");
		eq(get(object(get(variant(gatewayGoogle25, "high"), "thinkingConfig")), "thinkingBudget"), 16000, "gateway google 2.5 high budget");

		final gatewayGeneric = ProviderTransform.variants(model("gateway", "gateway-model", "@ai-sdk/gateway", true));
		hasVariants(gatewayGeneric, ["none", "minimal", "low", "medium", "high", "xhigh"], "gateway generic efforts");
		eq(get(variant(gatewayGeneric, "xhigh"), "reasoningEffort"), "xhigh", "gateway generic xhigh effort");

		final cerebras = ProviderTransform.variants(model("cerebras", "llama-4", "@ai-sdk/cerebras", true));
		hasVariants(cerebras, ["low", "medium", "high"], "cerebras efforts");
		eq(get(variant(cerebras, "low"), "reasoningEffort"), "low", "cerebras low effort");

		final together = ProviderTransform.variants(model("togetherai", "llama-4", "@ai-sdk/togetherai", true));
		hasVariants(together, ["low", "medium", "high"], "togetherai efforts");
		eq(get(variant(together, "high"), "reasoningEffort"), "high", "togetherai high effort");

		final deepinfra = ProviderTransform.variants(model("deepinfra", "llama-4", "@ai-sdk/deepinfra", true));
		hasVariants(deepinfra, ["low", "medium", "high"], "deepinfra efforts");
		eq(get(variant(deepinfra, "medium"), "reasoningEffort"), "medium", "deepinfra medium effort");

		final openaiCompatibleReasoning = ProviderTransform.variants(model("custom-provider", "custom-model", "@ai-sdk/openai-compatible", true));
		hasVariants(openaiCompatibleReasoning, ["low", "medium", "high"], "openai-compatible generic efforts");
		eq(get(variant(openaiCompatibleReasoning, "low"), "reasoningEffort"), "low", "openai-compatible low effort");

		final copilot = ProviderTransform.variants(modelWithRelease("github-copilot", "gpt-5.2", "@ai-sdk/github-copilot", "2025-12-01", true));
		hasVariants(copilot, ["low", "medium", "high", "xhigh"], "copilot gpt-5.2 variants");
		eq(get(variant(copilot, "xhigh"), "reasoningSummary"), "auto", "copilot reasoning summary");

		final copilot54 = ProviderTransform.variants(modelWithRelease("github-copilot", "gpt-5.4", "@ai-sdk/github-copilot", "2026-03-05", true));
		hasVariants(copilot54, ["low", "medium", "high", "xhigh"], "copilot dated gpt-5.4 variants");

		final azure = ProviderTransform.variants(model("azure", "gpt-5", "@ai-sdk/azure", true));
		hasVariants(azure, ["minimal", "low", "medium", "high"], "azure gpt-5 variants");
		eq(get(variant(azure, "minimal"), "reasoningEffort"), "minimal", "azure minimal effort");
		eq(countVariants(ProviderTransform.variants(model("azure", "o1-mini", "@ai-sdk/azure", true))), 0, "azure o1-mini variants");

		final openai = ProviderTransform.variants(modelWithRelease("openai", "gpt-5-nano", "@ai-sdk/openai", "2025-12-05", true));
		hasVariants(openai, ["none", "minimal", "low", "medium", "high", "xhigh"], "openai dated variants");
		eq(countVariants(ProviderTransform.variants(model("openai", "gpt-5-pro", "@ai-sdk/openai", true))), 0, "openai gpt-5-pro variants");

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

		final xaiGrokMini = ProviderTransform.variants(model("xai", "grok-3-mini", "@ai-sdk/xai", true));
		hasVariants(xaiGrokMini, ["low", "high"], "xai grok mini efforts");
		eq(get(variant(xaiGrokMini, "low"), "reasoningEffort"), "low", "xai grok mini low effort");
		eq(countVariants(ProviderTransform.variants(model("xai", "grok-3", "@ai-sdk/xai", true))), 0, "xai grok-3 variants");

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

		final mixedRoot = objectSchema([
			{
				key: "spreadsheetData",
				value: objectSchema([{key: "rows", value: arraySchema(arraySchema({}))},])
			},
		]);
		final mixedRows = property(property(ProviderTransform.schema(gemini, mixedRoot), "spreadsheetData"), "rows");
		eq(items(items(mixedRows)).type, "string", "gemini mixed object/array default");

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

	static function messageTransforms():Void {
		final deepseek = modelWithRelease("deepseek", "deepseek-chat", "@ai-sdk/openai-compatible", "2024-01-01", true,
			{field: ProviderInterleavedField.ReasoningContent});
		final deepseekResult = ProviderTransform.message([
			message(ProviderMessageRole.Assistant, partContent([reasoningPart("Let me think about this..."), toolCallPart("tool/1", "bash"),])),
		], deepseek, optionMap());
		eq(partsOf(deepseekResult[0]).length, 1, "interleaved removes reasoning part");
		eq(partsOf(deepseekResult[0])[0].type, ProviderMessagePartType.ToolCall, "interleaved keeps tool call");
		final openaiCompatible = object(get(messageOptions(deepseekResult[0]), "openaiCompatible"));
		eq(get(openaiCompatible, "reasoning_content"), "Let me think about this...", "interleaved reasoning provider option");

		final openaiResult = ProviderTransform.message([
			message(ProviderMessageRole.Assistant, partContent([reasoningPart("Keep me"), textPart("Answer")])),
		], model("openai", "gpt-4", "@ai-sdk/openai"), optionMap());
		eq(partsOf(openaiResult[0]).length, 2, "non-interleaved keeps reasoning");

		final validBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ";
		final textOnly = modelWithRelease("text-only", "gpt-text", "@ai-sdk/openai", "2024-01-01", false, null, false, false);
		final unsupported = ProviderTransform.message([
			message(ProviderMessageRole.User, partContent([
				textPart("Compare attachments"),
				imagePart("data:image/png;base64,"),
				imagePart('data:image/png;base64,${validBase64}'),
				filePart("notes.pdf", "application/pdf"),
			])),
		], textOnly, optionMap());
		eq(partsOf(unsupported[0])[1].text, "ERROR: Image file is empty or corrupted. Please provide a valid image.", "empty image error");
		eq(partsOf(unsupported[0])[2].text, "ERROR: Cannot read image (this model does not support image input). Inform the user.", "unsupported image error");
		eq(partsOf(unsupported[0])[3].text, 'ERROR: Cannot read "notes.pdf" (this model does not support pdf input). Inform the user.',
			"unsupported file error");

		final anthropic = model("anthropic", "claude-3-5-sonnet-20241022", "@ai-sdk/anthropic");
		final validImage = ProviderTransform.message([
			message(ProviderMessageRole.User, partContent([
				textPart("What is in this image?"),
				imagePart('data:image/png;base64,${validBase64}'),
			])),
		], anthropic, optionMap());
		eq(partsOf(validImage[0]).length, 2, "valid image message length");
		eq(partsOf(validImage[0])[1].type, ProviderMessagePartType.Image, "valid image stays image");
		eq(partsOf(validImage[0])[1].image, 'data:image/png;base64,${validBase64}', "valid image payload preserved");

		final filtered = ProviderTransform.message([
			message(ProviderMessageRole.User, textContent("Hello")),
			message(ProviderMessageRole.Assistant, textContent("")),
			message(ProviderMessageRole.Assistant, partContent([textPart(""), reasoningPart(""), textPart("Answer")])),
			message(ProviderMessageRole.User, textContent("World")),
		], anthropic, optionMap());
		eq(filtered.length, 3, "anthropic filters empty messages");
		eq(textOf(filtered[0]), "Hello", "anthropic keeps first text");
		eq(partsOf(filtered[1]).length, 1, "anthropic filters empty parts");
		eq(partsOf(filtered[1])[0].text, "Answer", "anthropic keeps non-empty part");
		eq(textOf(filtered[2]), "World", "anthropic keeps final text");

		final openaiEmpty = ProviderTransform.message([
			message(ProviderMessageRole.Assistant, textContent("")),
			message(ProviderMessageRole.Assistant, partContent([textPart("")])),
		], model("openai", "gpt-4", "@ai-sdk/openai"), optionMap());
		eq(openaiEmpty.length, 2, "openai keeps empty messages");
		eq(textOf(openaiEmpty[0]), "", "openai keeps empty string");
		eq(partsOf(openaiEmpty[1]).length, 1, "openai keeps empty part");

		final split = ProviderTransform.message([
			message(ProviderMessageRole.User, partContent([textPart("Find PDFs")])),
			message(ProviderMessageRole.Assistant, partContent([
				toolCallPart("toolu_1", "read"),
				toolCallPart("toolu_2", "glob"),
				textPart("I checked your home directory."),
			])),
		], anthropic, optionMap());
		eq(split.length, 3, "anthropic splits assistant tool tails");
		eq(partsOf(split[1])[0].type, ProviderMessagePartType.Text, "anthropic split text first");
		eq(partsOf(split[2])[0].type, ProviderMessagePartType.ToolCall, "anthropic split tools second");

		final validOrder = ProviderTransform.message([
			message(ProviderMessageRole.Assistant, partContent([
				textPart("I checked your home directory."),
				toolCallPart("toolu_1", "read"),
				toolCallPart("toolu_2", "glob"),
			])),
		], anthropic, optionMap());
		eq(validOrder.length, 1, "anthropic valid tool order unchanged");
		eq(partsOf(validOrder[0])[0].type, ProviderMessagePartType.Text, "anthropic valid order keeps leading text");
		eq(partsOf(validOrder[0])[1].type, ProviderMessagePartType.ToolCall, "anthropic valid order keeps tool call");

		final systemCached = ProviderTransform.message([
			message(ProviderMessageRole.System, partContent([textPart("You are helpful")])),
			message(ProviderMessageRole.User, textContent("Hello")),
		], anthropic, optionMap());
		final anthropicCache = object(get(messageOptions(systemCached[0]), "anthropic"));
		eq(get(object(get(anthropicCache, "cacheControl")), "type"), "ephemeral", "anthropic message-level cache");
		assertCacheBundle(messageOptions(systemCached[0]), "anthropic cache bundle");
		eq(partsOf(systemCached[0])[0].providerOptions == null, true, "anthropic cache not on part");

		final gateway = model("vercel", "anthropic/claude-sonnet-4", "@ai-sdk/gateway", true);
		final gatewayResult = ProviderTransform.message([message(ProviderMessageRole.System, partContent([textPart("You are helpful")]))], gateway,
			optionMap());
		eq(gatewayResult[0].providerOptions == null, true, "gateway skips anthropic cache");

		final awsBedrock = ProviderTransform.message([
			message(ProviderMessageRole.System, partContent([textPart("You are helpful")])),
			message(ProviderMessageRole.User, partContent([textPart("Hello")])),
		],
			model("aws", "us.anthropic.claude-opus-4-6-v1", "@ai-sdk/amazon-bedrock"), optionMap());
		eq(get(object(get(messageOptions(awsBedrock[0]), "bedrock")), "cachePoint") != null, true, "bedrock npm cache at message level");
		eq(partsOf(awsBedrock[0])[0].providerOptions == null, true, "bedrock cache not on part");

		final customBedrock = ProviderTransform.message([message(ProviderMessageRole.User, textContent("Hello")),],
			modelWithApiID("amazon-bedrock", "custom-claude-sonnet-4.5", "arn:aws:bedrock:xxx:yyy:application-inference-profile/zzz", "@ai-sdk/amazon-bedrock"),
			optionMap());
		eq(get(object(get(messageOptions(customBedrock[0]), "bedrock")), "cachePoint") != null, true, "bedrock custom profile cache");

		final vertexAnthropic = ProviderTransform.message([
			message(ProviderMessageRole.System, textContent("You are helpful")),
			message(ProviderMessageRole.User, textContent("Hello")),
		],
			model("google-vertex-anthropic", "claude-sonnet-4@20250514", "@ai-sdk/google-vertex/anthropic"), optionMap());
		eq(get(object(get(messageOptions(vertexAnthropic[0]), "anthropic")), "cacheControl") != null, true, "vertex anthropic cache");
		assertCacheBundle(messageOptions(vertexAnthropic[0]), "vertex anthropic cache bundle");

		final alibabaPartCached = ProviderTransform.message([
			message(ProviderMessageRole.User, partContent([textPart("Cache this final part")])),
		], model("alibaba", "qwen3-max", "@ai-sdk/alibaba"), optionMap());
		eq(alibabaPartCached[0].providerOptions == null, true, "alibaba cache stays off message for normal part");
		assertCacheBundle(partOptionsOf(partsOf(alibabaPartCached[0])[0]), "alibaba normal part cache bundle");

		final approvalPart = toolApprovalResponsePart();
		final alibabaApprovalCached = ProviderTransform.message([message(ProviderMessageRole.User, partContent([approvalPart])),],
			model("alibaba", "qwen3-max", "@ai-sdk/alibaba"), optionMap());
		assertCacheBundle(messageOptions(alibabaApprovalCached[0]), "alibaba approval fallback cache bundle");
		eq(partsOf(alibabaApprovalCached[0])[0].providerOptions == null, true, "tool approval part keeps cache off part");

		final vertexSplit = ProviderTransform.message([
			message(ProviderMessageRole.Assistant, partContent([
				toolCallPart("toolu_1", "read"),
				toolCallPart("toolu_2", "glob"),
				textPart("I checked your home directory."),
			])),
		],
			model("google-vertex-anthropic", "claude-sonnet-4@20250514", "@ai-sdk/google-vertex/anthropic"), optionMap());
		eq(vertexSplit.length, 2, "vertex anthropic splits assistant tool tails");
		eq(partsOf(vertexSplit[0])[0].type, ProviderMessagePartType.Text, "vertex anthropic split text first");
		eq(partsOf(vertexSplit[1])[0].type, ProviderMessagePartType.ToolCall, "vertex anthropic split tools second");

		final itemIdPart = textPart("Hello");
		itemIdPart.providerOptions = record1("openai", record2("itemId", "msg_456", "reasoningEncryptedContent", "encrypted"));
		final itemIdMessage = message(ProviderMessageRole.Assistant, partContent([itemIdPart]));
		itemIdMessage.providerOptions = record2("openai", record1("itemId", "msg_root"), "extra", record1("itemId", "msg_extra"));
		final preservedIds = ProviderTransform.message([itemIdMessage], model("openai", "gpt-5", "@ai-sdk/openai", true), record1("store", false));
		eq(get(object(get(messageOptions(preservedIds[0]), "openai")), "itemId"), "msg_root", "store=false preserves root openai itemId");
		eq(get(object(get(messageOptions(preservedIds[0]), "extra")), "itemId"), "msg_extra", "store=false preserves root extra itemId");
		final preservedPartOpenAI = object(get(partOptionsOf(partsOf(preservedIds[0])[0]), "openai"));
		eq(get(preservedPartOpenAI, "itemId"), "msg_456", "store=false preserves part itemId");
		eq(get(preservedPartOpenAI, "reasoningEncryptedContent"), "encrypted", "store=false preserves encrypted reasoning metadata");

		final claudeScrub = ProviderTransform.message([
			message(ProviderMessageRole.Assistant, partContent([toolCallPart("bad/id!", "bash")])),
		], model("anthropic", "claude-sonnet-4", "@ai-sdk/anthropic"), optionMap());
		eq(partsOf(claudeScrub[0])[0].toolCallId, "bad_id_", "claude tool id scrub");

		final mistral = ProviderTransform.message([
			message(ProviderMessageRole.Tool, partContent([toolResultPart("abc-def!!", "bash")])),
			message(ProviderMessageRole.User, textContent("Continue")),
		], model("mistral", "mistral-small-latest", "@ai-sdk/mistral"), optionMap());
		eq(partsOf(mistral[0])[0].toolCallId, "abcdef000", "mistral tool id scrub");
		eq(partsOf(mistral[1])[0].text, "Done.", "mistral inserts assistant bridge");

		final providerOptions = record1("azure-cognitive-services", record1("someOption", "value"));
		final partOptions = record1("azure-cognitive-services", record1("part", true));
		final part = textPart("Hello");
		part.providerOptions = partOptions;
		final remapMessage = message(ProviderMessageRole.User, partContent([part]));
		remapMessage.providerOptions = providerOptions;
		final remapped = ProviderTransform.message([remapMessage], model("azure-cognitive-services", "gpt-4", "@ai-sdk/azure"), optionMap());
		eq(exists(messageOptions(remapped[0]), "azure"), true, "message provider options remapped");
		eq(exists(messageOptions(remapped[0]), "azure-cognitive-services"), false, "message provider id removed");
		eq(exists(partOptionsOf(partsOf(remapped[0])[0]), "azure"), true, "part provider options remapped");

		final copilotMessage = message(ProviderMessageRole.User, textContent("Hello"));
		copilotMessage.providerOptions = record1("github-copilot", record1("someOption", "value"));
		final copilotRemapped = ProviderTransform.message([copilotMessage], model("github-copilot", "gpt-5-mini", "@ai-sdk/github-copilot"), optionMap());
		eq(exists(messageOptions(copilotRemapped[0]), "copilot"), true, "copilot provider options remapped");
		eq(exists(messageOptions(copilotRemapped[0]), "github-copilot"), false, "copilot provider id removed");

		final bedrockMessage = message(ProviderMessageRole.User, textContent("Hello"));
		bedrockMessage.providerOptions = record1("my-bedrock", record1("someOption", "value"));
		final bedrockRemapped = ProviderTransform.message([bedrockMessage], model("my-bedrock", "test-model", "@ai-sdk/amazon-bedrock"), optionMap());
		eq(exists(messageOptions(bedrockRemapped[0]), "bedrock"), true, "bedrock provider options remapped");
		eq(exists(messageOptions(bedrockRemapped[0]), "my-bedrock"), false, "bedrock provider id removed");
	}

	static function model(providerID:String, apiID:String, npm:String, ?reasoning:Bool = false, ?interleaved:ProviderInterleaved, ?inputImage:Bool = true,
			?inputPdf:Bool = true):ProviderModel {
		return modelWithRelease(providerID, apiID, npm, "2024-01-01", reasoning, interleaved, inputImage, inputPdf);
	}

	static function modelWithRelease(providerID:String, apiID:String, npm:String, releaseDate:String, ?reasoning:Bool = false,
			?interleaved:ProviderInterleaved, ?inputImage:Bool = true, ?inputPdf:Bool = true, ?outputLimit:Float = 8192):ProviderModel {
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
					image: inputImage,
					video: false,
					pdf: inputPdf
				},
				output: {
					text: true,
					audio: false,
					image: false,
					video: false,
					pdf: false
				},
				interleaved: interleaved == null ? false : interleaved,
			},
			cost: {input: 0.001, output: 0.002, cache: {read: 0.0001, write: 0.0002}},
			limit: {context: 200000, output: outputLimit},
			options: optionMap(),
			headers: new DynamicAccess<String>(),
			release_date: releaseDate,
			variants: new DynamicAccess<ProviderOptions>(),
		};
	}

	static function modelWithOutputLimit(providerID:String, apiID:String, npm:String, output:Float):ProviderModel {
		return modelWithRelease(providerID, apiID, npm, "2024-01-01", false, null, true, true, output);
	}

	static function modelWithApiID(providerID:String, modelID:String, apiID:String, npm:String):ProviderModel {
		return {
			id: ModelID.make(modelID),
			providerID: ProviderID.make(providerID),
			name: modelID,
			api: {id: apiID, url: "https://api.example.test", npm: npm},
			status: "active",
			capabilities: {
				temperature: true,
				reasoning: true,
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
			release_date: "2024-01-01",
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

	static function empty(options:ProviderOptions):Bool {
		for (_ in options.keys())
			return false;
		return true;
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

	static function message(role:ProviderMessageRole, content:ProviderMessageContent):ProviderMessage {
		return {role: role, content: content};
	}

	static function textContent(text:String):ProviderMessageContent {
		return text;
	}

	static function partContent(parts:Array<ProviderMessagePart>):ProviderMessageContent {
		return parts;
	}

	static function textPart(text:String):ProviderMessagePart {
		return {type: ProviderMessagePartType.Text, text: text};
	}

	static function reasoningPart(text:String):ProviderMessagePart {
		return {type: ProviderMessagePartType.Reasoning, text: text};
	}

	static function imagePart(image:String):ProviderMessagePart {
		return {type: ProviderMessagePartType.Image, image: image};
	}

	static function filePart(filename:String, mediaType:String):ProviderMessagePart {
		return {type: ProviderMessagePartType.File, filename: filename, mediaType: mediaType};
	}

	static function toolCallPart(toolCallId:String, toolName:String):ProviderMessagePart {
		return {
			type: ProviderMessagePartType.ToolCall,
			toolCallId: toolCallId,
			toolName: toolName,
			input: Unknown.fromBoundary(record1("command", "echo hello")),
		};
	}

	static function toolResultPart(toolCallId:String, toolName:String):ProviderMessagePart {
		return {
			type: ProviderMessagePartType.ToolResult,
			toolCallId: toolCallId,
			toolName: toolName,
			output: Unknown.fromBoundary(record1("type", "text")),
		};
	}

	static function toolApprovalResponsePart():ProviderMessagePart {
		return {type: ProviderMessagePartType.ToolApprovalResponse};
	}

	static function partsOf(msg:ProviderMessage):Array<ProviderMessagePart> {
		if (!Std.isOfType(msg.content, Array))
			throw "Expected message part content";
		// Fixture assertion helper for AI SDK's `string | part[]` content union.
		// The runtime Array guard keeps the cast scoped to known test messages.
		return cast msg.content;
	}

	static function textOf(msg:ProviderMessage):String {
		if (!Std.isOfType(msg.content, String))
			throw "Expected message text content";
		// Fixture assertion helper for AI SDK's `string | part[]` content union.
		// The runtime String guard keeps the cast scoped to known test messages.
		return cast msg.content;
	}

	static function messageOptions(msg:ProviderMessage):ProviderOptions {
		final options = msg.providerOptions;
		if (options == null)
			throw "Missing message providerOptions";
		return options;
	}

	static function partOptionsOf(part:ProviderMessagePart):ProviderOptions {
		final options = part.providerOptions;
		if (options == null)
			throw "Missing part providerOptions";
		return options;
	}

	static function object(value:Dynamic):ProviderOptions {
		// ProviderTransform emits nested SDK option records through the open
		// ProviderOptions boundary. This cast is confined to smoke assertions for
		// keys that this fixture just created or that ProviderTransform produced.
		return cast value;
	}

	static function assertCacheBundle(options:ProviderOptions, label:String):Void {
		eq(get(object(get(object(get(options, "anthropic")), "cacheControl")), "type"), "ephemeral", label + " anthropic");
		eq(get(object(get(object(get(options, "openrouter")), "cacheControl")), "type"), "ephemeral", label + " openrouter");
		eq(get(object(get(object(get(options, "bedrock")), "cachePoint")), "type"), "default", label + " bedrock");
		eq(get(object(get(object(get(options, "openaiCompatible")), "cache_control")), "type"), "ephemeral", label + " openai compatible");
		eq(get(object(get(object(get(options, "copilot")), "copilot_cache_control")), "type"), "ephemeral", label + " copilot");
		eq(get(object(get(object(get(options, "alibaba")), "cacheControl")), "type"), "ephemeral", label + " alibaba");
	}

	static function stringArray(value:Dynamic):Array<String> {
		if (!Std.isOfType(value, Array))
			throw "Expected string array";
		// Request option fixtures read a known transform-produced string-array
		// field from the open SDK passthrough boundary.
		return cast value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
