package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import haxe.Json;
import js.lib.Date;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedStreamUsage;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;

typedef CopilotChatStreamChunk = {
	@:optional final id:Null<String>;
	@:optional final created:Null<Float>;
	@:optional final model:Null<String>;
	final choices:Array<CopilotChatStreamChoice>;
	@:optional final usage:Null<CopilotTokenUsage>;
	@:optional final error:Null<CopilotChatStreamError>;
}

typedef CopilotChatStreamError = {
	final message:String;
}

typedef CopilotChatStreamChoice = {
	@:optional final delta:Null<CopilotChatStreamDelta>;
	@:optional final finish_reason:Null<String>;
}

typedef CopilotChatStreamDelta = {
	@:optional final content:Null<String>;
	@:optional final reasoning_text:Null<String>;
	@:optional final reasoning_opaque:Null<String>;
	@:optional final tool_calls:Null<Array<CopilotChatStreamToolCallDelta>>;
}

typedef CopilotChatStreamToolCallDelta = {
	final index:Int;
	@:optional final id:Null<String>;
	@:native("function") @:optional final fn:Null<CopilotChatStreamFunctionDelta>;
}

typedef CopilotChatStreamFunctionDelta = {
	@:optional final name:Null<String>;
	@:optional final arguments:Null<String>;
}

enum abstract CopilotChatStreamEventType(String) from String to String {
	final StreamStart = "stream-start";
	final ResponseMetadata = "response-metadata";
	final ReasoningStart = "reasoning-start";
	final ReasoningDelta = "reasoning-delta";
	final ReasoningEnd = "reasoning-end";
	final TextStart = "text-start";
	final TextDelta = "text-delta";
	final TextEnd = "text-end";
	final ToolInputStart = "tool-input-start";
	final ToolInputDelta = "tool-input-delta";
	final ToolInputEnd = "tool-input-end";
	final ToolCall = "tool-call";
	final Finish = "finish";
	final Error = "error";
}

typedef CopilotChatStreamProviderMetadata = {
	final copilot:CopilotChatStreamCopilotMetadata;
}

typedef CopilotChatStreamCopilotMetadata = {
	@:optional var reasoningOpaque:Undefinable<String>;
	@:optional var acceptedPredictionTokens:Undefinable<Float>;
	@:optional var rejectedPredictionTokens:Undefinable<Float>;
}

typedef CopilotChatStreamEvent = {
	final type:CopilotChatStreamEventType;
	@:optional var id:Undefinable<String>;
	@:optional var modelId:Undefinable<String>;
	@:optional var timestamp:Undefinable<Date>;
	@:optional var warnings:Undefinable<Array<String>>;
	@:optional var delta:Undefinable<String>;
	@:optional var toolName:Undefinable<String>;
	@:optional var toolCallId:Undefinable<String>;
	@:optional var input:Undefinable<String>;
	@:optional var finishReason:Undefinable<CopilotMappedFinishReason>;
	@:optional var usage:Undefinable<CopilotMappedStreamUsage>;
	@:optional var providerMetadata:Undefinable<CopilotChatStreamProviderMetadata>;
	@:optional var error:Undefinable<String>;
}

class CopilotInvalidStreamChunkError {
	public final message:String;

	public function new(message:String) {
		this.message = message;
	}

	public function toString():String {
		return message;
	}
}

typedef CopilotActiveToolCall = {
	final id:String;
	final name:String;
	var arguments:String;
	var hasFinished:Bool;
}

class CopilotChatStreamState {
	final toolCalls:Array<Null<CopilotActiveToolCall>> = [];
	final usage = new CopilotStreamUsageAccumulator();
	final warnings:Array<String>;
	var finishReason:CopilotMappedFinishReason = {
		unified: AiFinishReason.Other,
		raw: Undefinable.absent(),
	};
	var isFirstChunk = true;
	var isActiveReasoning = false;
	var isActiveText = false;
	var reasoningOpaque:Null<String> = null;

	public function new(?warnings:Array<String>) {
		this.warnings = warnings == null ? [] : warnings;
	}

	public function start():Array<CopilotChatStreamEvent> {
		return [
			{
				type: CopilotChatStreamEventType.StreamStart,
				warnings: warnings,
			},
		];
	}

	public function process(chunk:CopilotChatStreamChunk):Array<CopilotChatStreamEvent> {
		final events:Array<CopilotChatStreamEvent> = [];

		if (chunk.error != null) {
			finishReason = {
				unified: AiFinishReason.Error,
				raw: Undefinable.absent(),
			};
			events.push({type: CopilotChatStreamEventType.Error, error: chunk.error.message});
			return events;
		}

		if (isFirstChunk) {
			isFirstChunk = false;
			final metadata = CopilotChatCompletion.responseMetadata({
				id: chunk.id,
				created: chunk.created,
				model: chunk.model,
				choices: [],
			});
			events.push({
				type: CopilotChatStreamEventType.ResponseMetadata,
				id: metadata.id,
				modelId: metadata.modelId,
				timestamp: metadata.timestamp,
			});
		}

		final chunkUsage = chunk.usage;
		if (chunkUsage != null)
			usage.update(presentUsage(chunkUsage));

		if (chunk.choices.length == 0)
			return events;

		final choice = chunk.choices[0];
		if (choice.finish_reason != null) {
			finishReason = CopilotChatCompletion.finishReason(choice.finish_reason);
		}

		final delta = choice.delta;
		if (delta == null)
			return events;

		captureReasoningOpaque(delta.reasoning_opaque);
		processReasoning(delta.reasoning_text, events);
		processText(delta.content, events);
		processToolCalls(delta.tool_calls, events);

		return events;
	}

