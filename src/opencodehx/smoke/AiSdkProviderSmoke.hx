package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import haxe.Exception;
import js.lib.Promise;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.ConfigProviderConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelConfig;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelCallOptions;
import opencodehx.externs.ai.AiSdk.AiLanguageModelGenerateResult;
import opencodehx.externs.ai.AiSdk.AiLanguageModelSpecificationVersion;
import opencodehx.externs.ai.AiSdk.AiLanguageModelStreamResult;
import opencodehx.externs.ai.AiSdk.AiSdkBundledProvider;
import opencodehx.externs.ai.AiSdk.AiSupportedUrls;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.provider.AiSdkLanguageLoader;
import opencodehx.provider.AiSdkLanguageLoader.AiSdkModelMethod;
import opencodehx.provider.AiSdkProvider;
import opencodehx.provider.AiSdkProvider.AiSdkMockModel;
import opencodehx.provider.AiSdkProvider.AiSdkStreamEvent;
import opencodehx.provider.AiSdkProvider.AiSdkStreamResult;
import opencodehx.provider.CloudflareAiGatewayLoader;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ProviderCapabilities;
import opencodehx.provider.ProviderTypes.ProviderCost;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderLimit;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderOptions;

class AiSdkProviderSmoke {
	@:async
	public static function run():Promise<Void> {
		await(textStream());
		await(toolCallStream());
		await(errorStream());
		await(abortStream());
		openAICompatibleFactory();
		cloudflareGatewayFactory();
		anthropicFactory();
		sdkModelSelection();
		sdkFailureSelection();
	}

	@:async
	static function textStream():Promise<Void> {
		final result = @:await AiSdkProvider.stream({
			model: AiSdkMockModel.text(["Hello ", "AI SDK"]),
			prompt: "Say hello.",
		});
		eq(result.text, "Hello AI SDK", "ai sdk text");
		eq(result.finishReason, AiFinishReason.Stop, "ai sdk text finish");
		eq(result.totalUsage.totalTokens, 7.0, "ai sdk text usage");
		eq(count(result, function(event) return switch event {
			case TextDelta(_): true;
			case _: false;
		}), 2, "ai sdk text deltas");
	}

	@:async
	static function toolCallStream():Promise<Void> {
		final result = @:await AiSdkProvider.stream({
			model: AiSdkMockModel.toolCall(),
			prompt: "Read README.md.",
			tools: AiSdkProvider.toolSet("read", AiSdkProvider.readTool()),
		});
		eq(result.text, "", "ai sdk tool text");
		eq(result.finishReason, AiFinishReason.ToolCalls, "ai sdk tool finish");
		eq(hasEvent(result, function(event) return switch event {
			case ToolCall("tool_1", "read"): true;
			case _: false;
		}), true, "ai sdk tool call event");
		eq(hasEvent(result, function(event) return switch event {
			case ToolResult("tool_1", "read"): true;
			case _: false;
		}), true, "ai sdk tool result event");
	}

	@:async
	static function errorStream():Promise<Void> {
		final result = @:await AiSdkProvider.stream({
			model: AiSdkMockModel.error("fixture provider error"),
			prompt: "Fail.",
		});
		eq(result.finishReason, AiFinishReason.Error, "ai sdk error finish");
		eq(result.errors[0], "fixture provider error", "ai sdk error callback");
		eq(hasEvent(result, function(event) return switch event {
			case StreamError("fixture provider error"): true;
			case _: false;
		}), true, "ai sdk error event");
	}

	@:async
	static function abortStream():Promise<Void> {
		final result = @:await AiSdkProvider.stream({
			model: AiSdkMockModel.abortable(),
			prompt: "Abort.",
			abortImmediately: true,
		});
		eq(result.aborted, true, "ai sdk abort flag");
		eq(result.text, "", "ai sdk abort text");
		eq(hasEvent(result, function(event) return switch event {
			case StreamAbort(AiSdkProvider.ABORT_REASON): true;
			case _: false;
		}), true, "ai sdk abort event");
	}

	static function openAICompatibleFactory():Void {
		final registry = new ProviderRegistry({config: sdkConfig(), env: {}, auth: {}});
		final provider = requireProvider(registry.getProvider(ProviderID.make("sdk-compatible")), "sdk-compatible provider");
		final model = registry.getModel(ProviderID.make("sdk-compatible"), ModelID.make("local-alias"));
		final resolved = registry.resolveLanguage(model);
		eq(resolved.sdkModelID, "remote-model", "ai sdk factory model id");
		eq(resolved.language.modelId, "remote-model", "ai sdk language model id");
		eq(resolved.language.provider, "sdk-compatible.chat", "ai sdk language provider");
		eq(AiSdkLanguageLoader.factoryOptions(provider, model).baseURL, "https://llm.example.test/v1", "ai sdk factory base url");
	}

