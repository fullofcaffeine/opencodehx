package opencodehx.provider;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.extern.EitherType;
import js.lib.Promise;
import js.lib.Error as JsError;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiJsonSchemaObject;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsage;
import opencodehx.externs.ai.AiSdk.AiModelMessages;
import opencodehx.externs.ai.AiSdk.AiProviderFinishReason;
import opencodehx.externs.ai.AiSdk.AiProviderStreamPart;
import opencodehx.externs.ai.AiSdk.AiProviderStreamResult;
import opencodehx.externs.ai.AiSdk.AiProviderUsage;
import opencodehx.externs.ai.AiSdk.AiJsonObject;
import opencodehx.externs.ai.AiSdk.AiSdk;
import opencodehx.externs.ai.AiSdk.AiSdkTest;
import opencodehx.externs.ai.AiSdk.AiSharedProviderOptionsMap;
import opencodehx.externs.ai.AiSdk.AiSharedProviderOptions;
import opencodehx.externs.ai.AiSdk.AiStreamHeaders;
import opencodehx.externs.ai.AiSdk.AiStreamTextOptions;
import opencodehx.externs.ai.AiSdk.AiTool;
import opencodehx.externs.ai.AiSdk.MockLanguageModelV3;
import opencodehx.externs.web.AbortControllerWithReason;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolParameter;

enum AiSdkStreamEvent {
	TextDelta(text:String);
	ToolCall(toolCallID:String, toolName:String, input:Unknown);
	ToolResult(toolCallID:String, toolName:String, output:Unknown);
	StreamError(message:String);
	StreamAbort(reason:String);
	Finish(reason:AiFinishReason);
}

