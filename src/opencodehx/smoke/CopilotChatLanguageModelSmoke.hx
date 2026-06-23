package opencodehx.smoke;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import js.html.Response;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.ConfigProviderConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelConfig;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModelCallOptions;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContent;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContentType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiLanguageModelResponseFormatType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelSpecificationVersion;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolChoiceType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolType;
import opencodehx.externs.ai.AiSdk.AiOpenAICompatibleProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderOptions;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.provider.copilot.CopilotAiSdkLanguageModel;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchFunction;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchInit;
import opencodehx.provider.copilot.CopilotChatLanguageModel;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatRequest;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEventType;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderIDs;
import opencodehx.provider.ProviderTypes.ProviderOptions;

typedef CopilotLanguageModelCapturedFetch = {
	final url:String;
	final init:CopilotChatFetchInit;
}

class CopilotChatLanguageModelSmoke {
	@:async
	public static function run():Promise<Void> {
		@:await generateUsesModelIdentity();
		@:await sdkAdapterGeneratesFromLanguageModelV3Options();
		@:await streamUsesClassOptions();
		supportedUrlsAreCloned();
		registryResolvesCopilotChatModel();
		registryGetLanguageReturnsSdkFacade();
		return null;
	}

	@:async
	static function generateUsesModelIdentity():Promise<Void> {
		final calls:Array<CopilotLanguageModelCapturedFetch> = [];
		final model = chatModel(calls, [
			jsonResponse(generateResponseJson(), 200, "OK", headerMap("x-request-id", "language-generate"))
		], true, false);

		final request = CopilotChatRequest.options("wrong-request-model", [CopilotPromptMessage.User([CopilotPromptPart.Text("Hello")])]);
		request.responseFormat = CopilotChatRequest.jsonResponseFormat(schema(), "weather_response");
		request.supportsStructuredOutputs = false;
		final generated = @:await model.doGenerate(request, headerMap("x-call", "present"));

		eq(model.specificationVersion, "v3", "language model spec version");
		eq(model.modelId, "gemini-2.0-flash-001", "language model id");
		eq(model.provider, "github-copilot.chat", "language provider");
		eq(model.providerOptionsName, "github-copilot", "provider options name");
		eq(model.supportsStructuredOutputs, true, "structured output flag");
		eq(calls[0].url, "https://api.githubcopilot.com/chat/completions", "language generate url");
		eq(calls[0].init.headers.get("x-call"), "present", "language call headers");
		contains(calls[0].init.body, '"model":"gemini-2.0-flash-001"', "class model id wins");
		notContains(calls[0].init.body, "wrong-request-model", "request model id omitted");
		contains(calls[0].init.body, '"type":"json_schema"', "class structured output support");
		eq(generated.warnings.length, 0, "structured generate warnings");
		eq(generated.content[0].text.orNull(), "Hello from language model", "language generated text");
		eq(generated.content[1].toolCallId.orNull(), "generated-by-language-model", "language generated tool id");
		return null;
	}

	@:async
	static function sdkAdapterGeneratesFromLanguageModelV3Options():Promise<Void> {
		final calls:Array<CopilotLanguageModelCapturedFetch> = [];
		final adapter = new CopilotAiSdkLanguageModel({
			chat: chatModel(calls, [
				jsonResponse(generateResponseJson(), 200, "OK", headerMap("x-request-id", "sdk-generate"))
			], true, false),
		});

		final generated = @:await adapter.doGenerate(sdkGenerateOptions());

		eq(calls[0].init.headers.get("x-sdk-call"), "present", "sdk call header forwarded");
		eq(calls[0].init.headers.exists("x-sdk-absent"), false, "undefined sdk header omitted");
		contains(calls[0].init.body, '"messages":[{"role":"system","content":"You are terse"', "sdk system message");
		contains(calls[0].init.body, '"max_tokens":12', "sdk max output tokens");
		contains(calls[0].init.body, '"user":"sdk-user"', "sdk copilot provider option");
		contains(calls[0].init.body, '"reasoning_effort":"high"', "sdk reasoning effort");
		contains(calls[0].init.body, '"verbosity":"low"', "sdk provider-name option override");
		contains(calls[0].init.body, '"thinking_budget":128', "sdk thinking budget");
		contains(calls[0].init.body, '"tool_choice":{"type":"function","function":{"name":"get_weather"}}', "sdk named tool choice");
		eq(generated.content[0].type, AiLanguageModelContentType.Text, "sdk generated text part type");
		eq(generatedText(generated.content[0], "sdk generated text"), "Hello from language model", "sdk generated text");
		eq(generated.content[1].type, AiLanguageModelContentType.ToolCall, "sdk generated tool part type");
		eq(generatedToolCallId(generated.content[1], "sdk generated tool id"), "generated-by-language-model", "sdk generated tool id");
		eq(generated.finishReason.unified, AiFinishReason.ToolCalls, "sdk finish reason");
		eq(generated.usage.inputTokens.total.orNull(), 5, "sdk usage input tokens");
		return null;
	}