	static function cloudflareGatewayFactory():Void {
		final registry = new ProviderRegistry({
			config: cloudflareConfig(),
			env: {
				CLOUDFLARE_ACCOUNT_ID: "fixture-account",
				CLOUDFLARE_GATEWAY_ID: "fixture-gateway",
				CLOUDFLARE_API_TOKEN: "fixture-token",
			},
			auth: {},
		});
		final provider = requireProvider(registry.getProvider(ProviderID.make("cloudflare-ai-gateway")), "cloudflare provider");
		final model = registry.getModel(ProviderID.make("cloudflare-ai-gateway"), ModelID.make("openai/gpt-5.2-codex"));
		final settings = CloudflareAiGatewayLoader.settings(provider, model);
		eq(settings.accountId, "fixture-account", "cloudflare account id");
		eq(settings.gateway, "fixture-gateway", "cloudflare gateway id");
		eq(settings.apiKey.orNull(), "fixture-token", "cloudflare api token");
		final options = settings.options.orNull();
		if (options == null)
			throw "cloudflare options: expected forwarded options";
		eq(options.cacheKey.orNull(), "cache-key", "cloudflare cache key");
		eq(options.cacheTtl.orNull(), 120, "cloudflare cache ttl");
		eq(options.skipCache.orNull(), true, "cloudflare skip cache");
		eq(options.collectLog.orNull(), false, "cloudflare collect log");
		final hasMetadata:Bool = options.metadata.orNull() != null;
		eq(hasMetadata, true, "cloudflare metadata forwarded");

		final resolved = registry.resolveLanguage(model);
		eq(resolved.sdkModelID, "openai/gpt-5.2-codex", "cloudflare sdk model id");
		eq(resolved.language.modelId, "openai/gpt-5.2-codex", "cloudflare language model id");
		eq(resolved.language.specificationVersion, AiLanguageModelSpecificationVersion.V3, "cloudflare language model spec");
	}

	static function anthropicFactory():Void {
		final registry = new ProviderRegistry({
			config: ConfigInfo.empty("fixture-user"),
			env: {ANTHROPIC_API_KEY: "fixture-anthropic-token"},
			auth: {},
		});
		final provider = requireProvider(registry.getProvider(ProviderID.make("anthropic")), "anthropic provider");
		final model = registry.getModel(ProviderID.make("anthropic"), ModelID.make("claude-haiku-4-5"));
		final settings = AiSdkLanguageLoader.anthropicFactoryOptions(provider, model);
		eq(settings.name.orNull(), "anthropic", "anthropic provider name");
		eq(settings.baseURL.orNull(), "https://api.anthropic.com/v1", "anthropic base url");
		eq(settings.apiKey.orNull(), "fixture-anthropic-token", "anthropic api key");
		final headers = settings.headers.orNull();
		if (headers == null)
			throw "anthropic headers: expected default beta headers";
		eq(headers.get("anthropic-beta"), "interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14", "anthropic beta header");

		final resolved = registry.resolveLanguage(model);
		eq(resolved.sdkModelID, "claude-haiku-4-5", "anthropic sdk model id");
		eq(resolved.method, AiSdkModelMethod.LanguageModel, "anthropic model method");
		eq(resolved.language.modelId, "claude-haiku-4-5", "anthropic language model id");
		eq(resolved.language.provider, "anthropic", "anthropic language provider");
		eq(resolved.language.specificationVersion, "v2", "anthropic language model spec");
	}

	static function sdkModelSelection():Void {
		final sdk = fixtureSdk();
		final openai = AiSdkLanguageLoader.resolveWithSdk(sdk, provider("openai"), model("openai", "gpt-5.2", "@ai-sdk/openai"));
		eq(openai.method, AiSdkModelMethod.Responses, "openai model method");
		eq(openai.language.modelId, "responses:gpt-5.2", "openai responses model");

		final xai = AiSdkLanguageLoader.resolveWithSdk(sdk, provider("xai"), model("xai", "grok-4", "@ai-sdk/xai"));
		eq(xai.method, AiSdkModelMethod.Responses, "xai model method");
		eq(xai.language.modelId, "responses:grok-4", "xai responses model");

		final azure = AiSdkLanguageLoader.resolveWithSdk(sdk, provider("azure"), model("azure", "gpt-5", "@ai-sdk/azure"));
		eq(azure.method, AiSdkModelMethod.Responses, "azure default model method");
		eq(azure.language.modelId, "responses:gpt-5", "azure default responses model");

		final azureChat = AiSdkLanguageLoader.resolveWithSdk(sdk, provider("azure"), model("azure", "gpt-4.1", "@ai-sdk/azure", useCompletionUrlsOptions()));
		eq(azureChat.method, AiSdkModelMethod.Chat, "azure completion-url model method");
		eq(azureChat.language.modelId, "chat:gpt-4.1", "azure completion-url chat model");

		final azureFallback = AiSdkLanguageLoader.resolveWithSdk(languageModelOnlySdk(), provider("azure"), model("azure", "gpt-4.1", "@ai-sdk/azure"));
		eq(azureFallback.method, AiSdkModelMethod.LanguageModel, "azure languageModel fallback method");
		eq(azureFallback.language.modelId, "languageModel:gpt-4.1", "azure languageModel fallback");
	}

