package opencodehx.externs.ai;

import genes.ts.Unknown;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.extern.EitherType;
import js.html.AbortSignal;
import js.html.URL;
import js.lib.Promise;
import js.lib.Promise.Thenable;
import js.lib.Uint8Array;
import opencodehx.externs.aws.AwsCredentialProviders.AwsCredentialProvider;
import opencodehx.externs.web.WebStreams.WebReadableStream;

@:ts.type("import('ai').FinishReason")
enum abstract AiFinishReason(String) from String to String {
	final Stop = "stop";
	final Length = "length";
	final ContentFilter = "content-filter";
	final ToolCalls = "tool-calls";
	final Error = "error";
	final Other = "other";
}

typedef AiProviderInputTokens = {
	final total:Float;
	final noCache:Float;
	final cacheRead:Float;
	final cacheWrite:Float;
}

typedef AiProviderOutputTokens = {
	final total:Float;
	final text:Float;
	final reasoning:Float;
}

typedef AiProviderUsage = {
	final inputTokens:AiProviderInputTokens;
	final outputTokens:AiProviderOutputTokens;
}

typedef AiProviderFinishReason = {
	final unified:AiFinishReason;
	final raw:Undefinable<String>;
}

typedef AiUsageInputDetails = {
	@:optional final noCacheTokens:Float;
	@:optional final cacheReadTokens:Float;
	@:optional final cacheWriteTokens:Float;
}

typedef AiUsageOutputDetails = {
	@:optional final textTokens:Float;
	@:optional final reasoningTokens:Float;
}

typedef AiLanguageModelUsage = {
	@:optional final inputTokens:Float;
	final inputTokenDetails:AiUsageInputDetails;
	@:optional final outputTokens:Float;
	final outputTokenDetails:AiUsageOutputDetails;
	@:optional final totalTokens:Float;
	@:optional final reasoningTokens:Float;
	@:optional final cachedInputTokens:Float;
}

typedef AiTextStreamPart = {
	final type:String;
	@:optional final id:String;
	@:optional final text:String;
	@:optional final toolCallId:String;
	@:optional final toolName:String;
	@:optional final input:Unknown;
	@:optional final output:Unknown;
	@:optional final rawValue:Unknown;
}

typedef AiStreamChunkEvent = {
	final chunk:AiTextStreamPart;
}

typedef AiStreamErrorEvent = {
	final error:Unknown;
}

typedef AiStreamAbortEvent = {
	final steps:Array<Unknown>;
}

typedef AiToolOptions<I, O> = {
	final inputSchema:AiJsonSchema;
	@:optional final description:String;
	@:optional final execute:I->Promise<O>;
}

typedef AiJsonSchemaObject = {
	final type:String;
	@:optional final description:String;
	@:optional final properties:DynamicAccess<AiJsonSchemaObject>;
	@:optional final required:Array<String>;
	@:optional final additionalProperties:Bool;
}

typedef AiStreamHeaders = DynamicAccess<Undefinable<String>>;

typedef AiStreamTextOptions = {
	final model:AiLanguageModel;
	final prompt:EitherType<String, AiModelMessages>;
	final tools:Undefinable<DynamicAccess<AiTool>>;
	final maxRetries:Int;
	final abortSignal:Undefinable<AbortSignal>;
	final maxOutputTokens:Undefinable<Float>;
	final temperature:Undefinable<Float>;
	final topP:Undefinable<Float>;
	final topK:Undefinable<Float>;
	final headers:Undefinable<AiStreamHeaders>;
	final providerOptions:Undefinable<AiSharedProviderOptions>;
	final onChunk:AiStreamChunkEvent->Void;
	final onError:AiStreamErrorEvent->Void;
	final onAbort:AiStreamAbortEvent->Void;
}

enum abstract AiLanguageModelTransformType(String) from String to String {
	final Generate = "generate";
	final Stream = "stream";
}

typedef AiLanguageModelTransformParams = {
	final type:AiLanguageModelTransformType;
	final params:AiLanguageModelCallOptions;
	final model:AiLanguageModelV3;
}

typedef AiLanguageModelMiddlewareShape = {
	final specificationVersion:AiLanguageModelSpecificationVersion;
	final transformParams:AiLanguageModelTransformParams->Thenable<AiLanguageModelCallOptions>;
}

@:forward(specificationVersion, transformParams)
abstract AiLanguageModelMiddleware(AiLanguageModelMiddlewareShape) from AiLanguageModelMiddlewareShape to AiLanguageModelMiddlewareShape {}

typedef AiWrapLanguageModelOptions = {
	final model:AiLanguageModel;
	final middleware:AiLanguageModelMiddleware;
}

typedef AiStreamTextResult = {
	final text:Thenable<String>;
	final finishReason:Thenable<AiFinishReason>;
	final totalUsage:Thenable<AiLanguageModelUsage>;
}

typedef AiMockLanguageModelDoStream = EitherType<AiProviderStreamResult, Array<AiProviderStreamResult>>;

typedef AiMockLanguageModelOptions = {
	@:optional final provider:String;
	@:optional final modelId:String;
	@:optional final doStream:AiMockLanguageModelDoStream;
}

typedef AiProviderStreamResult = {
	final stream:AiProviderReadableStream;
}

typedef AiProviderReadableStreamOptions = {
	final chunks:Array<AiProviderStreamPart>;
	@:optional final initialDelayInMs:Null<Int>;
	@:optional final chunkDelayInMs:Null<Int>;
}

typedef AiSdkFactoryOptionsShape = {
	final name:String;
	final baseURL:String;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
	final includeUsage:Undefinable<Bool>;
}

typedef AiBedrockFactoryOptionsShape = {
	final region:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
	final credentialProvider:Undefinable<AwsCredentialProvider>;
}

typedef AiAnthropicFactoryOptionsShape = {
	final name:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
}

typedef AiOpenAIFactoryOptionsShape = {
	final name:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final organization:Undefinable<String>;
	final project:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
}