	public function finish():Array<CopilotChatStreamEvent> {
		final events:Array<CopilotChatStreamEvent> = [];

		if (isActiveReasoning) {
			events.push(reasoningEndEvent());
			isActiveReasoning = false;
		}

		if (isActiveText) {
			events.push({type: CopilotChatStreamEventType.TextEnd, id: "txt-0"});
			isActiveText = false;
		}

		for (toolCall in toolCalls) {
			if (toolCall == null || toolCall.hasFinished)
				continue;
			events.push({type: CopilotChatStreamEventType.ToolInputEnd, id: toolCall.id});
			events.push({
				type: CopilotChatStreamEventType.ToolCall,
				toolCallId: toolCall.id,
				toolName: toolCall.name,
				input: toolCall.arguments,
			});
			toolCall.hasFinished = true;
		}

		events.push({
			type: CopilotChatStreamEventType.Finish,
			finishReason: finishReason,
			usage: CopilotChatCompletion.streamUsage(usage.toUsage()),
			providerMetadata: finishProviderMetadata(),
		});

		return events;
	}

	function captureReasoningOpaque(value:Null<String>):Void {
		if (value == null || value == "")
			return;
		if (reasoningOpaque != null) {
			throw new CopilotInvalidStreamChunkError("Multiple reasoning_opaque values received in a single response. Only one thinking part per response is supported.");
		}
		reasoningOpaque = value;
	}

	function processReasoning(value:Null<String>, events:Array<CopilotChatStreamEvent>):Void {
		if (value == null || value == "")
			return;
		if (!isActiveReasoning) {
			events.push({type: CopilotChatStreamEventType.ReasoningStart, id: "reasoning-0"});
			isActiveReasoning = true;
		}
		events.push({
			type: CopilotChatStreamEventType.ReasoningDelta,
			id: "reasoning-0",
			delta: value,
		});
	}

	function processText(value:Null<String>, events:Array<CopilotChatStreamEvent>):Void {
		if (value == null || value == "")
			return;
		if (isActiveReasoning && !isActiveText) {
			events.push(reasoningEndEvent());
			isActiveReasoning = false;
		}
		if (!isActiveText) {
			events.push({
				type: CopilotChatStreamEventType.TextStart,
				id: "txt-0",
				providerMetadata: reasoningMetadata(),
			});
			isActiveText = true;
		}
		events.push({
			type: CopilotChatStreamEventType.TextDelta,
			id: "txt-0",
			delta: value,
		});
	}

	function processToolCalls(value:Null<Array<CopilotChatStreamToolCallDelta>>, events:Array<CopilotChatStreamEvent>):Void {
		if (value == null)
			return;
		if (isActiveReasoning) {
			events.push(reasoningEndEvent());
			isActiveReasoning = false;
		}
		for (delta in value)
			processToolCall(delta, events);
	}

	function processToolCall(delta:CopilotChatStreamToolCallDelta, events:Array<CopilotChatStreamEvent>):Void {
		var toolCall = toolCalls[delta.index];
		if (toolCall == null) {
			final toolCallId = requireString(delta.id, "Expected 'id' to be a string.");
			final fn = requireFunction(delta.fn);
			final toolName = requireString(fn.name, "Expected 'function.name' to be a string.");
			final initialArguments = stringOrEmpty(fn.arguments);
			final active:CopilotActiveToolCall = {
				id: toolCallId,
				name: toolName,
				arguments: initialArguments,
				hasFinished: false,
			};
			toolCalls[delta.index] = active;
			events.push({
				type: CopilotChatStreamEventType.ToolInputStart,
				id: active.id,
				toolName: active.name,
			});
			if (initialArguments.length > 0)
				events.push({
					type: CopilotChatStreamEventType.ToolInputDelta,
					id: active.id,
					delta: initialArguments,
				});
			completeToolIfReady(active, events);
			return;
		}

		final active = presentToolCall(toolCall);
		if (active.hasFinished)
			return;

		final nextArguments = delta.fn == null ? "" : stringOrEmpty(delta.fn.arguments);
		active.arguments += nextArguments;
		events.push({
			type: CopilotChatStreamEventType.ToolInputDelta,
			id: active.id,
			delta: nextArguments,
		});
		completeToolIfReady(active, events);
	}

	function completeToolIfReady(toolCall:CopilotActiveToolCall, events:Array<CopilotChatStreamEvent>):Void {
		if (!isParsableJson(toolCall.arguments))
			return;
		events.push({type: CopilotChatStreamEventType.ToolInputEnd, id: toolCall.id});
		events.push({
			type: CopilotChatStreamEventType.ToolCall,
			toolCallId: toolCall.id,
			toolName: toolCall.name,
			input: toolCall.arguments,
			providerMetadata: reasoningMetadata(),
		});
		toolCall.hasFinished = true;
	}