	static function sdkFailureSelection():Void {
		expectFailure(() -> AiSdkLanguageLoader.resolve(provider("unsupported"), model("unsupported", "chat", "@ai-sdk/not-installed")),
			"unsupported sdk package", "Unsupported bundled AI SDK provider: @ai-sdk/not-installed");
		expectFailure(() -> AiSdkLanguageLoader.factoryOptions(provider("missing-url"),
			modelWithApiURL("missing-url", "chat", "@ai-sdk/openai-compatible", "")),
			"missing sdk base url", "Provider missing-url model chat needs api/baseURL before SDK loading");
		expectFailure(() -> AiSdkLanguageLoader.resolveWithSdk(chatOnlySdk(), provider("openai"), model("openai", "gpt-5.2", "@ai-sdk/openai")),
			"missing responses method", "AI SDK provider does not expose responses(modelID) for gpt-5.2");
		expectFailure(() -> AiSdkLanguageLoader.resolveWithSdk(responsesOnlySdk(), provider("azure"),
			model("azure", "gpt-4.1", "@ai-sdk/azure", useCompletionUrlsOptions())),
			"missing chat method", "AI SDK provider does not expose chat(modelID) for gpt-4.1");
	}

	static function sdkConfig():ConfigInfo {
		final info = ConfigInfo.empty("fixture-user");
		final providers = new DynamicAccess<ConfigProviderConfig>();
		final models = new DynamicAccess<ConfigProviderModelConfig>();
		models.set("local-alias", {
			id: "remote-model",
			name: "Local Alias",
			tool_call: true,
			limit: {context: 128000, output: 4096},
		});
		providers.set("sdk-compatible", {
			name: "SDK Compatible",
			npm: "@ai-sdk/openai-compatible",
			api: "https://llm.example.test/v1",
			env: [],
			options: sdkOptions(),
			models: models,
		});
		info.provider = providers;
		return info;
	}

	static function cloudflareConfig():ConfigInfo {
		final info = ConfigInfo.empty("fixture-user");
		final providers = new DynamicAccess<ConfigProviderConfig>();
		// Fixture boundary: Cloudflare options are provider-owned passthrough
		// data. The production loader narrows stable leaves before constructing
		// typed AiGatewaySettings, while metadata remains an opaque forwarded
		// record because Haxe never reads its provider-specific fields.
		final options = new DynamicAccess<Dynamic>();
		final metadata = new DynamicAccess<Dynamic>();
		metadata.set("invoked_by", "test");
		metadata.set("project", "opencodehx");
		options.set("metadata", metadata);
		options.set("cacheKey", "cache-key");
		options.set("cacheTtl", 120);
		options.set("skipCache", true);
		options.set("collectLog", false);
		providers.set("cloudflare-ai-gateway", {
			options: options,
		});
		info.provider = providers;
		return info;
	}

	static function sdkOptions():ProviderOptions {
		// Fixture boundary: ProviderOptions is intentionally SDK passthrough data.
		// This smoke keeps the values to the OpenAI-compatible factory's stable
		// subset and lets AiSdkLanguageLoader narrow them before use.
		final options = new DynamicAccess<Dynamic>();
		options.set("apiKey", "local-key");
		options.set("includeUsage", true);
		final headers = new DynamicAccess<String>();
		headers.set("x-opencodehx-smoke", "present");
		options.set("headers", headers);
		return options;
	}

	static function useCompletionUrlsOptions():ProviderOptions {
		// Fixture boundary: this is the stable OpenCode provider option that
		// selects Azure chat-completions URLs instead of responses URLs.
		// ProviderOptions itself is intentionally DynamicAccess<Dynamic> because
		// upstream SDK/plugin options are open passthrough data; this fixture
		// writes only one typed boolean key and AiSdkLanguageLoader narrows it
		// through ProviderOptionAccess before use.
		final options = new DynamicAccess<Dynamic>();
		options.set("useCompletionUrls", true);
		return options;
	}

