package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import js.html.AbortSignal;
import js.lib.Promise;
import opencodehx.externs.ai.AiSdk.AiJsonObject;
import opencodehx.externs.ai.AiSdk.AiJsonValue;
import opencodehx.externs.ai.AiSdk.AiLanguageModelCallOptions;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContent;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContentType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModelGenerateResult;
import opencodehx.externs.ai.AiSdk.AiLanguageModelOutputTokens;
import opencodehx.externs.ai.AiSdk.AiLanguageModelRequestInfo;
import opencodehx.externs.ai.AiSdk.AiLanguageModelSourceType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelSpecificationVersion;
import opencodehx.externs.ai.AiSdk.AiLanguageModelStreamResponseInfo;
import opencodehx.externs.ai.AiSdk.AiLanguageModelStreamResult;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsageTokens;
import opencodehx.externs.ai.AiSdk.AiLanguageModelV3Usage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelWarning;
import opencodehx.externs.ai.AiSdk.AiLanguageModelWarningType;
import opencodehx.externs.ai.AiSdk.AiProviderMetadata;
import opencodehx.externs.ai.AiSdk.AiProviderReadableStream;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.externs.ai.AiSdk.AiRegExp;
import opencodehx.externs.ai.AiSdk.AiNonNullJsonValue;
import opencodehx.externs.ai.AiSdk.AiSupportedUrls;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatFetchFunction;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider.CopilotOpenAICompatibleModelConfig;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotMappedResponsesUsage;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesGeneratedContent;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesGeneratedContentType;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesProviderMetadata;
import opencodehx.provider.copilot.CopilotResponsesHttpClient.CopilotResponsesGenerateResult;
import opencodehx.provider.copilot.CopilotResponsesHttpClient.CopilotResponsesStreamResult;
import opencodehx.provider.copilot.CopilotResponsesRequest.CopilotResponsesRequestOptions;

using StringTools;

typedef CopilotResponsesLanguageModelConfig = {
	final modelConfig:CopilotOpenAICompatibleModelConfig;
	@:optional final fetcher:CopilotChatFetchFunction;
	@:optional final generateId:Void->String;
}

/**
 * Haxe-owned port of upstream's OpenAI Responses `LanguageModelV3` surface.
 *
 * This model is intentionally separate from the chat-completions adapter:
 * Responses uses a different request body (`input`), different system-message
 * rules for reasoning models, different finish-reason semantics, and distinct
 * stream events. Keeping it separate avoids a tempting but wrong chat fallback
 * for `gpt-5` non-mini Copilot models.
 */
class CopilotResponsesLanguageModel {
	public final specificationVersion:AiLanguageModelSpecificationVersion = AiLanguageModelSpecificationVersion.V3;
	public final modelId:String;
	public final provider:String;
	public final supportedUrls:AiSupportedUrls;

	final modelConfig:CopilotOpenAICompatibleModelConfig;
	final fetcher:Null<CopilotChatFetchFunction>;
	final generateId:Null<Void->String>;

	public function new(config:CopilotResponsesLanguageModelConfig) {
		modelConfig = config.modelConfig;
		modelId = modelConfig.modelId;
		provider = modelConfig.provider;
		supportedUrls = responsesSupportedUrls();
		fetcher = config.fetcher;
		generateId = config.generateId;
	}

	public function doGenerate(options:AiLanguageModelCallOptions):Promise<AiLanguageModelGenerateResult> {
		return CopilotResponsesHttpClient.generate({
			modelConfig: modelConfig,
			request: requestFromOptions(options),
			headers: headersFromOptions(options.headers),
			fetcher: fetcher,
			generateId: generateId,
			abortSignal: options.abortSignal,
		}).then(generateResult);
	}

	public function doStream(options:AiLanguageModelCallOptions):Promise<AiLanguageModelStreamResult> {
		return CopilotResponsesHttpClient.stream({
			modelConfig: modelConfig,
			request: requestFromOptions(options),
			headers: headersFromOptions(options.headers),
			fetcher: fetcher,
			includeRawChunks: options.includeRawChunks == true,
			abortSignal: options.abortSignal,
		}).then(streamResult);
	}

	function requestFromOptions(options:AiLanguageModelCallOptions):CopilotResponsesRequestOptions {
		final request = CopilotResponsesRequest.options(modelId, CopilotAiSdkPrompt.fromSdk(options.prompt));
		request.maxOutputTokens = numberOrAbsent(options.maxOutputTokens);
		request.temperature = numberOrAbsent(options.temperature);
		request.topP = numberOrAbsent(options.topP);
		request.topK = numberOrAbsent(options.topK);
		request.stopSequences = stringArrayOrAbsent(options.stopSequences);
		request.seed = numberOrAbsent(options.seed);
		request.frequencyPenalty = numberOrAbsent(options.frequencyPenalty);
		request.presencePenalty = numberOrAbsent(options.presencePenalty);
		request.responseFormat = CopilotResponsesRequest.responseFormat(options.responseFormat);
		request.providerOptions = CopilotResponsesRequest.providerOptions(options.providerOptions, providerOptionsName());
		request.tools = CopilotResponsesRequest.tools(options.tools);
		request.toolChoice = CopilotResponsesRequest.toolChoice(options.toolChoice);
		return request;
	}