	@:async
	static function streamUsesClassOptions():Promise<Void> {
		final calls:Array<CopilotLanguageModelCapturedFetch> = [];
		final model = chatModel(calls, [
			streamResponse([
				'data: {"id":"chatcmpl-stream","created":1677652288,"model":"gemini-2.0-flash-001","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}\n\n',
				'data: {"choices":[{"delta":{"content":"!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}\n\n',
				"data: [DONE]\n\n",
			])
		], false, true);

		final request = CopilotChatRequest.options("wrong-stream-model", [CopilotPromptMessage.User([CopilotPromptPart.Text("Stream")])]);
		request.topK = 9;
		final streamed = @:await model.doStream(request, null, true);

		contains(calls[0].init.body, '"model":"gemini-2.0-flash-001"', "stream class model id wins");
		contains(calls[0].init.body, '"stream":true', "stream body flag");
		contains(calls[0].init.body, '"stream_options":{"include_usage":true}', "class include usage");
		eq(streamed.events[0].type, CopilotChatStreamEventType.StreamStart, "language stream start");
		eq(streamed.events[0].warnings.orNull()[0].feature, "topK", "language stream warning");
		eq(streamed.events[1].type, CopilotChatStreamEventType.Raw, "language raw chunk");
		eq(streamed.events[4].delta.orNull(), "Hi", "language stream first text");
		return null;
	}

	static function supportedUrlsAreCloned():Void {
		final urls = new DynamicAccess<Array<String>>();
		urls.set("image", ["https://images.example/{id}"]);
		final model = new CopilotChatLanguageModel({
			modelConfig: CopilotOpenAICompatibleProvider.chat(CopilotOpenAICompatibleProvider.settings(), "gpt-4o"),
			supportedUrls: urls,
		});

		urls.get("image").push("mutated-before-read");
		final first = model.supportedUrls;
		first.get("image").push("mutated-after-read");
		final second = model.supportedUrls;
		eq(second.get("image").join(","), "https://images.example/{id}", "supported urls clone");
	}

	static function registryResolvesCopilotChatModel():Void {
		final registry = new ProviderRegistry({config: copilotConfig(), env: {}, auth: {}});
		final model = registry.getModel(ProviderIDs.known("github-copilot"), ModelID.make("copilot-chat-alias"));
		final resolved = registry.resolveCopilotChat(model);

		eq(resolved.sdkModelID, "gemini-2.0-flash-001", "registry copilot sdk model id");
		eq(resolved.language.modelId, "gemini-2.0-flash-001", "registry copilot language model id");
		eq(resolved.language.provider, "github-copilot.chat", "registry copilot provider");
		eq(resolved.language.supportsStructuredOutputs, true, "registry copilot structured output option");
		eq(CopilotOpenAICompatibleProvider.url(resolved.modelConfig, "/chat/completions"), "https://api.githubcopilot.com/chat/completions",
			"registry copilot url");
		eq(resolved.modelConfig.headers.get("authorization"), "Bearer github-token", "registry copilot auth header");
		eq(resolved.modelConfig.headers.get("x-copilot-fixture"), "present", "registry copilot model header");
	}

	static function registryGetLanguageReturnsSdkFacade():Void {
		final registry = new ProviderRegistry({config: copilotConfig(), env: {}, auth: {}});
		final model = registry.getModel(ProviderIDs.known("github-copilot"), ModelID.make("copilot-chat-alias"));
		final language = registry.getLanguage(model);

		eq(language.specificationVersion, AiLanguageModelSpecificationVersion.V3, "registry sdk spec version");
		eq(language.modelId, "gemini-2.0-flash-001", "registry sdk language model id");
		eq(language.provider, "github-copilot.chat", "registry sdk provider");
	}

	static function chatModel(calls:Array<CopilotLanguageModelCapturedFetch>, responses:Array<Response>, supportsStructuredOutputs:Bool,
			includeUsage:Bool):CopilotChatLanguageModel {
		return new CopilotChatLanguageModel({
			modelConfig: CopilotOpenAICompatibleProvider.chat(CopilotOpenAICompatibleProvider.settings("github-token", "https://api.githubcopilot.com",
				"github-copilot"), "gemini-2.0-flash-001"),
			fetcher: fakeFetcher(calls, responses),
			supportsStructuredOutputs: supportsStructuredOutputs,
			includeUsage: includeUsage,
			generateId: () -> "generated-by-language-model",
		});
	}

	static function copilotConfig():ConfigInfo {
		final info = ConfigInfo.empty("fixture-user");
		final providers = new DynamicAccess<ConfigProviderConfig>();
		final models = new DynamicAccess<ConfigProviderModelConfig>();
		models.set("copilot-chat-alias", {
			id: "gemini-2.0-flash-001",
			name: "Copilot Chat Alias",
			provider: {
				npm: "@ai-sdk/github-copilot",
				api: "https://api.githubcopilot.com",
			},
			tool_call: true,
			limit: {context: 128000, output: 4096},
			headers: headerMap("x-copilot-fixture", "present"),
		});
		providers.set("github-copilot", {
			name: "GitHub Copilot",
			env: [],
			options: copilotOptions(),
			models: models,
		});
		info.provider = providers;
		return info;
	}

