package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import js.lib.Promise;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.ConfigProviderConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelConfig;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.provider.AiSdkLanguageLoader;
import opencodehx.provider.AiSdkProvider;
import opencodehx.provider.AiSdkProvider.AiSdkMockModel;
import opencodehx.provider.AiSdkProvider.AiSdkStreamEvent;
import opencodehx.provider.AiSdkProvider.AiSdkStreamResult;
import opencodehx.provider.ProviderRegistry;
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
		final provider = registry.getProvider(ProviderID.make("sdk-compatible"));
		final model = registry.getModel(ProviderID.make("sdk-compatible"), ModelID.make("local-alias"));
		final resolved = registry.resolveLanguage(model);
		eq(resolved.sdkModelID, "remote-model", "ai sdk factory model id");
		eq(resolved.language.modelId, "remote-model", "ai sdk language model id");
		eq(resolved.language.provider, "sdk-compatible.chat", "ai sdk language provider");
		eq(AiSdkLanguageLoader.factoryOptions(provider, model).baseURL, "https://llm.example.test/v1", "ai sdk factory base url");
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

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
