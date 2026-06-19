package opencodehx.provider.copilot;

import genes.js.Async.await;
import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import js.html.URL;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.ai.AiSdk.AiLanguageModelCallOptions;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContent;
import opencodehx.externs.ai.AiSdk.AiLanguageModelContentType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelFileData;
import opencodehx.externs.ai.AiSdk.AiLanguageModelFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModelGenerateResult;
import opencodehx.externs.ai.AiSdk.AiLanguageModelOutputTokens;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPrompt;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPart;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiLanguageModelResponseFormat;
import opencodehx.externs.ai.AiSdk.AiLanguageModelResponseFormatType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelSpecificationVersion;
import opencodehx.externs.ai.AiSdk.AiLanguageModelStreamResult;
import opencodehx.externs.ai.AiSdk.AiLanguageModelTool;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolChoice;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolChoiceType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolResultOutput;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsageTokens;
import opencodehx.externs.ai.AiSdk.AiLanguageModelV3Usage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelWarning;
import opencodehx.externs.ai.AiSdk.AiLanguageModelWarningType;
import opencodehx.externs.ai.AiSdk.AiJsonObject;
import opencodehx.externs.ai.AiSdk.AiJsonValue;
import opencodehx.externs.ai.AiSdk.AiOpenAICompatibleProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderMetadata;
import opencodehx.externs.ai.AiSdk.AiProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderOptionsMap;
import opencodehx.externs.ai.AiSdk.AiProviderReadableStream;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.externs.ai.AiSdk.AiRegExp;
import opencodehx.externs.ai.AiSdk.AiSupportedUrls;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotGeneratedContent;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotGeneratedContentType;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotContentProviderMetadata;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedOutputTokens;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedResponseUsage;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedStreamUsage;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedInputTokens;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotPredictionMetadata;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatGenerateResult;
import opencodehx.provider.copilot.CopilotChatHttpClient.CopilotChatStreamResult;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotFileData;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotMetadata;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotProviderOptions;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotToolOutput;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotChatRequestOptions;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotCompatibleProviderOptions;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotJsonResponseFormat;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEvent;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEventType;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamProviderMetadata;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatTool;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatToolChoice;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;

using StringTools;

typedef CopilotAiSdkLanguageModelConfig = {
	final chat:CopilotChatLanguageModel;
	@:optional final supportedUrls:AiSupportedUrls;
}

/**
 * Exact AI SDK `LanguageModelV3` facade for the Haxe-owned Copilot chat model.
 *
 * `CopilotChatLanguageModel` deliberately exposes OpenCodeHX-native request and
 * result DTOs for focused helper tests. This adapter is the sole boundary that
 * accepts SDK `LanguageModelV3CallOptions`, converts them into those DTOs, and
 * maps the response back to SDK result/stream shapes. Keeping the translation
 * here prevents production casts while still letting `ProviderRegistry` return
 * a structurally valid `LanguageModelV3`.
 */
class CopilotAiSdkLanguageModel {
	public final specificationVersion:AiLanguageModelSpecificationVersion = AiLanguageModelSpecificationVersion.V3;
	public final modelId:String;
	public final provider:String;
	public final supportedUrls:AiSupportedUrls;

	final chat:CopilotChatLanguageModel;
	final providerOptionsName:String;

	public function new(config:CopilotAiSdkLanguageModelConfig) {
		chat = config.chat;
		modelId = chat.modelId;
		provider = chat.provider;
		providerOptionsName = chat.providerOptionsName;
		supportedUrls = config.supportedUrls == null ? emptySupportedUrls() : config.supportedUrls;
	}

	@:async
	public function doGenerate(options:AiLanguageModelCallOptions):Promise<AiLanguageModelGenerateResult> {
		final request = requestFromOptions(options);
		final generated = @:await chat.doGenerate(request, headersFromOptions(options.headers), options.abortSignal);
		return generateResult(generated);
	}

	@:async
	public function doStream(options:AiLanguageModelCallOptions):Promise<AiLanguageModelStreamResult> {
		final request = requestFromOptions(options);
		final streamed = @:await chat.doStream(request, headersFromOptions(options.headers), options.includeRawChunks == true, options.abortSignal);
		return {
			stream: eventStream(streamed.events),
			request: {body: Unknown.fromBoundary(streamed.request.body)},
			response: {headers: streamed.response.headers},
		};
	}