typedef AiXaiFactoryOptionsShape = {
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
}

typedef AiAzureFactoryOptionsShape = {
	final resourceName:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
	final apiVersion:Undefinable<String>;
	final useDeploymentBasedUrls:Undefinable<Bool>;
}

typedef AiOptionalHeaderMap = DynamicAccess<Undefinable<String>>;

typedef AiGoogleFactoryOptionsShape = {
	final name:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<AiOptionalHeaderMap>;
}

typedef AiVertexFactoryOptionsShape = {
	final project:Undefinable<String>;
	final location:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<AiOptionalHeaderMap>;
}

typedef AiVertexAnthropicFactoryOptionsShape = {
	final project:Undefinable<String>;
	final location:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final headers:Undefinable<AiOptionalHeaderMap>;
}

typedef AiSimpleFactoryOptionsShape = {
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
}

typedef AiVeniceFactoryOptionsShape = {
	final name:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
	final includeUsage:Undefinable<Bool>;
	final supportsStructuredOutputs:Undefinable<Bool>;
}

@:ts.type("NonNullable<import('@openrouter/ai-sdk-provider').OpenRouterProviderSettings['compatibility']>")
enum abstract AiOpenRouterCompatibility(String) to String {
	final Strict = "strict";
	final Compatible = "compatible";
}

typedef AiOpenRouterFactoryOptionsShape = {
	final baseURL:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
	final compatibility:Undefinable<AiOpenRouterCompatibility>;
	final extraBody:Undefinable<DynamicAccess<Unknown>>;
	final api_keys:Undefinable<DynamicAccess<String>>;
	final appName:Undefinable<String>;
	final appUrl:Undefinable<String>;
}

typedef AiGitLabFactoryOptionsShape = {
	final instanceUrl:Undefinable<String>;
	final apiKey:Undefinable<String>;
	final headers:Undefinable<DynamicAccess<String>>;
	final name:Undefinable<String>;
	final featureFlags:Undefinable<DynamicAccess<Bool>>;
	final aiGatewayUrl:Undefinable<String>;
	final aiGatewayHeaders:Undefinable<DynamicAccess<String>>;
}

typedef AiSdkBundledProvider = {
	function languageModel(modelID:String):AiLanguageModel;
	@:optional final chat:String->AiLanguageModel;
	@:optional final responses:String->AiLanguageModel;
}

typedef AiSdkProviderFactory = AiSdkFactoryOptions->AiSdkBundledProvider;
typedef AiBedrockProviderFactory = AiBedrockFactoryOptions->AiSdkBundledProvider;
typedef AiAnthropicProviderFactory = AiAnthropicFactoryOptions->AiSdkBundledProvider;
typedef AiOpenAIProviderFactory = AiOpenAIFactoryOptions->AiSdkBundledProvider;
typedef AiXaiProviderFactory = AiXaiFactoryOptions->AiSdkBundledProvider;
typedef AiAzureProviderFactory = AiAzureFactoryOptions->AiSdkBundledProvider;
typedef AiGoogleProviderFactory = AiGoogleFactoryOptions->AiSdkBundledProvider;
typedef AiVertexProviderFactory = AiVertexFactoryOptions->AiSdkBundledProvider;
typedef AiVertexAnthropicProviderFactory = AiVertexAnthropicFactoryOptions->AiSdkBundledProvider;
typedef AiMistralProviderFactory = AiMistralFactoryOptions->AiSdkBundledProvider;
typedef AiGroqProviderFactory = AiGroqFactoryOptions->AiSdkBundledProvider;
typedef AiCohereProviderFactory = AiCohereFactoryOptions->AiSdkBundledProvider;
typedef AiPerplexityProviderFactory = AiPerplexityFactoryOptions->AiSdkBundledProvider;
typedef AiOpenRouterProviderFactory = AiOpenRouterFactoryOptions->AiSdkBundledProvider;
typedef AiDeepInfraProviderFactory = AiDeepInfraFactoryOptions->AiSdkBundledProvider;
typedef AiCerebrasProviderFactory = AiCerebrasFactoryOptions->AiSdkBundledProvider;
typedef AiGatewayProviderFactory = AiGatewayFactoryOptions->AiSdkBundledProvider;
typedef AiTogetherAIProviderFactory = AiTogetherAIFactoryOptions->AiSdkBundledProvider;
typedef AiVercelProviderFactory = AiVercelFactoryOptions->AiSdkBundledProvider;
typedef AiAlibabaProviderFactory = AiAlibabaFactoryOptions->AiSdkBundledProvider;
typedef AiVeniceProviderFactory = AiVeniceFactoryOptions->AiSdkBundledProvider;
typedef AiGitLabProviderFactory = AiGitLabFactoryOptions->AiSdkBundledProvider;

@:ts.type("'v3'")
enum abstract AiLanguageModelSpecificationVersion(String) from String to String {
	final V3 = "v3";
}

@:native("RegExp")
extern class AiRegExp {
	function new(pattern:String, ?flags:String);
}

typedef AiSupportedUrlMap = DynamicAccess<Array<AiRegExp>>;

/**
 * Type-only bridge for AI SDK `LanguageModelV3["supportedUrls"]`.
 *
 * The SDK contract is `Record<string, RegExp[]> | PromiseLike<...>`. The
 * Haxe-owned providers currently expose the synchronous record arm, which is
 * the shape upstream's Copilot providers use for concrete URL support.
 */
@:ts.type("Record<string, RegExp[]>")
abstract AiSupportedUrls(AiSupportedUrlMap) from AiSupportedUrlMap to AiSupportedUrlMap {}

typedef AiProviderOptionsMap = DynamicAccess<AiOpenAICompatibleProviderOptions>;