	function reasoningEndEvent():CopilotChatStreamEvent {
		return {
			type: CopilotChatStreamEventType.ReasoningEnd,
			id: "reasoning-0",
			providerMetadata: reasoningMetadata(),
		};
	}

	function reasoningMetadata():Undefinable<CopilotChatStreamProviderMetadata> {
		if (reasoningOpaque == null || reasoningOpaque == "")
			return Undefinable.absent();
		return {
			copilot: {
				reasoningOpaque: reasoningOpaque,
			},
		};
	}

	function finishProviderMetadata():CopilotChatStreamProviderMetadata {
		final metadata:CopilotChatStreamProviderMetadata = {
			copilot: {},
		};
		if (reasoningOpaque != null && reasoningOpaque != "")
			metadata.copilot.reasoningOpaque = reasoningOpaque;
		final accepted = usage.acceptedPredictionTokens;
		if (accepted != null)
			metadata.copilot.acceptedPredictionTokens = accepted;
		final rejected = usage.rejectedPredictionTokens;
		if (rejected != null)
			metadata.copilot.rejectedPredictionTokens = rejected;
		return metadata;
	}

	static function isParsableJson(value:String):Bool {
		try {
			Json.parse(value);
			return true;
		} catch (_:Dynamic) {
			// JSON.parse can throw any JavaScript value. The Dynamic catch is
			// contained to this validation boundary and never escapes.
			return false;
		}
	}

	static function requireString(value:Null<String>, message:String):String {
		if (value == null)
			throw new CopilotInvalidStreamChunkError(message);
		final present:String = value;
		return present;
	}

	static function requireFunction(value:Null<CopilotChatStreamFunctionDelta>):CopilotChatStreamFunctionDelta {
		if (value == null)
			throw new CopilotInvalidStreamChunkError("Expected 'function.name' to be a string.");
		final present:CopilotChatStreamFunctionDelta = value;
		return present;
	}

	static function presentToolCall(value:Null<CopilotActiveToolCall>):CopilotActiveToolCall {
		if (value == null)
			throw new CopilotInvalidStreamChunkError("Expected active tool call.");
		final present:CopilotActiveToolCall = value;
		return present;
	}

	static function presentUsage(value:Null<CopilotTokenUsage>):CopilotTokenUsage {
		if (value == null)
			throw new CopilotInvalidStreamChunkError("Expected stream usage.");
		final present:CopilotTokenUsage = value;
		return present;
	}

	static function stringOrEmpty(value:Null<String>):String {
		if (value == null)
			return "";
		final present:String = value;
		return present;
	}
}

class CopilotChatStream {
	public static function collect(chunks:Array<CopilotChatStreamChunk>, ?warnings:Array<String>):Array<CopilotChatStreamEvent> {
		final state = new CopilotChatStreamState(warnings);
		final events = state.start();
		for (chunk in chunks) {
			for (event in state.process(chunk))
				events.push(event);
		}
		for (event in state.finish())
			events.push(event);
		return events;
	}
}

class CopilotStreamUsageAccumulator {
	public var promptTokens:Null<Float> = null;
	public var cachedTokens:Null<Float> = null;
	public var completionTokens:Null<Float> = null;
	public var totalTokens:Null<Float> = null;
	public var reasoningTokens:Null<Float> = null;
	public var acceptedPredictionTokens:Null<Float> = null;
	public var rejectedPredictionTokens:Null<Float> = null;

	public function new() {}

	public function update(usage:CopilotTokenUsage):Void {
		if (usage.prompt_tokens != null)
			promptTokens = usage.prompt_tokens;
		if (usage.completion_tokens != null)
			completionTokens = usage.completion_tokens;
		if (usage.total_tokens != null)
			totalTokens = usage.total_tokens;
		final promptDetails = usage.prompt_tokens_details;
		if (promptDetails != null && promptDetails.cached_tokens != null)
			cachedTokens = promptDetails.cached_tokens;
		final completionDetails = usage.completion_tokens_details;
		if (completionDetails == null)
			return;
		if (completionDetails.reasoning_tokens != null)
			reasoningTokens = completionDetails.reasoning_tokens;
		if (completionDetails.accepted_prediction_tokens != null)
			acceptedPredictionTokens = completionDetails.accepted_prediction_tokens;
		if (completionDetails.rejected_prediction_tokens != null)
			rejectedPredictionTokens = completionDetails.rejected_prediction_tokens;
	}

	public function toUsage():CopilotTokenUsage {
		return {
			prompt_tokens: promptTokens,
			completion_tokens: completionTokens,
			total_tokens: totalTokens,
			prompt_tokens_details: {
				cached_tokens: cachedTokens,
			},
			completion_tokens_details: {
				reasoning_tokens: reasoningTokens,
				accepted_prediction_tokens: acceptedPredictionTokens,
				rejected_prediction_tokens: rejectedPredictionTokens,
			},
		};
	}
}
