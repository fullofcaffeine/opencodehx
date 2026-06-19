package opencodehx.smoke;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import js.html.Response;
import js.lib.Promise;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.ConfigProviderConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelConfig;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModelCallOptions;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContentType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiLanguageModelResponseFormatType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolChoiceType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolType;
import opencodehx.externs.ai.AiSdk.AiOpenAICompatibleProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.externs.ai.AiSdk.AiProviderOptions;
import opencodehx.provider.CopilotLanguageLoader;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchFunction;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchInit;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider;
import opencodehx.provider.copilot.CopilotResponsesLanguageModel;
import opencodehx.provider.copilot.CopilotResponsesStream;

typedef CopilotResponsesCapturedFetch = {
	final url:String;
	final init:CopilotChatFetchInit;
}

class CopilotResponsesLanguageModelSmoke {
	@:async
	public static function run():Promise<Void> {
		@:await generateUsesResponsesPayload();
		@:await streamUsesResponsesEndpoint();
		streamMapperCoversCoreEvents();
		registryRoutesGpt5ToResponses();
		return null;
	}

	@:async
	static function generateUsesResponsesPayload():Promise<Void> {
		final calls:Array<CopilotResponsesCapturedFetch> = [];
		final model = responsesModel(calls, [
			jsonResponse(generateResponseJson(), 200, "OK", headerMap("x-request-id", "responses-generate"))
		]);

		final generated = @:await model.doGenerate(generateOptions());

		eq(calls[0].url, "https://api.githubcopilot.com/responses", "responses generate url");
		eq(calls[0].init.headers.get("x-sdk-call"), "present", "responses sdk header");
		contains(calls[0].init.body, '"model":"gpt-5.2"', "responses model id");
		contains(calls[0].init.body, '"role":"developer","content":"You are exact"', "gpt-5 system becomes developer");
		contains(calls[0].init.body, '"reasoning":{"effort":"high","summary":"auto"}', "reasoning options");
		contains(calls[0].init.body, '"text":{"format":{"type":"json_schema"', "json schema response format");
		contains(calls[0].init.body, '"tools":[{"type":"function","name":"get_weather"', "function tool");
		contains(calls[0].init.body, '"tool_choice":"required"', "required tool choice");
		notContains(calls[0].init.body, '"temperature"', "reasoning model strips temperature");
		notContains(calls[0].init.body, '"top_p"', "reasoning model strips topP");
		eq(generated.warnings.length, 2, "responses unsupported warning count");
		eq(generated.content[0].type, AiLanguageModelContentType.Reasoning, "responses reasoning content");
		eq(generated.content[1].type, AiLanguageModelContentType.Text, "responses text content");
		eq(generated.content[2].type, AiLanguageModelContentType.Source, "responses source content");
		eq(generated.content[3].type, AiLanguageModelContentType.ToolCall, "responses tool content");
		eq(generated.finishReason.unified, AiFinishReason.ToolCalls, "responses finish reason");
		eq(generated.usage.inputTokens.total.orNull(), 10, "responses input tokens");
		eq(generated.usage.inputTokens.noCache.orNull(), 8, "responses no-cache tokens");
		eq(generated.usage.outputTokens.reasoning.orNull(), 3, "responses reasoning tokens");
		return null;
	}

	@:async
	static function streamUsesResponsesEndpoint():Promise<Void> {
		final calls:Array<CopilotResponsesCapturedFetch> = [];
		final model = responsesModel(calls, [
			jsonResponse(streamText(), 200, "OK", headerMap("content-type", "text/event-stream"))
		]);

		final streamed = @:await model.doStream(streamOptions());

		eq(calls[0].url, "https://api.githubcopilot.com/responses", "responses stream url");
		contains(calls[0].init.body, '"stream":true', "responses stream body");
		contains(calls[0].init.body, '"include":["message.output_text.logprobs"]', "responses auto logprobs include");
		if (streamed.request == null || streamed.request.body == null)
			throw "responses stream request body missing";
		contains(Std.string(streamed.request.body), '"stream":true', "responses sdk stream request body");
		return null;
	}