typedef AiOpenAICompatibleProviderOptions = {
	@:optional final user:String;
	@:optional final reasoningEffort:String;
	@:optional final reasoningSummary:String;
	@:optional final textVerbosity:String;
	@:native("thinking_budget") @:optional final thinkingBudgetSnake:Float;
	@:optional final thinkingBudget:Float;
	@:optional final reasoningOpaque:String;
	@:native("copilot_cache_control") @:optional final copilotCacheControl:AiCopilotCacheControl;
	@:optional final include:Array<String>;
	@:optional final instructions:String;
	@:optional final logprobs:EitherType<Bool, Float>;
	@:optional final maxToolCalls:Float;
	@:optional final metadata:AiJsonValue;
	@:optional final parallelToolCalls:Bool;
	@:optional final previousResponseId:String;
	@:optional final promptCacheKey:String;
	@:optional final safetyIdentifier:String;
	@:optional final serviceTier:String;
	@:optional final store:Bool;
	@:optional final strictJsonSchema:Bool;
}

typedef AiCopilotCacheControl = {
	final type:String;
}

/**
 * Type-only bridge for SDK provider options.
 *
 * Haxe reads only the OpenAI-compatible subset that Copilot supports while the
 * emitted TypeScript remains the SDK-owned `SharedV3ProviderOptions` record.
 */
@:ts.type("import('@ai-sdk/provider').SharedV3ProviderOptions")
abstract AiProviderOptions(AiProviderOptionsMap) from AiProviderOptionsMap to AiProviderOptionsMap {}

typedef AiSharedProviderOptionsMap = DynamicAccess<AiJsonObject>;

/**
 * Open provider-options bridge for `streamText(...)` request assembly.
 *
 * Product code owns provider-specific validation before values enter this
 * record. This abstraction only preserves the AI SDK's open
 * `SharedV3ProviderOptions` boundary without weakening Copilot's narrower
 * `AiProviderOptions` readers.
 */
@:ts.type("import('@ai-sdk/provider').SharedV3ProviderOptions")
abstract AiSharedProviderOptions(AiSharedProviderOptionsMap) from AiSharedProviderOptionsMap to AiSharedProviderOptionsMap {}

/**
 * AI SDK metadata objects are JSON-shaped, not arbitrary JS objects.
 *
 * `fromBoundary` is the explicit crossing point after local code has built or
 * decoded a JSON-compatible object. The backing `Unknown` keeps callers from
 * reading unchecked fields while `@:ts.type` preserves the SDK declaration.
 */
@:ts.type("import('@ai-sdk/provider').JSONObject")
abstract AiJsonObject(Unknown) from Unknown to Unknown {
	public static inline function fromBoundary<T>(value:T):AiJsonObject {
		return Unknown.fromBoundary(value);
	}
}

/**
 * AI SDK JSON payload bridge for values accepted by provider metadata, tool
 * payloads, and response bodies. Keep construction explicit so non-JSON
 * runtime values do not spread through application types by accident.
 */
@:ts.type("import('@ai-sdk/provider').JSONValue")
abstract AiJsonValue(Unknown) from Unknown to Unknown {
	public static inline function fromBoundary<T>(value:T):AiJsonValue {
		return Unknown.fromBoundary(value);
	}
}

/**
 * Some AI SDK result fields reject `null` while still accepting any JSON
 * scalar/object/array. This bridge keeps that TS contract precise without
 * weakening the surrounding Haxe DTOs.
 */
@:ts.type("NonNullable<import('@ai-sdk/provider').JSONValue>")
abstract AiNonNullJsonValue(AiJsonValue) from AiJsonValue to AiJsonValue {
	public static inline function fromBoundary<T>(value:T):AiNonNullJsonValue {
		return AiJsonValue.fromBoundary(value);
	}
}

@:ts.type("import('@ai-sdk/provider').SharedV3ProviderMetadata")
abstract AiProviderMetadata(DynamicAccess<AiJsonObject>) from DynamicAccess<AiJsonObject> to DynamicAccess<AiJsonObject> {}

enum abstract AiLanguageModelPromptRole(String) from String to String {
	final System = "system";
	final User = "user";
	final Assistant = "assistant";
	final Tool = "tool";
}

enum abstract AiLanguageModelPromptPartType(String) from String to String {
	final Text = "text";
	final File = "file";
	final Reasoning = "reasoning";
	final ToolCall = "tool-call";
	final ToolResult = "tool-result";
	final ToolApprovalResponse = "tool-approval-response";
}

typedef AiLanguageModelFileData = EitherType<String, EitherType<Uint8Array, URL>>;
typedef AiLanguageModelPromptMessageContent = EitherType<String, Array<AiLanguageModelPromptPart>>;

typedef AiLanguageModelPromptMessage = {
	final role:AiLanguageModelPromptRole;
	final content:AiLanguageModelPromptMessageContent;
	@:optional final providerOptions:AiProviderOptions;
}

typedef AiModelToolCallPartShape = {
	final type:String;
	final toolCallId:String;
	final toolName:String;
	final input:Unknown;
}

@:ts.type("'text' | 'json' | 'content' | 'execution-denied' | 'error-text' | 'error-json'")
enum abstract AiModelToolResultOutputType(String) from String to String {
	final Text = "text";
	final ErrorText = "error-text";
}

typedef AiModelTextPartShape = {
	final type:String;
	final text:String;
}

typedef AiModelFilePartShape = {
	final type:String;
	final data:AiLanguageModelFileData;
	@:optional final filename:String;
	final mediaType:String;
}

typedef AiModelToolResultOutputShape = {
	final type:AiModelToolResultOutputType;
	@:optional final value:String;
	@:optional final reason:String;
}

typedef AiModelToolResultPartShape = {
	final type:String;
	final toolCallId:String;
	final toolName:String;
	final output:AiModelToolResultOutput;
}

@:forward(type, toolCallId, toolName, input)
@:ts.type("import('ai').ToolCallPart")
abstract AiModelToolCallPart(AiModelToolCallPartShape) from AiModelToolCallPartShape to AiModelToolCallPartShape {}

@:forward(type, text)
@:ts.type("import('ai').TextPart")
abstract AiModelTextPart(AiModelTextPartShape) from AiModelTextPartShape to AiModelTextPartShape {}

