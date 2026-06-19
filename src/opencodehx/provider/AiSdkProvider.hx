package opencodehx.provider;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import js.Syntax;
import js.html.AbortController;
import js.lib.Promise;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiJsonSchemaObject;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsage;
import opencodehx.externs.ai.AiSdk.AiProviderFinishReason;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.externs.ai.AiSdk.AiProviderUsage;
import opencodehx.externs.ai.AiSdk.AiSdk;
import opencodehx.externs.ai.AiSdk.AiSdkTest;
import opencodehx.externs.ai.AiSdk.AiStreamTextOptions;
import opencodehx.externs.ai.AiSdk.AiTool;
import opencodehx.externs.ai.AiSdk.MockLanguageModelV3;

enum AiSdkStreamEvent {
	TextDelta(text:String);
	ToolCall(toolCallID:String, toolName:String);
	ToolResult(toolCallID:String, toolName:String);
	StreamError(message:String);
	StreamAbort(reason:String);
	Finish(reason:AiFinishReason);
}

typedef AiSdkStreamInput = {
	final model:AiLanguageModel;
	final prompt:String;
	@:optional final tools:DynamicAccess<AiTool>;
	@:optional final abortImmediately:Bool;
}

typedef AiSdkStreamResult = {
	final text:String;
	final finishReason:AiFinishReason;
	final totalUsage:AiLanguageModelUsage;
	final events:Array<AiSdkStreamEvent>;
	final errors:Array<String>;
	final aborted:Bool;
}

typedef AiReadToolInput = {
	final path:String;
}

class AiSdkProvider {
	public static inline final ABORT_REASON = "fixture abort";

	@:async
	public static function stream(input:AiSdkStreamInput):Promise<AiSdkStreamResult> {
		final events:Array<AiSdkStreamEvent> = [];
		final errors:Array<String> = [];
		final controller = input.abortImmediately == true ? new AbortController() : null;
		final options:AiStreamTextOptions = {
			model: input.model,
			prompt: input.prompt,
			tools: toolsOrAbsent(input.tools),
			maxRetries: 0,
			abortSignal: controller == null ? Undefinable.absent() : controller.signal,
			onChunk: event -> {
				final chunk = event.chunk;
				switch chunk.type {
					case "text-delta":
						if (chunk.text != null) events.push(TextDelta(chunk.text));
					case "tool-call":
						events.push(ToolCall(chunk.toolCallId, chunk.toolName));
					case "tool-result":
						events.push(ToolResult(chunk.toolCallId, chunk.toolName));
					case _:
				}
			},
			onError: event -> {
				final message = messageFromUnknown(event.error);
				errors.push(message);
				events.push(StreamError(message));
			},
			onAbort: _ -> {
				events.push(StreamAbort(ABORT_REASON));
			},
		};

		final result = AiSdk.streamText(options);
		if (controller != null)
			Syntax.code("{0}.abort({1})", controller, ABORT_REASON);

		var text = "";
		var finishReason:AiFinishReason = AiFinishReason.Error;
		var totalUsage = emptyUsage();
		try {
			text = @:await Promise.resolve(result.text);
			finishReason = @:await Promise.resolve(result.finishReason);
			totalUsage = @:await Promise.resolve(result.totalUsage);
		} catch (error:Dynamic) {
			// Haxe catches arbitrary JavaScript throw values as Dynamic. This
			// boundary is limited to the AI SDK promise read and normalized
			// immediately into a string error for app-facing code.
			final message = messageFromCaught(error);
			if (input.abortImmediately != true) {
				errors.push(message);
				events.push(StreamError(message));
			}
		}
		events.push(Finish(finishReason));
		return {
			text: text,
			finishReason: finishReason,
			totalUsage: totalUsage,
			events: events,
			errors: errors,
			aborted: input.abortImmediately == true,
		};
	}