	static function streamMapperCoversCoreEvents():Void {
		final events = CopilotResponsesStream.collectText(streamText(), true, [], Undefinable.absent());
		eq(events[0].type, "stream-start", "responses stream start");
		eq(events[1].type, "raw", "responses raw chunk");
		eq(events[2].type, "response-metadata", "responses metadata chunk");
		eq(events[4].type, "text-start", "responses text start");
		eq(textDelta(events[6], "responses text delta"), "Hello", "responses text delta");
		eq(events[10].type, "finish", "responses finish");
		eq(finishReason(events[10], "responses stream finish reason"), AiFinishReason.Stop, "responses stream finish reason");
	}

	static function registryRoutesGpt5ToResponses():Void {
		eq(CopilotLanguageLoader.shouldUseResponsesApi("gpt-5.2"), true, "gpt-5 responses route");
		eq(CopilotLanguageLoader.shouldUseResponsesApi("gpt-5-mini"), false, "gpt-5-mini chat route");

		final registry = new ProviderRegistry({config: copilotConfig(), env: {}, auth: {}});
		final chatModel = registry.getModel(ProviderID.make("github-copilot"), ModelID.make("copilot-chat-alias"));
		final responsesModel = registry.getModel(ProviderID.make("github-copilot"), ModelID.make("copilot-responses-alias"));
		final chatLanguage = registry.getLanguage(chatModel);
		final responsesLanguage = registry.getLanguage(responsesModel);
		final resolved = registry.resolveCopilotResponses(responsesModel);

		eq(chatLanguage.provider, "github-copilot.chat", "registry chat provider");
		eq(responsesLanguage.provider, "github-copilot.responses", "registry responses provider");
		eq(resolved.sdkModelID, "gpt-5.2", "registry responses sdk model id");
		eq(CopilotOpenAICompatibleProvider.url(resolved.modelConfig, "/responses"), "https://api.githubcopilot.com/responses", "registry responses url");
	}

	static function responsesModel(calls:Array<CopilotResponsesCapturedFetch>, responses:Array<Response>):CopilotResponsesLanguageModel {
		return new CopilotResponsesLanguageModel({
			modelConfig: CopilotOpenAICompatibleProvider.responses(CopilotOpenAICompatibleProvider.settings("github-token", "https://api.githubcopilot.com",
				"github-copilot"), "gpt-5.2"),
			fetcher: fakeFetcher(calls, responses),
			generateId: () -> "responses-source-id",
		});
	}

	static function generateOptions():AiLanguageModelCallOptions {
		return {
			prompt: [
				{role: AiLanguageModelPromptRole.System, content: "You are exact"},
				{
					role: AiLanguageModelPromptRole.User,
					content: [{type: AiLanguageModelPromptPartType.Text, text: "Hello"},],
				},
			],
			maxOutputTokens: 33,
			temperature: 0.2,
			topP: 0.9,
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
			toolChoice: {type: AiLanguageModelToolChoiceType.Required},
			headers: sdkHeaders(),
			providerOptions: sdkProviderOptions(false),
		};
	}

	static function streamOptions():AiLanguageModelCallOptions {
		return {
			prompt: [
				{role: AiLanguageModelPromptRole.System, content: "You are exact"},
				{
					role: AiLanguageModelPromptRole.User,
					content: [{type: AiLanguageModelPromptPartType.Text, text: "Hello"},],
				},
			],
			maxOutputTokens: 33,
			temperature: 0.2,
			topP: 0.9,
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
			toolChoice: {type: AiLanguageModelToolChoiceType.Required},
			headers: sdkHeaders(),
			providerOptions: sdkProviderOptions(true),
			includeRawChunks: true,
		};
	}

	static function sdkProviderOptions(enableLogprobs:Bool):AiProviderOptions {
		final options = new DynamicAccess<AiOpenAICompatibleProviderOptions>();
		options.set("copilot", {
			reasoningEffort: "high",
			reasoningSummary: "auto",
			strictJsonSchema: true,
			logprobs: enableLogprobs,
		});
		return options;
	}