	function requestFromOptions(options:AiLanguageModelCallOptions):CopilotChatRequestOptions {
		final request = CopilotChatRequest.options(modelId, promptFromSdk(options.prompt));
		request.maxOutputTokens = numberOrAbsent(options.maxOutputTokens);
		request.temperature = numberOrAbsent(options.temperature);
		request.topP = numberOrAbsent(options.topP);
		request.topK = numberOrAbsent(options.topK);
		request.frequencyPenalty = numberOrAbsent(options.frequencyPenalty);
		request.presencePenalty = numberOrAbsent(options.presencePenalty);
		request.stopSequences = stringArrayOrAbsent(options.stopSequences);
		request.seed = numberOrAbsent(options.seed);
		request.responseFormat = responseFormat(options.responseFormat);
		request.providerOptions = compatibleProviderOptions(options.providerOptions, providerOptionsName);
		request.tools = tools(options.tools);
		request.toolChoice = toolChoice(options.toolChoice);
		return request;
	}

	static function promptFromSdk(prompt:AiLanguageModelPrompt):Array<CopilotPromptMessage> {
		final messages:Array<AiLanguageModelPromptMessage> = prompt;
		final out:Array<CopilotPromptMessage> = [];
		for (message in messages) {
			final providerOptions = copilotProviderOptions(message.providerOptions);
			switch message.role {
				case AiLanguageModelPromptRole.System:
					final content = textContent(message.content, "system message content");
					out.push(CopilotPromptMessage.System(content, providerOptions));
				case AiLanguageModelPromptRole.User:
					final content = partContent(message.content, "user message content");
					out.push(CopilotPromptMessage.User(promptParts(content), providerOptions));
				case AiLanguageModelPromptRole.Assistant:
					final content = partContent(message.content, "assistant message content");
					out.push(CopilotPromptMessage.Assistant(promptParts(content), providerOptions));
				case AiLanguageModelPromptRole.Tool:
					final content = partContent(message.content, "tool message content");
					out.push(CopilotPromptMessage.Tool(promptParts(content), providerOptions));
				case role:
					throw 'Unsupported AI SDK prompt role: ${role}';
			}
		}
		return out;
	}

	static function promptParts(parts:Array<AiLanguageModelPromptPart>):Array<CopilotPromptPart> {
		final out:Array<CopilotPromptPart> = [];
		for (part in parts)
			out.push(promptPart(part));
		return out;
	}

	static function textContent(value:opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessageContent, label:String):String {
		if (!Std.isOfType(value, String))
			throw 'Expected AI SDK ${label} to be a string';
		final text:String = value;
		return text;
	}

	static function partContent(value:opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessageContent, label:String):Array<AiLanguageModelPromptPart> {
		if (!Std.isOfType(value, Array))
			throw 'Expected AI SDK ${label} to be a part array';
		final parts:Array<AiLanguageModelPromptPart> = value;
		return parts;
	}

	static function promptPart(part:AiLanguageModelPromptPart):CopilotPromptPart {
		final providerOptions = copilotProviderOptions(part.providerOptions);
		return switch part.type {
			case AiLanguageModelPromptPartType.Text:
				CopilotPromptPart.Text(requireString(part.text, "text part text"), providerOptions);
			case AiLanguageModelPromptPartType.File:
				CopilotPromptPart.File(fileData(requireFileData(part.data, "file part data")), requireString(part.mediaType, "file part mediaType"),
					providerOptions);
			case AiLanguageModelPromptPartType.Reasoning:
				CopilotPromptPart.Reasoning(requireString(part.text, "reasoning part text"), providerOptions);
			case AiLanguageModelPromptPartType.ToolCall:
				CopilotPromptPart.ToolCall(requireString(part.toolCallId, "tool-call part toolCallId"),
					requireString(part.toolName, "tool-call part toolName"), requireUnknown(part.input, "tool-call part input"), providerOptions);
			case AiLanguageModelPromptPartType.ToolResult:
				CopilotPromptPart.ToolResult(requireString(part.toolCallId, "tool-result part toolCallId"),
					requireString(part.toolName, "tool-result part toolName"), toolOutput(requireOutput(part.output, "tool-result part output")),
					providerOptions);
			case AiLanguageModelPromptPartType.ToolApprovalResponse:
				CopilotPromptPart.ToolApprovalResponse(requireString(part.approvalId, "tool-approval-response part approvalId"),
					requireBool(part.approved, "tool-approval-response part approved"), part.reason, providerOptions);
			case type:
				throw 'Unsupported AI SDK prompt part type: ${type}';
		}
	}