@:forward(type, data, filename, mediaType)
@:ts.type("import('ai').FilePart")
abstract AiModelFilePart(AiModelFilePartShape) from AiModelFilePartShape to AiModelFilePartShape {}

@:forward(type, value)
@:ts.type("import('@ai-sdk/provider-utils').ToolResultOutput")
abstract AiModelToolResultOutput(AiModelToolResultOutputShape) from AiModelToolResultOutputShape to AiModelToolResultOutputShape {}

@:forward(type, toolCallId, toolName, output)
@:ts.type("import('ai').ToolResultPart")
abstract AiModelToolResultPart(AiModelToolResultPartShape) from AiModelToolResultPartShape to AiModelToolResultPartShape {}

typedef AiModelUserMessagePart = EitherType<AiModelTextPart, AiModelFilePart>;
typedef AiModelAssistantMessagePart = EitherType<AiModelTextPart, EitherType<AiModelFilePart, EitherType<AiModelToolCallPart, AiModelToolResultPart>>>;
typedef AiModelToolMessagePart = AiModelToolResultPart;
typedef AiModelMessagePart = EitherType<AiModelUserMessagePart, EitherType<AiModelAssistantMessagePart, AiModelToolMessagePart>>;

typedef AiModelToolResultTurn = {
	final toolCallId:String;
	final toolName:String;
	final input:Unknown;
	final output:String;
}

typedef AiModelMessageShape = {
	final role:String;
	final content:EitherType<String, Array<AiModelMessagePart>>;
}

@:forward(role, content)
@:ts.type("import('ai').ModelMessage")
abstract AiModelMessage(AiModelMessageShape) from AiModelMessageShape to AiModelMessageShape {}

/**
 * Public AI SDK message input accepted by `streamText`.
 *
 * The provider call surface records the converted LanguageModelV3 prompt,
 * while `streamText` accepts its own `ModelMessage[]` union at the boundary.
 */
@:ts.type("import('ai').ModelMessage[]")
abstract AiModelMessages(Array<AiModelMessage>) from Array<AiModelMessage> to Array<AiModelMessage> {
	public static function systemUser(system:Array<String>, user:String):AiModelMessages {
		return systemHistoryUser(system, [], user);
	}

	public static function systemUserToolResult(system:Array<String>, user:String, toolCallId:String, toolName:String, input:Unknown,
			output:String):AiModelMessages {
		return systemUserToolResults(system, user, [
			{
				toolCallId: toolCallId,
				toolName: toolName,
				input: input,
				output: output,
			}
		]);
	}

	public static function systemUserToolResults(system:Array<String>, user:String, turns:Array<AiModelToolResultTurn>):AiModelMessages {
		return systemHistoryUserToolResults(system, [], user, turns);
	}

	public static function systemHistoryUser(system:Array<String>, history:Array<AiModelMessage>, user:String):AiModelMessages {
		final out:Array<AiModelMessage> = [];
		pushSystem(out, system);
		for (message in history)
			out.push(message);
		out.push({
			role: "user",
			content: user,
		});
		return out;
	}

	public static function systemHistoryUserToolResults(system:Array<String>, history:Array<AiModelMessage>, user:String,
			turns:Array<AiModelToolResultTurn>):AiModelMessages {
		final out:Array<AiModelMessage> = systemHistoryUser(system, history, user);
		for (turn in turns) {
			out.push({
				role: "assistant",
				content: [toolCallPart(turn)],
			});
			out.push({
				role: "tool",
				content: [toolResultPart(turn)],
			});
		}
		return out;
	}

	static function pushSystem(out:Array<AiModelMessage>, system:Array<String>):Void {
		for (item in system) {
			out.push({
				role: "system",
				content: item,
			});
		}
	}

	static function toolCallPart(turn:AiModelToolResultTurn):AiModelToolCallPart {
		return {
			type: "tool-call",
			toolCallId: turn.toolCallId,
			toolName: turn.toolName,
			input: turn.input,
		};
	}

	static function toolResultPart(turn:AiModelToolResultTurn):AiModelToolResultPart {
		return {
			type: "tool-result",
			toolCallId: turn.toolCallId,
			toolName: turn.toolName,
			output: {
				type: "text",
				value: turn.output,
			},
		};
	}
}

typedef AiLanguageModelPromptPart = {
	final type:AiLanguageModelPromptPartType;
	@:optional final text:String;
	@:optional final filename:String;
	@:optional final data:AiLanguageModelFileData;
	@:optional final mediaType:String;
	@:optional final toolCallId:String;
	@:optional final toolName:String;
	@:optional final input:Unknown;
	@:optional final output:AiLanguageModelToolResultOutput;
	@:optional final approvalId:String;
	@:optional final approved:Bool;
	@:optional final reason:String;
	@:optional final providerOptions:AiProviderOptions;
}

typedef AiLanguageModelToolResultOutput = {
	final type:String;
	@:optional final value:EitherType<String, Unknown>;
	@:optional final reason:String;
	@:optional final providerOptions:AiProviderOptions;
}

@:ts.type("import('@ai-sdk/provider').LanguageModelV3Prompt")
abstract AiLanguageModelPrompt(Array<AiLanguageModelPromptMessage>) from Array<AiLanguageModelPromptMessage> to Array<AiLanguageModelPromptMessage> {}

enum abstract AiLanguageModelResponseFormatType(String) from String to String {
	final Text = "text";
	final Json = "json";
}

typedef AiLanguageModelResponseFormatShape = {
	final type:AiLanguageModelResponseFormatType;
	@:optional final schema:Unknown;
	@:optional final name:String;
	@:optional final description:String;
}

@:forward(type, schema, name, description)
@:ts.type("NonNullable<import('@ai-sdk/provider').LanguageModelV3CallOptions['responseFormat']>")
abstract AiLanguageModelResponseFormat(AiLanguageModelResponseFormatShape) from AiLanguageModelResponseFormatShape to AiLanguageModelResponseFormatShape {}