	static function sdkHeaders():DynamicAccess<Undefinable<String>> {
		final headers = new DynamicAccess<Undefinable<String>>();
		headers.set("x-sdk-call", "present");
		return headers;
	}

	static function copilotConfig():ConfigInfo {
		final info = ConfigInfo.empty("fixture-user");
		final providers = new DynamicAccess<ConfigProviderConfig>();
		final models = new DynamicAccess<ConfigProviderModelConfig>();
		models.set("copilot-chat-alias", model("gemini-2.0-flash-001", "Copilot Chat Alias"));
		models.set("copilot-responses-alias", model("gpt-5.2", "Copilot Responses Alias"));
		providers.set("github-copilot", {
			name: "GitHub Copilot",
			env: [],
			options: copilotOptions(),
			models: models,
		});
		info.provider = providers;
		return info;
	}

	static function model(id:String, name:String):ConfigProviderModelConfig {
		return {
			id: id,
			name: name,
			provider: {
				npm: "@ai-sdk/github-copilot",
				api: "https://api.githubcopilot.com",
			},
			tool_call: true,
			limit: {context: 128000, output: 4096},
		};
	}

	static function copilotOptions():ProviderOptions {
		// ProviderOptions is the intentional provider-SDK passthrough boundary.
		// This fixture keeps values to the Copilot loader's typed stable subset.
		final options = new DynamicAccess<Dynamic>();
		options.set("apiKey", "github-token");
		return options;
	}

	static function fakeFetcher(calls:Array<CopilotResponsesCapturedFetch>, responses:Array<Response>):CopilotChatFetchFunction {
		return function(url:String, init:CopilotChatFetchInit):Promise<Response> {
			calls.push({url: url, init: init});
			final response = responses.shift();
			if (response == null)
				throw "missing fake Copilot responses response";
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

	static function generateResponseJson():String {
		return
			'{"id":"resp-language","created_at":1677652288,"model":"gpt-5.2","output":[{"type":"reasoning","id":"rs_1","encrypted_content":"cipher","summary":[{"type":"summary_text","text":"thinking"}]},{"type":"message","role":"assistant","id":"msg_1","content":[{"type":"output_text","text":"Hello from responses","annotations":[{"type":"url_citation","start_index":0,"end_index":5,"url":"https://example.com","title":"Example"}]}]},{"type":"function_call","id":"fc_item","call_id":"call_weather","name":"get_weather","arguments":"{\\"location\\":\\"Paris\\"}"}],"service_tier":null,"incomplete_details":null,"usage":{"input_tokens":10,"input_tokens_details":{"cached_tokens":2},"output_tokens":7,"output_tokens_details":{"reasoning_tokens":3}}}';
	}

	static function streamText():String {
		return [
			'data: {"type":"response.created","response":{"id":"resp-stream","created_at":1677652288,"model":"gpt-5.2","service_tier":null}}',
			'data: {"type":"response.output_item.added","output_index":0,"item":{"type":"message","id":"msg_stream"}}',
			'data: {"type":"response.output_text.delta","item_id":"msg_stream","delta":"Hello","logprobs":null}',
			'data: {"type":"response.output_item.done","output_index":0,"item":{"type":"message","id":"msg_stream"}}',
			'data: {"type":"response.completed","response":{"incomplete_details":null,"usage":{"input_tokens":1,"input_tokens_details":null,"output_tokens":1,"output_tokens_details":null},"service_tier":null}}',
			"",
		].join("\n\n");
	}

	static function schema():Unknown {
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

	static function textDelta(event:AiProviderStreamPart, label:String):String {
		if (event.type != "text-delta")
			throw '$label: expected text-delta, got ${event.type}';
		if (event.delta == null)
			throw '$label: expected delta';
		return event.delta;
	}

	static function finishReason(event:AiProviderStreamPart, label:String):AiFinishReason {
		if (event.type != "finish")
			throw '$label: expected finish, got ${event.type}';
		if (event.finishReason == null)
			throw '$label: expected finish reason';
		return event.finishReason.unified;
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