	static function fileData(data:AiLanguageModelFileData):CopilotFileData {
		if (Std.isOfType(data, String)) {
			final base64Value:String = data;
			return CopilotFileData.Base64(base64Value);
		}
		if (Std.isOfType(data, Uint8Array)) {
			final bytesValue:Uint8Array = data;
			return CopilotFileData.Bytes(bytesValue);
		}
		final urlValue:URL = data;
		return CopilotFileData.RemoteUrl(urlValue);
	}

	static function toolOutput(output:AiLanguageModelToolResultOutput):CopilotToolOutput {
		return switch output.type {
			case "text":
				final value:String = requireOutputValue(output.value, "tool-result text value");
				CopilotToolOutput.Text(value);
			case "error-text":
				final value:String = requireOutputValue(output.value, "tool-result error-text value");
				CopilotToolOutput.ErrorText(value);
			case "execution-denied":
				CopilotToolOutput.ExecutionDenied(output.reason);
			case "content":
				CopilotToolOutput.Content(requireOutputUnknown(output.value, "tool-result content value"));
			case "json":
				CopilotToolOutput.JsonValue(requireOutputUnknown(output.value, "tool-result json value"));
			case "error-json":
				CopilotToolOutput.ErrorJson(requireOutputUnknown(output.value, "tool-result error-json value"));
			case type:
				throw 'Unsupported AI SDK tool-result output type: ${type}';
		}
	}

	static function responseFormat(format:Null<AiLanguageModelResponseFormat>):Null<opencodehx.provider.copilot.CopilotChatRequest.CopilotChatResponseFormat> {
		if (format == null)
			return null;
		if (format.type == AiLanguageModelResponseFormatType.Text)
			return opencodehx.provider.copilot.CopilotChatRequest.CopilotChatResponseFormat.Text;
		if (format.type == AiLanguageModelResponseFormatType.Json)
			return CopilotChatRequest.jsonResponseFormat(format.schema, format.name, format.description);
		throw "Unsupported AI SDK response format";
	}

	static function compatibleProviderOptions(source:Null<AiProviderOptions>, providerName:String):CopilotCompatibleProviderOptions {
		var user:Null<String> = null;
		var reasoningEffort:Null<String> = null;
		var textVerbosity:Null<String> = null;
		var thinkingBudget:Null<Float> = null;

		function apply(value:Null<AiOpenAICompatibleProviderOptions>):Void {
			if (value == null)
				return;
			if (value.user != null)
				user = value.user;
			if (value.reasoningEffort != null)
				reasoningEffort = value.reasoningEffort;
			if (value.textVerbosity != null)
				textVerbosity = value.textVerbosity;
			if (value.thinkingBudgetSnake != null)
				thinkingBudget = value.thinkingBudgetSnake;
			if (value.thinkingBudget != null)
				thinkingBudget = value.thinkingBudget;
		}

		if (source != null) {
			final options:AiProviderOptionsMap = source;
			apply(options.get("copilot"));
			apply(options.get(providerName));
		}

		return CopilotChatRequest.providerOptions(user, reasoningEffort, textVerbosity, thinkingBudget);
	}

	static function copilotProviderOptions(source:Null<AiProviderOptions>):Null<CopilotProviderOptions> {
		if (source == null)
			return null;
		final options:AiProviderOptionsMap = source;
		final copilot = options.get("copilot");
		if (copilot == null)
			return null;
		final metadata:CopilotMetadata = {};
		if (copilot.reasoningOpaque != null)
			metadata.reasoningOpaque = copilot.reasoningOpaque;
		if (copilot.copilotCacheControl != null)
			metadata.copilot_cache_control = {type: copilot.copilotCacheControl.type};
		return {copilot: metadata};
	}