	public static function readTool():AiTool {
		return AiSdk.tool({
			inputSchema: AiSdk.jsonSchema(pathInputSchema()),
			execute: input -> Promise.resolve('read:${input.path}'),
		});
	}

	public static function toolSet(name:String, tool:AiTool):DynamicAccess<AiTool> {
		final tools = new DynamicAccess<AiTool>();
		tools.set(name, tool);
		return tools;
	}

	static function toolsOrAbsent(tools:Null<DynamicAccess<AiTool>>):Undefinable<DynamicAccess<AiTool>> {
		return tools == null ? Undefinable.absent() : tools;
	}

	static function pathInputSchema():AiJsonSchemaObject {
		final properties = new DynamicAccess<AiJsonSchemaObject>();
		properties.set("path", {type: "string"});
		return {
			type: "object",
			properties: properties,
			required: ["path"],
			additionalProperties: false,
		};
	}

	static function messageFromUnknown(error:Unknown):String {
		return Syntax.code("{0} instanceof Error ? {0}.message : String({0})", error);
	}

	static function messageFromCaught(error:Dynamic):String {
		return Syntax.code("{0} instanceof Error ? {0}.message : String({0})", error);
	}

	static function emptyUsage():AiLanguageModelUsage {
		return {
			inputTokenDetails: {},
			outputTokenDetails: {},
		};
	}
}

class AiSdkMockModel {
	public static function text(chunks:Array<String>):AiLanguageModel {
		final parts:Array<AiProviderStreamPart> = [AiProviderStreamPart.streamStart(), AiProviderStreamPart.textStart("txt_1")];
		for (chunk in chunks)
			parts.push(AiProviderStreamPart.textDelta("txt_1", chunk));
		parts.push(AiProviderStreamPart.textEnd("txt_1"));
		parts.push(AiProviderStreamPart.finish(finishReason(AiFinishReason.Stop, "stop"), usage(3, 4)));
		return model("mock-text", parts, null, null);
	}

	public static function toolCall():AiLanguageModel {
		return model("mock-tool", [
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.toolCall("tool_1", "read", "{\"path\":\"README.md\"}"),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.ToolCalls, "tool_calls"), usage(3, 4)),
		], null, null);
	}

	public static function error(message:String):AiLanguageModel {
		return model("mock-error", [
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.error(Unknown.fromBoundary(message)),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.Error, "error"), usage(1, 0)),
		], null, null);
	}

	public static function abortable():AiLanguageModel {
		return model("mock-abort", [
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.textStart("txt_abort"),
			AiProviderStreamPart.textDelta("txt_abort", "late"),
			AiProviderStreamPart.textEnd("txt_abort"),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.Stop, "stop"), usage(1, 1)),
		], 30, 30);
	}

	static function model(modelId:String, chunks:Array<AiProviderStreamPart>, initialDelayInMs:Null<Int>, chunkDelayInMs:Null<Int>):AiLanguageModel {
		final mock = new MockLanguageModelV3({
			provider: "opencodehx-test",
			modelId: modelId,
			doStream: {
				stream: AiSdkTest.simulateReadableStream({
					chunks: chunks,
					initialDelayInMs: initialDelayInMs,
					chunkDelayInMs: chunkDelayInMs,
				}),
			},
		});
		// MockLanguageModelV3 implements the AI SDK LanguageModelV3 interface,
		// but Haxe cannot see that external TypeScript `implements` clause.
		return cast mock;
	}

	static function finishReason(unified:AiFinishReason, raw:String):AiProviderFinishReason {
		return {
			unified: unified,
			raw: raw,
		};
	}

	static function usage(inputTokens:Float, outputTokens:Float):AiProviderUsage {
		return {
			inputTokens: {
				total: inputTokens,
				noCache: inputTokens,
				cacheRead: 0,
				cacheWrite: 0,
			},
			outputTokens: {
				total: outputTokens,
				text: outputTokens,
				reasoning: 0,
			},
		};
	}
}
