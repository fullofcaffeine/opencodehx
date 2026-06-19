package opencodehx.externs.ai;

import genes.ts.Unknown;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import js.html.AbortSignal;
import js.lib.Promise;
import js.lib.Promise.Thenable;

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
	final raw:String;
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
	final execute:I->Promise<O>;
}

typedef AiJsonSchemaObject = {
	final type:String;
	@:optional final properties:DynamicAccess<AiJsonSchemaObject>;
	@:optional final required:Array<String>;
	@:optional final additionalProperties:Bool;
}

typedef AiStreamTextOptions = {
	final model:AiLanguageModel;
	final prompt:String;
	final tools:Undefinable<DynamicAccess<AiTool>>;
	final maxRetries:Int;
	final abortSignal:Undefinable<AbortSignal>;
	final onChunk:AiStreamChunkEvent->Void;
	final onError:AiStreamErrorEvent->Void;
	final onAbort:AiStreamAbortEvent->Void;
}

typedef AiStreamTextResult = {
	final text:Thenable<String>;
	final finishReason:Thenable<AiFinishReason>;
	final totalUsage:Thenable<AiLanguageModelUsage>;
}

typedef AiMockLanguageModelOptions = {
	@:optional final provider:String;
	@:optional final modelId:String;
	@:optional final doStream:AiProviderStreamResult;
}

typedef AiProviderStreamResult = {
	final stream:AiProviderReadableStream;
}

typedef AiProviderReadableStreamOptions = {
	final chunks:Array<AiProviderStreamPart>;
	@:optional final initialDelayInMs:Null<Int>;
	@:optional final chunkDelayInMs:Null<Int>;
}

/**
 * Type-only bridge for AI SDK `LanguageModelV3`.
 *
 * Haxe cannot reasonably mirror the full provider interface here without
 * duplicating the SDK. Keep this raw TS type confined to the extern boundary;
 * app-facing code consumes typed `AiSdkProvider` results instead.
 */
@:ts.type("import('@ai-sdk/provider').LanguageModelV3")
abstract AiLanguageModel(Dynamic) from Dynamic to Dynamic {}

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
abstract AiProviderStreamPart(Dynamic) from Dynamic {
	public static inline function streamStart():AiProviderStreamPart {
		return cast {type: "stream-start", warnings: []};
	}

	public static inline function textStart(id:String):AiProviderStreamPart {
		return cast {type: "text-start", id: id};
	}

	public static inline function textDelta(id:String, delta:String):AiProviderStreamPart {
		return cast {type: "text-delta", id: id, delta: delta};
	}

	public static inline function textEnd(id:String):AiProviderStreamPart {
		return cast {type: "text-end", id: id};
	}

	public static inline function toolCall(toolCallId:String, toolName:String, input:String):AiProviderStreamPart {
		return cast {
			type: "tool-call",
			toolCallId: toolCallId,
			toolName: toolName,
			input: input
		};
	}

	public static inline function finish(finishReason:AiProviderFinishReason, usage:AiProviderUsage):AiProviderStreamPart {
		return cast {type: "finish", finishReason: finishReason, usage: usage};
	}

	public static inline function error(error:Unknown):AiProviderStreamPart {
		return cast {type: "error", error: error};
	}
}

/**
 * Type-only bridge for `ReadableStream<LanguageModelV3StreamPart>`.
 *
 * Haxe 4.3's JS stdlib does not provide a generic DOM ReadableStream extern,
 * so this stays as an AI SDK test boundary type.
 */
@:ts.type("ReadableStream<import('@ai-sdk/provider').LanguageModelV3StreamPart>")
abstract AiProviderReadableStream(Dynamic) from Dynamic to Dynamic {}

@:jsRequire("ai")
extern class AiSdk {
	static function streamText(options:AiStreamTextOptions):AiStreamTextResult;
	static function tool<I, O>(options:AiToolOptions<I, O>):AiTool;
	static function jsonSchema(schema:AiJsonSchemaObject):AiJsonSchema;
}

@:jsRequire("ai/test", "MockLanguageModelV3")
extern class MockLanguageModelV3 {
	function new(?options:AiMockLanguageModelOptions);
}

@:jsRequire("ai/test")
extern class AiSdkTest {
	static function simulateReadableStream(options:AiProviderReadableStreamOptions):AiProviderReadableStream;
}