	static function tools(source:Null<Array<AiLanguageModelTool>>):Array<CopilotChatTool> {
		final out:Array<CopilotChatTool> = [];
		if (source == null)
			return out;
		for (tool in source) {
			if (tool.type == AiLanguageModelToolType.Function) {
				out.push(CopilotChatTool.Function({
					name: tool.name,
					description: stringOrAbsent(tool.description),
					inputSchema: requireUnknown(tool.inputSchema, 'function tool ${tool.name} inputSchema'),
				}));
			} else if (tool.type == AiLanguageModelToolType.Provider) {
				out.push(CopilotChatTool.Provider);
			} else {
				throw "Unsupported AI SDK tool type";
			}
		}
		return out;
	}

	static function toolChoice(source:Null<AiLanguageModelToolChoice>):Null<CopilotChatToolChoice> {
		if (source == null)
			return null;
		if (source.type == AiLanguageModelToolChoiceType.Auto)
			return CopilotChatToolChoice.Auto;
		if (source.type == AiLanguageModelToolChoiceType.None)
			return CopilotChatToolChoice.None;
		if (source.type == AiLanguageModelToolChoiceType.Required)
			return CopilotChatToolChoice.Required;
		if (source.type == AiLanguageModelToolChoiceType.Tool)
			return CopilotChatToolChoice.Tool(requireString(source.toolName, "tool choice toolName"));
		throw "Unsupported AI SDK tool choice";
	}