	static function provider(id:String):ProviderInfo {
		return {
			id: ProviderID.make(id),
			name: id,
			source: "fixture",
			env: [],
			options: emptyOptions(),
			models: new Map<String, ProviderModel>(),
		};
	}

	static function model(providerID:String, modelID:String, npm:String, ?options:ProviderOptions):ProviderModel {
		return modelWithApiURL(providerID, modelID, npm, "https://llm.example.test/v1", options);
	}

	static function requireProvider(provider:Null<ProviderInfo>, label:String):ProviderInfo {
		if (provider == null)
			throw '${label}: expected provider';
		return provider;
	}

	static function modelWithApiURL(providerID:String, modelID:String, npm:String, apiURL:String, ?options:ProviderOptions):ProviderModel {
		return {
			id: ModelID.make(modelID),
			providerID: ProviderID.make(providerID),
			name: modelID,
			capabilities: capabilities(),
			api: {id: modelID, url: apiURL, npm: npm},
			cost: cost(),
			limit: limit(),
			status: "active",
			options: options == null ? emptyOptions() : options,
			headers: emptyHeaders(),
			release_date: "",
			variants: new DynamicAccess<ProviderOptions>(),
		};
	}

	static function fixtureSdk():AiSdkBundledProvider {
		return {
			languageModel: id -> fixtureLanguage("languageModel", id),
			chat: id -> fixtureLanguage("chat", id),
			responses: id -> fixtureLanguage("responses", id),
		};
	}

	static function languageModelOnlySdk():AiSdkBundledProvider {
		return {
			languageModel: id -> fixtureLanguage("languageModel", id),
		};
	}

	static function chatOnlySdk():AiSdkBundledProvider {
		return {
			languageModel: id -> fixtureLanguage("languageModel", id),
			chat: id -> fixtureLanguage("chat", id),
		};
	}

	static function responsesOnlySdk():AiSdkBundledProvider {
		return {
			languageModel: id -> fixtureLanguage("languageModel", id),
			responses: id -> fixtureLanguage("responses", id),
		};
	}

	static function fixtureLanguage(method:String, modelID:String):AiLanguageModel {
		return {
			specificationVersion: AiLanguageModelSpecificationVersion.V3,
			provider: "fixture",
			modelId: '${method}:${modelID}',
			supportedUrls: emptySupportedUrls(),
			doGenerate: (_:AiLanguageModelCallOptions) -> unusedGenerate(),
			doStream: (_:AiLanguageModelCallOptions) -> unusedStream(),
		};
	}

	static function emptySupportedUrls():AiSupportedUrls {
		return new DynamicAccess<Array<opencodehx.externs.ai.AiSdk.AiRegExp>>();
	}

	static function unusedGenerate():Promise<AiLanguageModelGenerateResult> {
		throw "fixture language model should not generate";
	}

	static function unusedStream():Promise<AiLanguageModelStreamResult> {
		throw "fixture language model should not stream";
	}

	static function emptyOptions():ProviderOptions {
		// Fixture boundary: ProviderOptions is open SDK passthrough data. Empty
		// maps contain no weak values, and production reads go through typed
		// ProviderOptionAccess helpers.
		return new DynamicAccess<Dynamic>();
	}

	static function emptyHeaders():ProviderHeaders {
		return new DynamicAccess<String>();
	}

	static function capabilities():ProviderCapabilities {
		return {
			toolcall: true,
			attachment: false,
			reasoning: true,
			temperature: true,
			interleaved: false,
			input: {
				text: true,
				image: false,
				audio: false,
				video: false,
				pdf: false
			},
			output: {
				text: true,
				image: false,
				audio: false,
				video: false,
				pdf: false
			},
		};
	}

	static function cost():ProviderCost {
		return {
			input: 0,
			output: 0,
			cache: {read: 0, write: 0},
		};
	}

	static function limit():ProviderLimit {
		return {
			context: 128000,
			output: 4096,
		};
	}

	static function hasEvent(result:AiSdkStreamResult, predicate:AiSdkStreamEvent->Bool):Bool {
		for (event in result.events) {
			if (predicate(event))
				return true;
		}
		return false;
	}

	static function count(result:AiSdkStreamResult, predicate:AiSdkStreamEvent->Bool):Int {
		var total = 0;
		for (event in result.events) {
			if (predicate(event))
				total++;
		}
		return total;
	}

	static function expectFailure(run:() -> Void, label:String, contains:String):Void {
		try {
			run();
		} catch (error:Exception) {
			if (error.message.indexOf(contains) != -1)
				return;
			throw '${label}: expected failure containing ${contains}, got ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