	static function copilotOptions():ProviderOptions {
		// ProviderOptions is the intentional provider-SDK passthrough boundary.
		// This fixture keeps values to the Copilot loader's typed stable subset.
		final options = new DynamicAccess<Dynamic>();
		options.set("apiKey", "github-token");
		options.set("supportsStructuredOutputs", true);
		return options;
	}

	static function sdkGenerateOptions():AiLanguageModelCallOptions {
		return {
			prompt: [
				{role: AiLanguageModelPromptRole.System, content: "You are terse"},
				{
					role: AiLanguageModelPromptRole.User,
					content: [{type: AiLanguageModelPromptPartType.Text, text: "Hello"},],
				},
			],
			maxOutputTokens: 12,
			responseFormat: {
				type: AiLanguageModelResponseFormatType.Json,
				schema: schema(),
				name: "weather_response",
			},
			tools: [
				{
					type: AiLanguageModelToolType.Function,
					name: "get_weather",
					description: "Get the weather",
					inputSchema: schema(),
				},
			],
			toolChoice: {type: AiLanguageModelToolChoiceType.Tool, toolName: "get_weather"},
			headers: sdkHeaders(),
			providerOptions: sdkProviderOptions(),
		};
	}

	static function sdkHeaders():DynamicAccess<Undefinable<String>> {
		final headers = new DynamicAccess<Undefinable<String>>();
		headers.set("x-sdk-call", "present");
		headers.set("x-sdk-absent", Undefinable.absent());
		return headers;
	}

	static function sdkProviderOptions():AiProviderOptions {
		final options = new DynamicAccess<AiOpenAICompatibleProviderOptions>();
		options.set("copilot", {
			user: "sdk-user",
			reasoningEffort: "high",
		});
		options.set("github-copilot", {
			textVerbosity: "low",
			thinkingBudgetSnake: 128,
		});
		return options;
	}

	static function fakeFetcher(calls:Array<CopilotLanguageModelCapturedFetch>, responses:Array<Response>):CopilotChatFetchFunction {
		return function(url:String, init:CopilotChatFetchInit):Promise<Response> {
			calls.push({url: url, init: init});
			final response = responses.shift();
			if (response == null)
				throw "missing fake Copilot language-model response";
			final present:Response = response;
			return Promise.resolve(present);
		}
	}

	static function jsonResponse(body:String, status:Int, statusText:String, headers:DynamicAccess<String>):Response {
		return new Response(body, {
			status: status,
			statusText: statusText,
			headers: headers,
		});
	}

	static function streamResponse(chunks:Array<String>):Response {
		final stream = new WebReadableStream<Uint8Array>({
			start: controller -> enqueueChunks(controller, chunks),
		});
		return new Response(stream, {
			status: 200,
			headers: headerMap("content-type", "text/event-stream"),
		});
	}

	static function enqueueChunks(controller:WebReadableStreamDefaultController<Uint8Array>, chunks:Array<String>):Void {
		final encoder = new WebTextEncoder();
		for (chunk in chunks)
			controller.enqueue(encoder.encode(chunk));
		controller.close();
	}

	static function generateResponseJson():String {
		return
			'{"id":"chatcmpl-language","created":1677652288,"model":"gemini-2.0-flash-001","choices":[{"message":{"role":"assistant","content":"Hello from language model","tool_calls":[{"function":{"name":"read_file","arguments":"{\\"path\\":\\"README.md\\"}"}}]},"finish_reason":"tool_calls"}],"usage":{"prompt_tokens":5,"completion_tokens":7,"total_tokens":12}}';
	}

	static function schema():Unknown {
		// AI SDK JSON Schema remains open boundary data; the language model only
		// decides whether it should be emitted as json_schema or json_object.
		return Unknown.fromBoundary({
			type: "object",
			properties: {
				location: {type: "string"},
			},
			required: ["location"],
		});
	}

	static function headerMap(name:String, value:String):DynamicAccess<String> {
		final headers = new DynamicAccess<String>();
		headers.set(name, value);
		return headers;
	}

	static function generatedText(part:AiLanguageModelContent, label:String):String {
		if (part.type != AiLanguageModelContentType.Text)
			throw '$label: expected text part, got ${part.type}';
		if (part.text == null)
			throw '$label: expected text value';
		return part.text;
	}

	static function generatedToolCallId(part:AiLanguageModelContent, label:String):String {
		if (part.type != AiLanguageModelContentType.ToolCall)
			throw '$label: expected tool-call part, got ${part.type}';
		if (part.toolCallId == null)
			throw '$label: expected tool-call id';
		return part.toolCallId;
	}

	static function contains(value:String, expected:String, label:String):Void {
		if (value.indexOf(expected) < 0)
			throw '$label: expected ${value} to contain ${expected}';
	}

	static function notContains(value:String, expected:String, label:String):Void {
		if (value.indexOf(expected) >= 0)
			throw '$label: expected ${value} not to contain ${expected}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