enum abstract AiLanguageModelToolType(String) from String to String {
	final Function = "function";
	final Provider = "provider";
}

typedef AiLanguageModelToolShape = {
	final type:AiLanguageModelToolType;
	final name:String;
	@:optional final description:String;
	@:optional final inputSchema:Unknown;
	@:optional final id:String;
	@:optional final args:Unknown;
	@:optional final strict:Bool;
	@:optional final providerOptions:AiProviderOptions;
}

@:forward(type, name, description, inputSchema, id, args, strict, providerOptions)
@:ts.type("NonNullable<import('@ai-sdk/provider').LanguageModelV3CallOptions['tools']>[number]")
abstract AiLanguageModelTool(AiLanguageModelToolShape) from AiLanguageModelToolShape to AiLanguageModelToolShape {}

enum abstract AiLanguageModelToolChoiceType(String) from String to String {
	final Auto = "auto";
	final None = "none";
	final Required = "required";
	final Tool = "tool";
}

typedef AiLanguageModelToolChoiceShape = {
	final type:AiLanguageModelToolChoiceType;
	@:optional final toolName:String;
}

@:forward(type, toolName)
@:ts.type("NonNullable<import('@ai-sdk/provider').LanguageModelV3CallOptions['toolChoice']>")
abstract AiLanguageModelToolChoice(AiLanguageModelToolChoiceShape) from AiLanguageModelToolChoiceShape to AiLanguageModelToolChoiceShape {}

typedef AiLanguageModelCallOptionsShape = {
	var prompt:AiLanguageModelPrompt;
	@:optional final maxOutputTokens:Float;
	@:optional final temperature:Float;
	@:optional final stopSequences:Array<String>;
	@:optional final topP:Float;
	@:optional final topK:Float;
	@:optional final presencePenalty:Float;
	@:optional final frequencyPenalty:Float;
	@:optional final responseFormat:AiLanguageModelResponseFormat;
	@:optional final seed:Float;
	@:optional final tools:Array<AiLanguageModelTool>;
	@:optional final toolChoice:AiLanguageModelToolChoice;
	@:optional final includeRawChunks:Bool;
	@:optional final abortSignal:AbortSignal;
	@:optional final headers:DynamicAccess<Undefinable<String>>;
	@:optional final providerOptions:AiProviderOptions;
}

@:forward(prompt, maxOutputTokens, temperature, stopSequences, topP, topK, presencePenalty, frequencyPenalty, responseFormat, seed, tools, toolChoice,
	includeRawChunks, abortSignal, headers, providerOptions)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3CallOptions")
abstract AiLanguageModelCallOptions(AiLanguageModelCallOptionsShape) from AiLanguageModelCallOptionsShape to AiLanguageModelCallOptionsShape {}

enum abstract AiLanguageModelContentType(String) from String to String {
	final Text = "text";
	final Reasoning = "reasoning";
	final ToolCall = "tool-call";
	final ToolResult = "tool-result";
	final File = "file";
	final Source = "source";
	final ToolApprovalRequest = "tool-approval-request";
}

@:ts.type("'url' | 'document'")
enum abstract AiLanguageModelSourceType(String) from String to String {
	final Url = "url";
	final Document = "document";
}

typedef AiLanguageModelContentShape = {
	final type:AiLanguageModelContentType;
	@:optional final id:String;
	@:optional final text:String;
	@:optional final mediaType:String;
	@:optional final data:EitherType<String, Uint8Array>;
	@:optional final toolCallId:String;
	@:optional final toolName:String;
	@:optional final input:String;
	@:optional final result:AiNonNullJsonValue;
	@:optional final providerExecuted:Bool;
	@:optional final sourceType:AiLanguageModelSourceType;
	@:optional final url:String;
	@:optional final title:String;
	@:optional final filename:String;
	@:optional final providerMetadata:Undefinable<AiProviderMetadata>;
}

@:forward(type, id, text, mediaType, data, toolCallId, toolName, input, result, providerExecuted, sourceType, url, title, filename, providerMetadata)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3Content")
abstract AiLanguageModelContent(AiLanguageModelContentShape) from AiLanguageModelContentShape to AiLanguageModelContentShape {}

enum abstract AiLanguageModelWarningType(String) from String to String {
	final Unsupported = "unsupported";
	final Compatibility = "compatibility";
	final Other = "other";
}

typedef AiLanguageModelWarningShape = {
	final type:AiLanguageModelWarningType;
	@:optional final feature:Undefinable<String>;
	@:optional final details:Undefinable<String>;
	@:optional final message:Undefinable<String>;
}

@:ts.type("import('@ai-sdk/provider').SharedV3Warning")
abstract AiLanguageModelWarning(AiLanguageModelWarningShape) from AiLanguageModelWarningShape to AiLanguageModelWarningShape {}

typedef AiLanguageModelUsageTokens = {
	final total:Undefinable<Float>;
	final noCache:Undefinable<Float>;
	final cacheRead:Undefinable<Float>;
	final cacheWrite:Undefinable<Float>;
}

typedef AiLanguageModelOutputTokens = {
	final total:Undefinable<Float>;
	final text:Undefinable<Float>;
	final reasoning:Undefinable<Float>;
}

typedef AiLanguageModelV3UsageShape = {
	final inputTokens:AiLanguageModelUsageTokens;
	final outputTokens:AiLanguageModelOutputTokens;
	@:optional final raw:Undefinable<AiJsonObject>;
}

@:forward(inputTokens, outputTokens, raw)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3Usage")
abstract AiLanguageModelV3Usage(AiLanguageModelV3UsageShape) from AiLanguageModelV3UsageShape to AiLanguageModelV3UsageShape {}

typedef AiLanguageModelFinishReasonShape = {
	final unified:AiFinishReason;
	final raw:Undefinable<String>;
}

@:forward(unified, raw)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3FinishReason")
abstract AiLanguageModelFinishReason(AiLanguageModelFinishReasonShape) from AiLanguageModelFinishReasonShape to AiLanguageModelFinishReasonShape {}