	static function responsesSupportedUrls():AiSupportedUrls {
		final out = new DynamicAccess<Array<AiRegExp>>();
		out.set("image/*", [new AiRegExp("^https?:\\/\\/.*$")]);
		out.set("application/pdf", [new AiRegExp("^https?:\\/\\/.*$")]);
		return out;
	}

	function providerOptionsName():String {
		final parts = provider.split(".");
		return parts.length == 0 ? "" : parts[0].trim();
	}

	static function generateResult(source:CopilotResponsesGenerateResult):AiLanguageModelGenerateResult {
		return {
			content: content(source.content),
			finishReason: finishReason(source.finishReason),
			usage: usage(source.usage),
			providerMetadata: responseMetadata(source.response.id.orNull(), null),
			request: requestInfo(source.request.body),
			response: {
				id: source.response.id,
				modelId: source.response.modelId,
				timestamp: source.response.timestamp,
				headers: source.response.headers,
				body: Unknown.fromBoundary(source.response.rawBody),
			},
			warnings: warnings(source.warnings),
		};
	}

	static function streamResult(source:CopilotResponsesStreamResult):AiLanguageModelStreamResult {
		return {
			stream: eventStream(source.events),
			request: requestInfo(source.request.body),
			response: streamResponseInfo(source.response.headers),
		};
	}

	static function content(source:Array<CopilotResponsesGeneratedContent>):Array<AiLanguageModelContent> {
		final out:Array<AiLanguageModelContent> = [];
		for (item in source) {
			switch item.type {
				case CopilotResponsesGeneratedContentType.Text:
					out.push({
						type: AiLanguageModelContentType.Text,
						text: requireUndefinableString(item.text, "responses text content"),
						providerMetadata: metadata(item.providerMetadata),
					});
				case CopilotResponsesGeneratedContentType.Reasoning:
					out.push({
						type: AiLanguageModelContentType.Reasoning,
						text: requireUndefinableString(item.text, "responses reasoning content"),
						providerMetadata: metadata(item.providerMetadata),
					});
				case CopilotResponsesGeneratedContentType.ToolCall:
					out.push(toolCallContent(item));
				case CopilotResponsesGeneratedContentType.ToolResult:
					out.push({
						type: AiLanguageModelContentType.ToolResult,
						toolCallId: requireUndefinableString(item.toolCallId, "responses tool result id"),
						toolName: requireUndefinableString(item.toolName, "responses tool result name"),
						result: requireUndefinableJsonValue(item.result, "responses tool result"),
					});
				case CopilotResponsesGeneratedContentType.Source:
					out.push(sourceContent(item));
			}
		}
		return out;
	}

	static function toolCallContent(item:CopilotResponsesGeneratedContent):AiLanguageModelContent {
		final providerExecuted = item.providerExecuted == null ? false : item.providerExecuted.orNull() == true;
		return {
			type: AiLanguageModelContentType.ToolCall,
			toolCallId: requireUndefinableString(item.toolCallId, "responses tool call id"),
			toolName: requireUndefinableString(item.toolName, "responses tool name"),
			input: requireUndefinableString(item.input, "responses tool input"),
			providerExecuted: providerExecuted,
			providerMetadata: metadata(item.providerMetadata),
		};
	}

	static function sourceContent(item:CopilotResponsesGeneratedContent):AiLanguageModelContent {
		final id = requireUndefinableString(item.id, "responses source id");
		final kind = sourceType(requireUndefinableString(item.sourceType, "responses source type"));
		return switch kind {
			case AiLanguageModelSourceType.Url:
				{
					type: AiLanguageModelContentType.Source,
					id: id,
					sourceType: AiLanguageModelSourceType.Url,
					url: requireUndefinableString(item.url, "responses source url"),
					title: requireUndefinableString(item.title, "responses source title"),
				};
			case AiLanguageModelSourceType.Document:
				{
					type: AiLanguageModelContentType.Source,
					id: id,
					sourceType: AiLanguageModelSourceType.Document,
					mediaType: "text/plain",
					title: requireUndefinableString(item.title, "responses source title"),
					filename: requireUndefinableString(item.filename, "responses source filename"),
				};
		}
	}