typedef AiSdkStreamInput = {
	final model:AiLanguageModel;
	final prompt:String;
	@:optional final tools:DynamicAccess<AiTool>;
	@:optional final messages:AiModelMessages;
	@:optional final abortImmediately:Bool;
	@:optional final maxOutputTokens:Float;
	@:optional final temperature:Undefinable<Float>;
	@:optional final topP:Undefinable<Float>;
	@:optional final topK:Undefinable<Float>;
	@:optional final headers:ProviderHeaders;
	@:optional final providerOptions:ProviderOptions;
	@:optional final maxRetries:Int;
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

typedef AiSdkInspectableMock = {
	final language:AiLanguageModel;
	final mock:MockLanguageModelV3;
}

class AiSdkProvider {
	public static inline final ABORT_REASON = "fixture abort";

	@:async
	public static function stream(input:AiSdkStreamInput):Promise<AiSdkStreamResult> {
		final events:Array<AiSdkStreamEvent> = [];
		final errors:Array<String> = [];
		final controller = input.abortImmediately == true ? new AbortControllerWithReason() : null;
		final prompt:EitherType<String, AiModelMessages> = input.messages == null ? input.prompt : input.messages;
		final options:AiStreamTextOptions = {
			model: input.model,
			prompt: prompt,
			tools: toolsOrAbsent(input.tools),
			maxRetries: input.maxRetries == null ? 0 : input.maxRetries,
			abortSignal: controller == null ? Undefinable.absent() : controller.signal,
			maxOutputTokens: numberOrAbsent(input.maxOutputTokens),
			temperature: undefinableNumberOrAbsent(input.temperature),
			topP: undefinableNumberOrAbsent(input.topP),
			topK: undefinableNumberOrAbsent(input.topK),
			headers: headersOrAbsent(input.headers),
			providerOptions: providerOptionsOrAbsent(input.providerOptions),
			onChunk: streamChunkHandler(events),
			onError: streamErrorHandler(events, errors),
			onAbort: streamAbortHandler(events),
		};

		final result = AiSdk.streamText(options);
		if (controller != null)
			controller.abort(ABORT_REASON);

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
			description: "Read a file from the workspace.",
			inputSchema: AiSdk.jsonSchema(pathInputSchema()),
			execute: input -> Promise.resolve('read:${input.path}'),
		});
	}

	public static function toolsFromRegistry(registry:ToolRegistry):DynamicAccess<AiTool> {
		final tools = new DynamicAccess<AiTool>();
		for (def in registry.all()) {
			tools.set(def.id, AiSdk.tool({
				description: def.description,
				inputSchema: AiSdk.jsonSchema(toolInputSchema(def)),
			}));
		}
		return tools;
	}

	public static function toolSet(name:String, tool:AiTool):DynamicAccess<AiTool> {
		final tools = new DynamicAccess<AiTool>();
		tools.set(name, tool);
		return tools;
	}

	public static function toolInputSchema(def:ToolDef):AiJsonSchemaObject {
		final properties = new DynamicAccess<AiJsonSchemaObject>();
		final required:Array<String> = [];
		for (parameter in def.schema.parameters) {
			properties.set(parameter.name, parameterSchema(parameter));
			if (parameter.required)
				required.push(parameter.name);
		}
		return {
			type: "object",
			properties: properties,
			required: required,
			additionalProperties: false,
		};
	}

	static function toolsOrAbsent(tools:Null<DynamicAccess<AiTool>>):Undefinable<DynamicAccess<AiTool>> {
		return tools == null ? Undefinable.absent() : tools;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}

	static function undefinableNumberOrAbsent(value:Null<Undefinable<Float>>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}

	static function headersOrAbsent(headers:Null<ProviderHeaders>):Undefinable<AiStreamHeaders> {
		if (headers == null)
			return Undefinable.absent();
		final out = new AiStreamHeaders();
		for (key in headers.keys()) {
			final value = headers.get(key);
			if (value != null)
				out.set(key, value);
		}
		return out;
	}

	static function providerOptionsOrAbsent(options:Null<ProviderOptions>):Undefinable<AiSharedProviderOptions> {
		if (options == null)
			return Undefinable.absent();
		final out = new AiSharedProviderOptionsMap();
		for (key in options.keys()) {
			// ProviderOptions is upstream's provider-SDK passthrough boundary.
			// At this bridge the top-level values are per-provider JSON option
			// objects produced by SessionLlm/ProviderTransform. Preserve the
			// SDK's JSONObject contract in one place instead of weakening the
			// session path with broad casts.
			final value = options.get(key);
			if (value != null)
				out.set(key, AiJsonObject.fromBoundary(value));
		}
		final shared:AiSharedProviderOptions = out;
		return shared;
	}

	static function streamChunkHandler(events:Array<AiSdkStreamEvent>):opencodehx.externs.ai.AiSdk.AiStreamChunkEvent->Void {
		return event -> {
			final chunk = event.chunk;
			switch chunk.type {
				case "text-delta":
					if (chunk.text != null) events.push(TextDelta(chunk.text));
				case "tool-call":
					events.push(ToolCall(chunk.toolCallId, chunk.toolName, optionalUnknown(chunk.input)));
				case "tool-result":
					events.push(ToolResult(chunk.toolCallId, chunk.toolName, optionalUnknown(chunk.output)));
				case _:
			}
		};
	}

	static function streamErrorHandler(events:Array<AiSdkStreamEvent>, errors:Array<String>):opencodehx.externs.ai.AiSdk.AiStreamErrorEvent->Void {
		return event -> {
			final message = messageFromUnknown(event.error);
			errors.push(message);
			events.push(StreamError(message));
		};
	}

	static function streamAbortHandler(events:Array<AiSdkStreamEvent>):opencodehx.externs.ai.AiSdk.AiStreamAbortEvent->Void {
		return _ -> {
			events.push(StreamAbort(ABORT_REASON));
		};
	}

	static function optionalUnknown(value:Null<Unknown>):Unknown {
		return value == null ? Unknown.fromBoundary({}) : value;
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

	static function parameterSchema(parameter:ToolParameter):AiJsonSchemaObject {
		final type = switch parameter.type {
			case "string":
				"string";
			case "integer":
				"integer";
			case "number":
				"number";
			case "boolean":
				"boolean";
			case unknown:
				throw 'Unsupported tool parameter type for ${parameter.name}: ${unknown}';
		}
		return parameter.description == null ? {type: type} : {type: type, description: parameter.description};
	}

	static function messageFromUnknown(error:Unknown):String {
		return messageFromBoundary(error);
	}

	static function messageFromCaught(error:Dynamic):String {
		// JavaScript can throw any value. Wrap the catch payload as Unknown so
		// normalization stays in one typed boundary instead of using raw syntax.
		return messageFromBoundary(Unknown.fromBoundary(error));
	}

	static function messageFromBoundary(error:Unknown):String {
		if (Std.isOfType(error, JsError)) {
			// The runtime check above proves this boundary value is a JS Error.
			final jsError:JsError = cast error;
			return jsError.message;
		}
		return Std.string(error);
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
		return inspectableText(chunks).language;
	}

	public static function inspectableText(chunks:Array<String>):AiSdkInspectableMock {
		final parts:Array<AiProviderStreamPart> = [AiProviderStreamPart.streamStart(), AiProviderStreamPart.textStart("txt_1")];
		for (chunk in chunks)
			parts.push(AiProviderStreamPart.textDelta("txt_1", chunk));
		parts.push(AiProviderStreamPart.textEnd("txt_1"));
		parts.push(AiProviderStreamPart.finish(finishReason(AiFinishReason.Stop, "stop"), usage(3, 4)));
		return inspectableModel("mock-text", parts, null, null);
	}

	public static function toolCall(?toolName:String, ?input:String):AiLanguageModel {
		final name = toolName == null ? "read" : toolName;
		final payload = input == null ? "{\"path\":\"README.md\"}" : input;
		return model("mock-tool", [
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.toolCall("tool_1", name, payload),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.ToolCalls, "tool_calls"), usage(3, 4)),
		], null, null);
	}

	public static function inspectableToolCall(?toolName:String, ?input:String):AiSdkInspectableMock {
		final name = toolName == null ? "read" : toolName;
		final payload = input == null ? "{\"path\":\"README.md\"}" : input;
		return inspectableModel("mock-tool", [
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.toolCall("tool_1", name, payload),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.ToolCalls, "tool_calls"), usage(3, 4)),
		], null, null);
	}

	public static function inspectableToolThenText(text:String, ?toolName:String, ?input:String):AiSdkInspectableMock {
		var name = "read";
		if (toolName != null)
			name = toolName;
		var payload = "{\"path\":\"README.md\"}";
		if (input != null)
			payload = input;
		final first = toolCallStream("tool_1", name, payload);
		final second = textStream("txt_2", text);
		final mock = new MockLanguageModelV3({
			provider: "opencodehx-test",
			modelId: "mock-tool-then-text",
			// ai/test records the call before indexing array fixtures, so index
			// zero is unused and the first real stream lives at index one.
			doStream: [first, first, second],
		});
		// MockLanguageModelV3 implements the AI SDK LanguageModelV3 interface,
		// but Haxe cannot see that external TypeScript `implements` clause.
		return {
			language: cast mock,
			mock: mock,
		};
	}

	public static function inspectableTwoToolsThenText(text:String, ?firstToolName:String, ?firstInput:String, ?secondToolName:String,
			?secondInput:String):AiSdkInspectableMock {
		var firstName = "read";
		if (firstToolName != null)
			firstName = firstToolName;
		var secondName = firstName;
		if (secondToolName != null)
			secondName = secondToolName;
		var firstPayload = "{\"path\":\"README.md\"}";
		if (firstInput != null)
			firstPayload = firstInput;
		var secondPayload = firstPayload;
		if (secondInput != null)
			secondPayload = secondInput;
		final first = toolCallStream("tool_1", firstName, firstPayload);
		final second = toolCallStream("tool_2", secondName, secondPayload);
		final third = textStream("txt_3", text);
		final mock = new MockLanguageModelV3({
			provider: "opencodehx-test",
			modelId: "mock-two-tools-then-text",
			// ai/test records the call before indexing array fixtures, so index
			// zero is unused and the first real stream lives at index one.
			doStream: [first, first, second, third],
		});
		// MockLanguageModelV3 implements the AI SDK LanguageModelV3 interface,
		// but Haxe cannot see that external TypeScript `implements` clause.
		return {
			language: cast mock,
			mock: mock,
		};
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
		return inspectableModel(modelId, chunks, initialDelayInMs, chunkDelayInMs).language;
	}

	static function inspectableModel(modelId:String, chunks:Array<AiProviderStreamPart>, initialDelayInMs:Null<Int>,
			chunkDelayInMs:Null<Int>):AiSdkInspectableMock {
		final mock = new MockLanguageModelV3({
			provider: "opencodehx-test",
			modelId: modelId,
			doStream: streamResult(chunks, initialDelayInMs, chunkDelayInMs),
		});
		// MockLanguageModelV3 implements the AI SDK LanguageModelV3 interface,
		// but Haxe cannot see that external TypeScript `implements` clause.
		return {
			language: cast mock,
			mock: mock,
		};
	}

	static function streamResult(chunks:Array<AiProviderStreamPart>, initialDelayInMs:Null<Int>, chunkDelayInMs:Null<Int>):AiProviderStreamResult {
		return {
			stream: AiSdkTest.simulateReadableStream({
				chunks: chunks,
				initialDelayInMs: initialDelayInMs,
				chunkDelayInMs: chunkDelayInMs,
			}),
		};
	}

	static function toolCallStream(callID:String, name:String, payload:String):AiProviderStreamResult {
		return streamResult([
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.toolCall(callID, name, payload),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.ToolCalls, "tool_calls"), usage(3, 4)),
		], null, null);
	}

	static function textStream(textID:String, text:String):AiProviderStreamResult {
		return streamResult([
			AiProviderStreamPart.streamStart(),
			AiProviderStreamPart.textStart(textID),
			AiProviderStreamPart.textDelta(textID, text),
			AiProviderStreamPart.textEnd(textID),
			AiProviderStreamPart.finish(finishReason(AiFinishReason.Stop, "stop"), usage(5, 6)),
		], null, null);
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