	static function generateResult(source:CopilotChatGenerateResult):AiLanguageModelGenerateResult {
		return {
			content: content(source.content),
			finishReason: finishReason(source.finishReason),
			usage: usage(source.usage),
			providerMetadata: providerMetadataFromUsage(source.usage.raw.orNull()),
			request: {
				body: Unknown.fromBoundary(source.request.body)
			},
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

	static function content(source:Array<CopilotGeneratedContent>):Array<AiLanguageModelContent> {
		final out:Array<AiLanguageModelContent> = [];
		for (item in source) {
			switch item.type {
				case CopilotGeneratedContentType.Text:
					out.push({
						type: AiLanguageModelContentType.Text,
						text: requireUndefinableString(item.text, "generated text content"),
						providerMetadata: contentMetadata(item.providerMetadata),
					});
				case CopilotGeneratedContentType.Reasoning:
					out.push({
						type: AiLanguageModelContentType.Reasoning,
						text: requireUndefinableString(item.text, "generated reasoning content"),
						providerMetadata: contentMetadata(item.providerMetadata),
					});
				case CopilotGeneratedContentType.ToolCall:
					out.push({
						type: AiLanguageModelContentType.ToolCall,
						toolCallId: requireUndefinableString(item.toolCallId, "generated tool call id"),
						toolName: requireUndefinableString(item.toolName, "generated tool name"),
						input: requireUndefinableString(item.input, "generated tool input"),
						providerMetadata: contentMetadata(item.providerMetadata),
					});
			}
		}
		return out;
	}

	static function eventStream(events:Array<CopilotChatStreamEvent>):AiProviderReadableStream {
		return new WebReadableStream<AiProviderStreamPart>({
			start: controller -> enqueueEvents(controller, events),
		});
	}

	static function enqueueEvents(controller:WebReadableStreamDefaultController<AiProviderStreamPart>, events:Array<CopilotChatStreamEvent>):Void {
		for (event in events)
			controller.enqueue(streamPart(event));
		controller.close();
	}

	static function streamPart(event:CopilotChatStreamEvent):AiProviderStreamPart {
		return switch event.type {
			case CopilotChatStreamEventType.StreamStart:
				{type: "stream-start", warnings: warnings(event.warnings.orNull())};
			case CopilotChatStreamEventType.Raw:
				{type: "raw", rawValue: Unknown.fromBoundary(requireUndefinableString(event.rawValue, "raw stream value"))};
			case CopilotChatStreamEventType.ResponseMetadata:
				{
					type: "response-metadata",
					id: optionalString(event.id),
					modelId: optionalString(event.modelId),
					timestamp: optionalDate(event.timestamp),
				};
			case CopilotChatStreamEventType.ReasoningStart:
				{type: "reasoning-start", id: requireUndefinableString(event.id, "reasoning start id"), providerMetadata: metadata(event.providerMetadata)};
			case CopilotChatStreamEventType.ReasoningDelta:
				{
					type: "reasoning-delta",
					id: requireUndefinableString(event.id, "reasoning delta id"),
					delta: requireUndefinableString(event.delta, "reasoning delta"),
					providerMetadata: metadata(event.providerMetadata),
				};
			case CopilotChatStreamEventType.ReasoningEnd:
				{type: "reasoning-end", id: requireUndefinableString(event.id, "reasoning end id"), providerMetadata: metadata(event.providerMetadata)};
			case CopilotChatStreamEventType.TextStart:
				{type: "text-start", id: requireUndefinableString(event.id, "text start id"), providerMetadata: metadata(event.providerMetadata)};
			case CopilotChatStreamEventType.TextDelta:
				{
					type: "text-delta",
					id: requireUndefinableString(event.id, "text delta id"),
					delta: requireUndefinableString(event.delta, "text delta"),
					providerMetadata: metadata(event.providerMetadata),
				};
			case CopilotChatStreamEventType.TextEnd:
				{type: "text-end", id: requireUndefinableString(event.id, "text end id"), providerMetadata: metadata(event.providerMetadata)};
			case CopilotChatStreamEventType.ToolInputStart:
				{
					type: "tool-input-start",
					id: requireUndefinableString(event.id, "tool input start id"),
					toolName: requireUndefinableString(event.toolName, "tool input start name"),
					providerMetadata: metadata(event.providerMetadata),
				};
			case CopilotChatStreamEventType.ToolInputDelta:
				{
					type: "tool-input-delta",
					id: requireUndefinableString(event.id, "tool input delta id"),
					delta: requireUndefinableString(event.delta, "tool input delta"),
					providerMetadata: metadata(event.providerMetadata),
				};
			case CopilotChatStreamEventType.ToolInputEnd:
				{type: "tool-input-end", id: requireUndefinableString(event.id, "tool input end id"), providerMetadata: metadata(event.providerMetadata)};
			case CopilotChatStreamEventType.ToolCall:
				{
					type: "tool-call",
					toolCallId: requireUndefinableString(event.toolCallId, "tool call id"),
					toolName: requireUndefinableString(event.toolName, "tool call name"),
					input: requireUndefinableString(event.input, "tool call input"),
					providerMetadata: metadata(event.providerMetadata),
				};
			case CopilotChatStreamEventType.Finish:
				{
					type: "finish",
					finishReason: finishReason(requireFinishReason(event.finishReason, "finish reason")),
					usage: streamUsage(requireStreamUsage(event.usage, "finish usage")),
					providerMetadata: metadata(event.providerMetadata),
				};
			case CopilotChatStreamEventType.Error:
				{type: "error", error: Unknown.fromBoundary(requireUndefinableString(event.error, "stream error"))};
		}
	}

	static function warnings(source:Null<Array<CopilotChatWarning>>):Array<AiLanguageModelWarning> {
		final out:Array<AiLanguageModelWarning> = [];
		if (source == null)
			return out;
		for (warning in source) {
			out.push({
				type: AiLanguageModelWarningType.Unsupported,
				feature: warning.feature,
				details: optionalString(warning.details),
			});
		}
		return out;
	}

	static function finishReason(source:CopilotMappedFinishReason):AiLanguageModelFinishReason {
		return {
			unified: source.unified,
			raw: source.raw,
		};
	}

	static function usage(source:CopilotMappedResponseUsage):AiLanguageModelV3Usage {
		return {
			inputTokens: inputTokens(source.inputTokens),
			outputTokens: outputTokens(source.outputTokens),
			raw: unknownOrAbsent(source.raw.orNull()),
		};
	}

	static function streamUsage(source:CopilotMappedStreamUsage):AiLanguageModelV3Usage {
		return {
			inputTokens: inputTokens(source.inputTokens),
			outputTokens: outputTokens(source.outputTokens),
			raw: AiJsonObject.fromBoundary(source.raw),
		};
	}

	static function inputTokens(source:CopilotMappedInputTokens):AiLanguageModelUsageTokens {
		return {
			total: source.total,
			noCache: source.noCache,
			cacheRead: source.cacheRead,
			cacheWrite: source.cacheWrite,
		};
	}

	static function outputTokens(source:CopilotMappedOutputTokens):AiLanguageModelOutputTokens {
		return {
			total: source.total,
			text: source.text,
			reasoning: source.reasoning,
		};
	}

	static function providerMetadataFromUsage(source:Null<CopilotTokenUsage>):Undefinable<AiProviderMetadata> {
		if (source == null)
			return Undefinable.absent();
		final prediction = CopilotChatCompletion.predictionMetadata(source);
		final metadata = predictionMetadata(prediction);
		if (metadata == null)
			return Undefinable.absent();
		return metadata;
	}

	static function contentMetadata(source:Null<Undefinable<CopilotContentProviderMetadata>>):Undefinable<AiProviderMetadata> {
		final present = source == null ? null : source.orNull();
		if (present == null)
			return Undefinable.absent();
		final out = new DynamicAccess<AiJsonObject>();
		out.set("copilot", AiJsonObject.fromBoundary(present.copilot));
		final metadata:AiProviderMetadata = out;
		return metadata;
	}

	static function metadata(source:Null<Undefinable<CopilotChatStreamProviderMetadata>>):Undefinable<AiProviderMetadata> {
		final present = source == null ? null : source.orNull();
		if (present == null)
			return Undefinable.absent();
		final out = new DynamicAccess<AiJsonObject>();
		out.set("copilot", AiJsonObject.fromBoundary(present.copilot));
		final metadata:AiProviderMetadata = out;
		return metadata;
	}

	static function predictionMetadata(source:CopilotPredictionMetadata):Null<AiProviderMetadata> {
		final accepted = source.acceptedPredictionTokens.orNull();
		final rejected = source.rejectedPredictionTokens.orNull();
		if (accepted == null && rejected == null)
			return null;
		final copilot = new DynamicAccess<AiJsonValue>();
		if (accepted != null)
			copilot.set("acceptedPredictionTokens", AiJsonValue.fromBoundary(accepted));
		if (rejected != null)
			copilot.set("rejectedPredictionTokens", AiJsonValue.fromBoundary(rejected));
		final out = new DynamicAccess<AiJsonObject>();
		out.set("copilot", AiJsonObject.fromBoundary(copilot));
		return out;
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

	static function emptySupportedUrls():AiSupportedUrls {
		return new DynamicAccess<Array<AiRegExp>>();
	}

	static function stringArrayOrAbsent(value:Null<Array<String>>):Undefinable<Array<String>> {
		return value == null ? Undefinable.absent() : value;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}

	static function unknownOrAbsent(value:Null<CopilotTokenUsage>):Undefinable<AiJsonObject> {
		return value == null ? Undefinable.absent() : AiJsonObject.fromBoundary(value);
	}

	static function requireString(value:Null<String>, label:String):String {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireBool(value:Null<Bool>, label:String):Bool {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireUnknown(value:Null<Unknown>, label:String):Unknown {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireOutput(value:Null<AiLanguageModelToolResultOutput>, label:String):AiLanguageModelToolResultOutput {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireFileData(value:Null<AiLanguageModelFileData>, label:String):AiLanguageModelFileData {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireOutputValue(value:Null<haxe.extern.EitherType<String, Unknown>>, label:String):String {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		if (!Std.isOfType(value, String))
			throw 'Expected AI SDK ${label} to be a string';
		return Std.string(value);
	}

	static function requireOutputUnknown(value:Null<haxe.extern.EitherType<String, Unknown>>, label:String):Unknown {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		final present:Unknown = value;
		return present;
	}

	static function requireUndefinableString(value:Null<Undefinable<String>>, label:String):String {
		final present = value == null ? null : value.orNull();
		if (present == null)
			throw 'Missing Copilot ${label}';
		return present;
	}

	static function requireFinishReason(value:Null<Undefinable<CopilotMappedFinishReason>>, label:String):CopilotMappedFinishReason {
		final present = value == null ? null : value.orNull();
		if (present == null)
			throw 'Missing Copilot ${label}';
		return present;
	}

	static function requireStreamUsage(value:Null<Undefinable<CopilotMappedStreamUsage>>, label:String):CopilotMappedStreamUsage {
		final present = value == null ? null : value.orNull();
		if (present == null)
			throw 'Missing Copilot ${label}';
		return present;
	}

	static function optionalString(value:Null<Undefinable<String>>):Undefinable<String> {
		if (value == null)
			return Undefinable.absent();
		return value;
	}

	static function optionalDate(value:Null<Undefinable<js.lib.Date>>):Undefinable<js.lib.Date> {
		if (value == null)
			return Undefinable.absent();
		return value;
	}

	static function isEmpty(value:DynamicAccess<String>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}
}