typedef AiLanguageModelRequestInfo = {
	@:optional final body:Unknown;
}

typedef AiLanguageModelGenerateResponseInfo = {
	@:optional final id:Undefinable<String>;
	@:optional final timestamp:Undefinable<js.lib.Date>;
	@:optional final modelId:Undefinable<String>;
	@:optional final headers:DynamicAccess<String>;
	@:optional final body:Unknown;
}

typedef AiLanguageModelGenerateResultShape = {
	final content:Array<AiLanguageModelContent>;
	final finishReason:AiLanguageModelFinishReason;
	final usage:AiLanguageModelV3Usage;
	@:optional final providerMetadata:Undefinable<AiProviderMetadata>;
	@:optional final request:AiLanguageModelRequestInfo;
	@:optional final response:AiLanguageModelGenerateResponseInfo;
	final warnings:Array<AiLanguageModelWarning>;
}

@:forward(content, finishReason, usage, providerMetadata, request, response, warnings)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3GenerateResult")
abstract AiLanguageModelGenerateResult(AiLanguageModelGenerateResultShape) from AiLanguageModelGenerateResultShape to AiLanguageModelGenerateResultShape {}

typedef AiLanguageModelStreamResponseInfo = {
	final headers:Undefinable<DynamicAccess<String>>;
}

typedef AiLanguageModelStreamResultShape = {
	final stream:AiProviderReadableStream;
	@:optional final request:AiLanguageModelRequestInfo;
	@:optional final response:AiLanguageModelStreamResponseInfo;
}

@:forward(stream, request, response)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3StreamResult")
abstract AiLanguageModelStreamResult(AiLanguageModelStreamResultShape) from AiLanguageModelStreamResultShape to AiLanguageModelStreamResultShape {}

typedef AiLanguageModelStreamPartShape = {
	final type:String;
	@:optional final warnings:Array<AiLanguageModelWarning>;
	@:optional final id:String;
	@:optional final modelId:String;
	@:optional final timestamp:js.lib.Date;
	@:optional final delta:String;
	@:optional final toolName:String;
	@:optional final toolCallId:String;
	@:optional final input:String;
	@:optional final providerExecuted:Bool;
	@:optional final result:AiNonNullJsonValue;
	@:optional final sourceType:AiLanguageModelSourceType;
	@:optional final url:String;
	@:optional final title:String;
	@:optional final filename:String;
	@:optional final mediaType:String;
	@:optional final finishReason:AiLanguageModelFinishReason;
	@:optional final usage:AiLanguageModelV3Usage;
	@:optional final providerMetadata:Undefinable<AiProviderMetadata>;
	@:optional final rawValue:Unknown;
	@:optional final error:Unknown;
}

typedef AiLanguageModelShape = {
	final specificationVersion:String;
	final provider:String;
	final modelId:String;
	final supportedUrls:AiSupportedUrls;
	function doGenerate(options:AiLanguageModelCallOptions):Promise<AiLanguageModelGenerateResult>;
	function doStream(options:AiLanguageModelCallOptions):Promise<AiLanguageModelStreamResult>;
}

/**
 * Type-only bridge for OpenAI-compatible provider factory settings.
 *
 * Haxe's `@:optional` fields currently lower to `T | null | undefined`, but
 * this package requires JavaScript `undefined` rather than `null`. The Haxe
 * shape therefore uses explicit `Undefinable<T>` fields and this raw override
 * keeps the public TypeScript type aligned with the SDK declaration.
 */
@:forward(name, baseURL, apiKey, headers, includeUsage)
@:ts.type("import('@ai-sdk/openai-compatible').OpenAICompatibleProviderSettings")
abstract AiSdkFactoryOptions(AiSdkFactoryOptionsShape) from AiSdkFactoryOptionsShape to AiSdkFactoryOptionsShape {}

/**
 * Type-only bridge for Amazon Bedrock provider settings.
 *
 * Bedrock has a different SDK factory contract from OpenAI-compatible
 * providers: region is required for useful calls, bearer `apiKey` disables
 * SigV4, and `credentialProvider` carries AWS's dynamic credential chain.
 */
@:forward(region, apiKey, baseURL, headers, credentialProvider)
@:ts.type("import('@ai-sdk/amazon-bedrock').AmazonBedrockProviderSettings")
abstract AiBedrockFactoryOptions(AiBedrockFactoryOptionsShape) from AiBedrockFactoryOptionsShape to AiBedrockFactoryOptionsShape {}

/**
 * Type-only bridge for AI SDK language models accepted by `streamText`.
 *
 * Some bundled providers still expose `LanguageModelV2` while Haxe-owned
 * adapters implement `LanguageModelV3`. The public `ai` package accepts both.
 * Keep V3 call-option/result types on Haxe-owned adapters, but use the V2/V3
 * union at the provider-loading boundary so real SDK packages do not need
 * casts or false runtime-version assertions.
 */
@:forward(specificationVersion, provider, modelId, supportedUrls, doGenerate, doStream)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3 | import('@ai-sdk/provider').LanguageModelV2")
abstract AiLanguageModel(AiLanguageModelShape) from AiLanguageModelShape to AiLanguageModelShape {}

/**
 * V3-only model bridge for SDKs that explicitly reject V2 models.
 *
 * Most OpenCodeHX runtime code should use `AiLanguageModel`, the V2/V3 union
 * accepted by `ai.streamText`. Cloudflare AI Gateway is narrower: its wrapper
 * combines only `LanguageModelV3` instances, so its extern needs this exact
 * type to keep TypeScript assignability honest.
 */
@:forward(specificationVersion, provider, modelId, supportedUrls, doGenerate, doStream)
@:ts.type("import('@ai-sdk/provider').LanguageModelV3")
abstract AiLanguageModelV3(AiLanguageModelShape) from AiLanguageModelShape to AiLanguageModelShape to AiLanguageModel {}