	static function eventStream(events:Array<AiProviderStreamPart>):AiProviderReadableStream {
		return new WebReadableStream<AiProviderStreamPart>({
			start: controller -> enqueueEvents(controller, events),
		});
	}

	static function enqueueEvents(controller:WebReadableStreamDefaultController<AiProviderStreamPart>, events:Array<AiProviderStreamPart>):Void {
		for (event in events)
			controller.enqueue(event);
		controller.close();
	}

	static function usage(source:CopilotMappedResponsesUsage):AiLanguageModelV3Usage {
		final raw = source.raw.orNull();
		return {
			inputTokens: inputTokens(source.inputTokens),
			outputTokens: outputTokens(source.outputTokens),
			raw: raw == null ? Undefinable.absent() : AiJsonObject.fromBoundary(raw),
		};
	}

	static function inputTokens(source:opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedInputTokens):AiLanguageModelUsageTokens {
		return {
			total: source.total,
			noCache: source.noCache,
			cacheRead: source.cacheRead,
			cacheWrite: source.cacheWrite,
		};
	}

	static function outputTokens(source:opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedOutputTokens):AiLanguageModelOutputTokens {
		return {
			total: source.total,
			text: source.text,
			reasoning: source.reasoning,
		};
	}

	static function finishReason(source:opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason):AiLanguageModelFinishReason {
		return {
			unified: source.unified,
			raw: source.raw,
		};
	}

	static function warnings(source:Array<CopilotChatWarning>):Array<AiLanguageModelWarning> {
		final out:Array<AiLanguageModelWarning> = [];
		for (warning in source) {
			out.push({
				type: AiLanguageModelWarningType.Unsupported,
				feature: warning.feature,
				details: warning.details == null ? Undefinable.absent() : warning.details,
			});
		}
		return out;
	}

	static function metadata(source:Null<Undefinable<CopilotResponsesProviderMetadata>>):Undefinable<AiProviderMetadata> {
		final present = source == null ? null : source.orNull();
		if (present == null)
			return Undefinable.absent();
		final out = new DynamicAccess<AiJsonObject>();
		out.set("openai", AiJsonObject.fromBoundary(present.openai));
		final metadata:AiProviderMetadata = out;
		return metadata;
	}

	static function responseMetadata(responseId:Null<String>, serviceTier:Null<String>):Undefinable<AiProviderMetadata> {
		if (responseId == null && serviceTier == null)
			return Undefinable.absent();
		final openai = new DynamicAccess<AiJsonValue>();
		if (responseId != null)
			openai.set("responseId", AiJsonValue.fromBoundary(responseId));
		if (serviceTier != null)
			openai.set("serviceTier", AiJsonValue.fromBoundary(serviceTier));
		final out = new DynamicAccess<AiJsonObject>();
		out.set("openai", AiJsonObject.fromBoundary(openai));
		final metadata:AiProviderMetadata = out;
		return metadata;
	}

	static function requestInfo(body:String):AiLanguageModelRequestInfo {
		return {body: Unknown.fromBoundary(body)};
	}

	static function streamResponseInfo(headers:DynamicAccess<String>):AiLanguageModelStreamResponseInfo {
		return {headers: headers};
	}

	static function headersFromOptions(source:Null<DynamicAccess<Undefinable<String>>>):Null<DynamicAccess<String>> {
		if (source == null)
			return null;
		final out = new DynamicAccess<String>();
		for (key in source.keys()) {
			final value = source.get(key);
			if (value == null)
				continue;
			final present = value.orNull();
			if (present != null)
				out.set(key, present);
		}
		return isEmpty(out) ? null : out;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}

	static function stringArrayOrAbsent(value:Null<Array<String>>):Undefinable<Array<String>> {
		return value == null ? Undefinable.absent() : value;
	}

	static function optionalString(value:Null<Undefinable<String>>):Null<String> {
		final present = value == null ? null : value.orNull();
		return present;
	}

	static function sourceType(value:String):AiLanguageModelSourceType {
		return switch value {
			case "url":
				AiLanguageModelSourceType.Url;
			case "document":
				AiLanguageModelSourceType.Document;
			case other:
				throw 'Unsupported Responses source type: ${other}';
		}
	}

	static function requireUndefinableString(value:Null<Undefinable<String>>, label:String):String {
		final present = value == null ? null : value.orNull();
		if (present == null)
			throw 'Missing Copilot ${label}';
		return present;
	}

	static function requireUndefinableJsonValue(value:Null<Undefinable<AiNonNullJsonValue>>, label:String):AiNonNullJsonValue {
		final present = value == null ? null : value.orNull();
		if (present == null)
			throw 'Missing Copilot ${label}';
		return present;
	}

	static function isEmpty(value:DynamicAccess<String>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}
}