/**
 * Type-only bridge for Anthropic provider settings.
 *
 * Anthropic has a default API base URL and currently exposes a LanguageModelV2
 * provider surface, so it cannot reuse the OpenAI-compatible settings bridge
 * without either forcing a fake baseURL or lying about the returned model type.
 */
@:forward(name, baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/anthropic').AnthropicProviderSettings")
abstract AiAnthropicFactoryOptions(AiAnthropicFactoryOptionsShape) from AiAnthropicFactoryOptionsShape to AiAnthropicFactoryOptionsShape {}

/**
 * Type-only bridge for official OpenAI provider settings.
 *
 * OpenAI has its own package-owned settings type. It mostly resembles the
 * OpenAI-compatible bridge, but also carries organization/project and returns
 * V3 response/chat models from its own factory methods.
 */
@:forward(name, baseURL, apiKey, organization, project, headers)
@:ts.type("import('@ai-sdk/openai').OpenAIProviderSettings")
abstract AiOpenAIFactoryOptions(AiOpenAIFactoryOptionsShape) from AiOpenAIFactoryOptionsShape to AiOpenAIFactoryOptionsShape {}

/**
 * Type-only bridge for official xAI provider settings.
 *
 * xAI intentionally has no `name` field in its published settings contract.
 * Keep this separate from the OpenAI bridge so generated TypeScript does not
 * rely on extra object-literal properties that the SDK type rejects.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/xai').XaiProviderSettings")
abstract AiXaiFactoryOptions(AiXaiFactoryOptionsShape) from AiXaiFactoryOptionsShape to AiXaiFactoryOptionsShape {}

/**
 * Type-only bridge for Azure OpenAI provider settings.
 *
 * Azure can be addressed by either `baseURL` or `resourceName`, and it carries
 * deployment/API-version switches that do not exist on plain OpenAI providers.
 */
@:forward(resourceName, baseURL, apiKey, headers, apiVersion, useDeploymentBasedUrls)
@:ts.type("import('@ai-sdk/azure').AzureOpenAIProviderSettings")
abstract AiAzureFactoryOptions(AiAzureFactoryOptionsShape) from AiAzureFactoryOptionsShape to AiAzureFactoryOptionsShape {}

/**
 * Type-only bridge for Google Generative AI provider settings.
 *
 * Google accepts string-or-undefined header values, so the Haxe backing map of
 * strings remains assignable while still keeping provider option narrowing in
 * `ProviderOptionAccess`.
 */
@:forward(name, baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/google').GoogleGenerativeAIProviderSettings")
abstract AiGoogleFactoryOptions(AiGoogleFactoryOptionsShape) from AiGoogleFactoryOptionsShape to AiGoogleFactoryOptionsShape {}

/**
 * Type-only bridge for Google Vertex provider settings.
 *
 * Project/location/API-key express mode are stable string settings. Google auth
 * options and custom fetch/token hooks stay out of this bridge until a typed
 * Google host-auth seam owns them.
 */
@:forward(project, location, baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/google-vertex').GoogleVertexProviderSettings")
abstract AiVertexFactoryOptions(AiVertexFactoryOptionsShape) from AiVertexFactoryOptionsShape to AiVertexFactoryOptionsShape {}

/**
 * Type-only bridge for Vertex Anthropic provider settings.
 *
 * This package subpath has a distinct settings type and no API-key field, so
 * keeping it separate prevents accidental extra properties in generated TS.
 */
@:forward(project, location, baseURL, headers)
@:ts.type("import('@ai-sdk/google-vertex/anthropic').GoogleVertexAnthropicProviderSettings")
abstract AiVertexAnthropicFactoryOptions(AiVertexAnthropicFactoryOptionsShape) from AiVertexAnthropicFactoryOptionsShape
	to AiVertexAnthropicFactoryOptionsShape {}

/**
 * Type-only bridge for Mistral provider settings.
 *
 * Mistral's stable loader settings match the simple baseURL/apiKey/headers
 * shape. `generateId` stays out until a typed request/ID seam owns it.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/mistral').MistralProviderSettings")
abstract AiMistralFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Groq provider settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/groq').GroqProviderSettings")
abstract AiGroqFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Cohere provider settings.
 *
 * Cohere also supports `generateId`, but OpenCodeHX does not own that runtime
 * seam in this slice, so the backing shape keeps only stable request settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/cohere').CohereProviderSettings")
abstract AiCohereFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Perplexity provider settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/perplexity').PerplexityProviderSettings")
abstract AiPerplexityFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for OpenRouter provider settings.
 *
 * OpenRouter has richer package-specific settings such as compatibility mode,
 * extraBody, BYOK maps, and app attribution. Loader construction owns those
 * stable provider-level settings while fetch hooks and model/request-specific
 * options stay out until a typed host-request or OpenRouter facade owns them.
 */
@:forward(baseURL, apiKey, headers, compatibility, extraBody, api_keys, appName, appUrl)
@:ts.type("import('@openrouter/ai-sdk-provider').OpenRouterProviderSettings")
abstract AiOpenRouterFactoryOptions(AiOpenRouterFactoryOptionsShape) from AiOpenRouterFactoryOptionsShape to AiOpenRouterFactoryOptionsShape {}

/**
 * Type-only bridge for DeepInfra provider settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/deepinfra').DeepInfraProviderSettings")
abstract AiDeepInfraFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Cerebras provider settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/cerebras').CerebrasProviderSettings")
abstract AiCerebrasFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Vercel AI Gateway provider settings.
 *
 * The package also exposes metadata-cache tuning and fetch hooks. This loader
 * bridge keeps only stable baseURL/apiKey/header transport settings; gateway
 * routing/caching request options stay in ProviderTransform.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/gateway').GatewayProviderSettings")
abstract AiGatewayFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for TogetherAI provider settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/togetherai').TogetherAIProviderSettings")
abstract AiTogetherAIFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Vercel provider settings.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/vercel').VercelProviderSettings")
abstract AiVercelFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Alibaba provider settings.
 *
 * Alibaba has separate embedding/video endpoint settings and includeUsage.
 * This loader slice owns only chat-language model loading; embedding/video and
 * stream-usage knobs belong to later typed request/facade work.
 */
@:forward(baseURL, apiKey, headers)
@:ts.type("import('@ai-sdk/alibaba').AlibabaProviderSettings")
abstract AiAlibabaFactoryOptions(AiSimpleFactoryOptionsShape) from AiSimpleFactoryOptionsShape to AiSimpleFactoryOptionsShape {}

/**
 * Type-only bridge for Venice provider settings.
 *
 * Venice has its own SDK-owned options type. The loader narrows only the
 * stable OpenCode settings before constructing the provider.
 */
@:forward(name, baseURL, apiKey, headers, includeUsage, supportsStructuredOutputs)
@:ts.type("import('venice-ai-sdk-provider').VeniceProviderSettings")
abstract AiVeniceFactoryOptions(AiVeniceFactoryOptionsShape) from AiVeniceFactoryOptionsShape to AiVeniceFactoryOptionsShape {}

/**
 * Type-only bridge for GitLab Duo provider settings.
 *
 * OAuth refresh fields and custom fetch stay out until the auth/request seams
 * own those lifecycles. The registry already narrows instance URL, API token,
 * feature flags, and AI Gateway headers before the provider is constructed.
 */
@:forward(instanceUrl, apiKey, headers, name, featureFlags, aiGatewayUrl, aiGatewayHeaders)
@:ts.type("import('gitlab-ai-provider').GitLabProviderSettings")
abstract AiGitLabFactoryOptions(AiGitLabFactoryOptionsShape) from AiGitLabFactoryOptionsShape to AiGitLabFactoryOptionsShape {}

/**
 * Type-only bridge for AI SDK `Tool`.
 *
 * The real type is heavily generic and inferred by `tool(...)`. Haxe code
 * constructs tools through the typed `AiToolOptions<I, O>` wrapper and stores
 * them only in the `streamText` boundary record.
 */
@:ts.type("import('ai').Tool")
abstract AiTool(Dynamic) from Dynamic to Dynamic {}

/**
 * Type-only bridge for JSON Schema accepted by AI SDK `jsonSchema(...)`.
 */
@:ts.type("import('ai').JSONSchema7")
abstract AiJsonSchema(Dynamic) from Dynamic to Dynamic {}

/**
 * Type-only bridge for provider stream parts used by `ai/test`.
 *
 * These constructors contain the only casts in the mock-provider setup. They
 * turn small Haxe records into the SDK's discriminated union after each
 * required discriminant and payload field has been supplied.
 */
@:ts.type("import('@ai-sdk/provider').LanguageModelV3StreamPart")
@:forward(type, warnings, id, modelId, timestamp, delta, toolName, toolCallId, input, providerExecuted, result, sourceType, url, title, filename, mediaType,
	finishReason, usage, providerMetadata, rawValue, error)
abstract AiProviderStreamPart(AiLanguageModelStreamPartShape) from AiLanguageModelStreamPartShape to AiLanguageModelStreamPartShape {
	public static inline function streamStart():AiProviderStreamPart {
		return {type: "stream-start", warnings: []};
	}

	public static inline function textStart(id:String):AiProviderStreamPart {
		return {type: "text-start", id: id};
	}

	public static inline function textDelta(id:String, delta:String):AiProviderStreamPart {
		return {type: "text-delta", id: id, delta: delta};
	}

	public static inline function textEnd(id:String):AiProviderStreamPart {
		return {type: "text-end", id: id};
	}

	public static inline function toolCall(toolCallId:String, toolName:String, input:String):AiProviderStreamPart {
		return {
			type: "tool-call",
			toolCallId: toolCallId,
			toolName: toolName,
			input: input
		};
	}

	public static inline function finish(finishReason:AiProviderFinishReason, usage:AiProviderUsage):AiProviderStreamPart {
		return {type: "finish", finishReason: finishReason, usage: concreteUsage(usage)};
	}

	public static inline function error(error:Unknown):AiProviderStreamPart {
		return {type: "error", error: error};
	}

	static inline function concreteUsage(usage:AiProviderUsage):AiLanguageModelV3Usage {
		return {
			inputTokens: {
				total: usage.inputTokens.total,
				noCache: usage.inputTokens.noCache,
				cacheRead: usage.inputTokens.cacheRead,
				cacheWrite: usage.inputTokens.cacheWrite,
			},
			outputTokens: {
				total: usage.outputTokens.total,
				text: usage.outputTokens.text,
				reasoning: usage.outputTokens.reasoning,
			},
		};
	}
}

/**
 * Type-only bridge for `ReadableStream<LanguageModelV3StreamPart>`.
 *
 * Haxe 4.3's JS stdlib does not provide a generic DOM ReadableStream extern,
 * so this stays as an AI SDK test boundary type.
 */
@:ts.type("ReadableStream<import('@ai-sdk/provider').LanguageModelV3StreamPart>")
abstract AiProviderReadableStream(WebReadableStream<AiProviderStreamPart>) from WebReadableStream<AiProviderStreamPart>
	to WebReadableStream<AiProviderStreamPart> {}

@:jsRequire("ai")
extern class AiSdk {
	static function streamText(options:AiStreamTextOptions):AiStreamTextResult;
	static function tool<I, O>(options:AiToolOptions<I, O>):AiTool;
	static function jsonSchema(schema:AiJsonSchemaObject):AiJsonSchema;
	static function wrapLanguageModel(options:AiWrapLanguageModelOptions):AiLanguageModelV3;
}

@:jsRequire("ai/test", "MockLanguageModelV3")
extern class MockLanguageModelV3 {
	final doStreamCalls:Array<AiLanguageModelCallOptions>;

	function new(?options:AiMockLanguageModelOptions);
}

@:jsRequire("ai/test")
extern class AiSdkTest {
	static function simulateReadableStream(options:AiProviderReadableStreamOptions):AiProviderReadableStream;
}
