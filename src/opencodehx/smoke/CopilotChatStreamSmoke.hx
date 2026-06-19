package opencodehx.smoke;

import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.provider.copilot.CopilotChatStream;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamChunk;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEvent;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEventType;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatRawStreamChunk;
import opencodehx.provider.copilot.CopilotChatStream.CopilotInvalidStreamChunkError;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamProviderMetadata;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotMappedStreamUsage;

class CopilotChatStreamSmoke {
	public static function run():Void {
		basicTextStream();
		rawChunks();
		reasoningToToolCalls();
		reasoningOpaqueWithContent();
		reasoningTextContentThenToolCalls();
		reasoningOpaqueToolCallsWithoutReasoningText();
		lateReasoningOpaque();
		errorChunk();
		invalidChunks();
	}

	static function basicTextStream():Void {
		final events = CopilotChatStream.collect([
			{
				id: "chatcmpl-123",
				created: 1677652288,
				model: "gemini-2.0-flash-001",
				choices: [{delta: {content: "Hello"}},],
			},
			{
				choices: [{delta: {content: " world"}},],
			},
			{
				choices: [{finish_reason: "stop", delta: {content: "!"}},],
			},
		]);

		eq(events[0].type, CopilotChatStreamEventType.StreamStart, "basic stream start");
		final metadata = first(events, CopilotChatStreamEventType.ResponseMetadata);
		eq(metadata.id.orNull(), "chatcmpl-123", "basic metadata id");
		eq(metadata.modelId.orNull(), "gemini-2.0-flash-001", "basic metadata model");
		eq(timestampOf(metadata).getTime(), 1677652288000.0, "basic metadata timestamp");

		final textEvents = only(events, [
			CopilotChatStreamEventType.TextStart,
			CopilotChatStreamEventType.TextDelta,
			CopilotChatStreamEventType.TextEnd,
			CopilotChatStreamEventType.Finish,
		]);
		eq(textEvents[0].type, CopilotChatStreamEventType.TextStart, "basic text start");
		eq(textEvents[0].id.orNull(), "txt-0", "basic text id");
		eq(textEvents[1].delta.orNull(), "Hello", "basic text delta 1");
		eq(textEvents[2].delta.orNull(), " world", "basic text delta 2");
		eq(textEvents[3].delta.orNull(), "!", "basic text delta 3");
		eq(textEvents[4].type, CopilotChatStreamEventType.TextEnd, "basic text end");
		eq(finishReasonOf(textEvents[5]).unified, AiFinishReason.Stop, "basic finish");
	}

	static function rawChunks():Void {
		final chunks:Array<CopilotChatRawStreamChunk> = [
			{
				rawValue: "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}",
				chunk: {
					id: "chatcmpl-raw",
					created: 1677652288,
					model: "gemini-2.0-flash-001",
					choices: [{delta: {content: "Hello"}},],
				},
			},
			{
				rawValue: "data: {\"choices\":[{\"finish_reason\":\"stop\",\"delta\":{}}]}",
				chunk: {
					choices: [{finish_reason: "stop", delta: {}},],
				},
			},
		];

		final events = CopilotChatStream.collectRaw(chunks, true);
		final rawEvents = only(events, [CopilotChatStreamEventType.Raw]);
		eq(rawEvents.length, 2, "raw chunk count");
		eq(rawEvents[0].rawValue.orNull(), chunks[0].rawValue, "raw chunk first payload");
		eq(rawEvents[1].rawValue.orNull(), chunks[1].rawValue, "raw chunk second payload");
		lt(indexOf(events, first(events, CopilotChatStreamEventType.StreamStart)), indexOf(events, rawEvents[0]), "stream start before first raw chunk");
		lt(indexOf(events, rawEvents[0]), indexOf(events, first(events, CopilotChatStreamEventType.ResponseMetadata)), "first raw before parsed metadata");
		lt(indexOf(events, rawEvents[1]), indexOf(events, first(events, CopilotChatStreamEventType.TextEnd)), "second raw before parsed finish events");

		final withoutRaw = CopilotChatStream.collectRaw(chunks, false);
		eq(only(withoutRaw, [CopilotChatStreamEventType.Raw]).length, 0, "raw chunks omitted when disabled");
	}

	static function reasoningToToolCalls():Void {
		final events = CopilotChatStream.collect([
			{
				choices: [{delta: {reasoning_text: "**Understanding Dayzee's Purpose**"}},],
				usage: emptyUsage(),
			},
			{
				choices: [{delta: {reasoning_text: "**Assessing Dayzee's Functionality**"}},],
				usage: emptyUsage(),
			},
			{
				choices: [
					{
						delta: {
							reasoning_opaque: "opaque-tools",
							tool_calls: [
								{
									index: 0,
									id: "call_abc123",
									fn: {
										name: "read_file",
										arguments: "{\"filePath\":\"/README.md\"}",
									},
								},
							],
						},
					},
				],
				usage: emptyUsage(),
			},
			{
				choices: [
					{
						finish_reason: "tool_calls",
						delta: {
							tool_calls: [
								{
									index: 1,
									id: "call_def456",
									fn: {
										name: "read_file",
										arguments: "{\"filePath\":\"/mix.exs\"}",
									},
								},
							],
						},
					},
				],
				usage: {
					prompt_tokens: 19581,
					completion_tokens: 53,
					total_tokens: 19768,
					prompt_tokens_details: {cached_tokens: 17068},
					completion_tokens_details: {
						reasoning_tokens: 134,
						accepted_prediction_tokens: 7,
						rejected_prediction_tokens: 3,
					},
				},
			},
		]);

		final reasoningEnd = first(events, CopilotChatStreamEventType.ReasoningEnd);
		final toolStart = first(events, CopilotChatStreamEventType.ToolInputStart);
		lt(indexOf(events, reasoningEnd), indexOf(events, toolStart), "reasoning ends before tool input");
		eq(reasoningEnd.id.orNull(), "reasoning-0", "reasoning end id");
		eq(reasoningOpaque(reasoningEnd), "opaque-tools", "reasoning end opaque");
		eq(only(events, [
			CopilotChatStreamEventType.TextStart,
			CopilotChatStreamEventType.TextDelta,
			CopilotChatStreamEventType.TextEnd
		]).length, 0, "direct reasoning to tool has no text");
		eq(toolStart.id.orNull(), "call_abc123", "tool input id");
		eq(toolStart.toolName.orNull(), "read_file", "tool input name");

		final toolCalls = only(events, [CopilotChatStreamEventType.ToolCall]);
		eq(toolCalls.length, 2, "tool call count");
		final toolCall = toolCalls[0];
		eq(toolCall.toolCallId.orNull(), "call_abc123", "tool call id");
		eq(toolCall.toolName.orNull(), "read_file", "tool call name");
		eq(toolCall.input.orNull(), "{\"filePath\":\"/README.md\"}", "tool call input");
		eq(reasoningOpaque(toolCall), "opaque-tools", "tool call opaque");
		eq(toolCalls[1].toolCallId.orNull(), "call_def456", "second tool call id");
		eq(toolCalls[1].toolName.orNull(), "read_file", "second tool call name");
		eq(toolCalls[1].input.orNull(), "{\"filePath\":\"/mix.exs\"}", "second tool call input");
		eq(reasoningOpaque(toolCalls[1]), "opaque-tools", "second tool call opaque");

		final finish = first(events, CopilotChatStreamEventType.Finish);
		final finishUsage = usageOf(finish);
		final finishMetadata = metadataOf(finish);
		eq(finishReasonOf(finish).unified, AiFinishReason.ToolCalls, "tool finish reason");
		eq(finishUsage.inputTokens.total.orNull(), 19581.0, "tool finish prompt");
		eq(finishUsage.inputTokens.noCache.orNull(), 2513.0, "tool finish no cache");
		eq(finishUsage.outputTokens.total.orNull(), 53.0, "tool finish completion");
		eq(finishUsage.outputTokens.reasoning.orNull(), 134.0, "tool finish reasoning");
		eq(finishMetadata.copilot.acceptedPredictionTokens.orNull(), 7.0, "tool accepted prediction");
		eq(finishMetadata.copilot.rejectedPredictionTokens.orNull(), 3.0, "tool rejected prediction");
	}

	static function reasoningOpaqueWithContent():Void {
		final events = CopilotChatStream.collect([
			{
				choices: [{delta: {reasoning_text: "**Understanding the Query's Nature**"}},],
			},
			{
				choices: [{delta: {reasoning_text: "**Framing the Response's Core**"}},],
			},
			{
				choices: [
					{
						delta: {
							content: "Of course. I'm thinking right now.",
							reasoning_opaque: "opaque-with-content",
						},
					},
				],
			},
			{
				choices: [{finish_reason: "stop", delta: {content: " What's on your mind?"}},],
			},
		]);

		final reasoningEnd = first(events, CopilotChatStreamEventType.ReasoningEnd);
		final textStart = first(events, CopilotChatStreamEventType.TextStart);
		lt(indexOf(events, reasoningEnd), indexOf(events, textStart), "same chunk opaque reasoning ends before text");
		eq(reasoningOpaque(reasoningEnd), "opaque-with-content", "same chunk opaque on reasoning end");
		eq(reasoningOpaque(textStart), "opaque-with-content", "same chunk opaque on text start");
		final textDeltas = only(events, [CopilotChatStreamEventType.TextDelta]);
		eq(textDeltas.length, 2, "same chunk text deltas");
		eq(textDeltas[0].delta.orNull(), "Of course. I'm thinking right now.", "same chunk first text");
		eq(textDeltas[1].delta.orNull(), " What's on your mind?", "same chunk second text");
		eq(finishReasonOf(first(events, CopilotChatStreamEventType.Finish)).unified, AiFinishReason.Stop, "same chunk finish");
	}

	static function reasoningTextContentThenToolCalls():Void {
		final events = CopilotChatStream.collect([
			{
				choices: [{delta: {reasoning_text: "**Analyzing the Structure**"}},],
			},
			{
				choices: [
					{
						delta: {
							content: "Okay, I need to check out the project's file structure.",
							reasoning_opaque: "opaque-content-tools",
						},
					},
				],
			},
			{
				choices: [
					{
						finish_reason: "tool_calls",
						delta: {
							tool_calls: [
								{
									index: 0,
									id: "call_MHxqRDd5WVo3NU8wUXRaMmc0MFE",
									fn: {
										name: "list_project_files",
										arguments: "{}",
									},
								},
							],
						},
					},
				],
				usage: {
					prompt_tokens: 3767,
					completion_tokens: 19,
					total_tokens: 3797,
					prompt_tokens_details: {cached_tokens: 0},
					completion_tokens_details: {reasoning_tokens: 11},
				},
			},
		]);

		final reasoningEnd = first(events, CopilotChatStreamEventType.ReasoningEnd);
		final textStart = first(events, CopilotChatStreamEventType.TextStart);
		final toolStart = first(events, CopilotChatStreamEventType.ToolInputStart);
		lt(indexOf(events, reasoningEnd), indexOf(events, textStart), "content tools reasoning before text");
		lt(indexOf(events, textStart), indexOf(events, toolStart), "content tools text before tool");
		eq(reasoningOpaque(reasoningEnd), "opaque-content-tools", "content tools reasoning opaque");
		eq(reasoningOpaque(first(events, CopilotChatStreamEventType.ToolCall)), "opaque-content-tools", "content tools tool opaque");
		eq(first(events, CopilotChatStreamEventType.TextDelta).delta.orNull(), "Okay, I need to check out the project's file structure.",
			"content tools text delta");
		eq(toolStart.id.orNull(), "call_MHxqRDd5WVo3NU8wUXRaMmc0MFE", "content tools call id");
		final finish = first(events, CopilotChatStreamEventType.Finish);
		eq(finishReasonOf(finish).unified, AiFinishReason.ToolCalls, "content tools finish");
		eq(usageOf(finish).inputTokens.total.orNull(), 3767.0, "content tools input usage");
		eq(usageOf(finish).outputTokens.total.orNull(), 19.0, "content tools output usage");
	}

	static function reasoningOpaqueToolCallsWithoutReasoningText():Void {
		final events = CopilotChatStream.collect([
			{
				choices: [
					{
						delta: {
							reasoning_opaque: "opaque-tool-only",
							tool_calls: [
								{
									index: 0,
									id: "call_reasoning_only",
									fn: {
										name: "read_file",
										arguments: "{}",
									},
								},
							],
						},
					},
				],
			},
			{
				choices: [{finish_reason: "tool_calls", delta: {}},],
			},
		]);

		eq(only(events, [
			CopilotChatStreamEventType.ReasoningStart,
			CopilotChatStreamEventType.ReasoningDelta,
			CopilotChatStreamEventType.ReasoningEnd
		]).length, 0, "tool opaque without reasoning has no reasoning events");
		final toolCall = first(events, CopilotChatStreamEventType.ToolCall);
		eq(toolCall.toolCallId.orNull(), "call_reasoning_only", "tool opaque call id");
		eq(toolCall.toolName.orNull(), "read_file", "tool opaque call name");
		eq(reasoningOpaque(toolCall), "opaque-tool-only", "tool opaque metadata");
	}

	static function lateReasoningOpaque():Void {
		final events = CopilotChatStream.collect([
			{
				choices: [{delta: {reasoning_text: "Thinking first"}},],
			},
			{
				choices: [{delta: {content: "Visible answer. "}},],
			},
			{
				choices: [
					{
						finish_reason: "stop",
						delta: {
							content: "Done.",
							reasoning_opaque: "late-opaque",
						},
					},
				],
				usage: {
					prompt_tokens: 5778,
					completion_tokens: 59,
					total_tokens: 5932,
					prompt_tokens_details: {cached_tokens: 0},
					completion_tokens_details: {reasoning_tokens: 95},
				},
			},
		]);

		final reasoningEnd = first(events, CopilotChatStreamEventType.ReasoningEnd);
		eq(reasoningEnd.providerMetadata.orNull() == null, true, "late opaque not on closed reasoning");
		final finish = first(events, CopilotChatStreamEventType.Finish);
		final finishUsage = usageOf(finish);
		eq(reasoningOpaque(finish), "late-opaque", "late opaque on finish");
		eq(finishReasonOf(finish).unified, AiFinishReason.Stop, "late opaque finish");
		eq(finishUsage.inputTokens.total.orNull(), 5778.0, "late opaque prompt");
		eq(finishUsage.outputTokens.total.orNull(), 59.0, "late opaque completion");
	}

	static function errorChunk():Void {
		final events = CopilotChatStream.collect([
			{
				choices: [],
				error: {message: "bad provider chunk"},
			},
		]);
		final error = first(events, CopilotChatStreamEventType.Error);
		eq(error.error.orNull(), "bad provider chunk", "error chunk message");
		final finish = first(events, CopilotChatStreamEventType.Finish);
		eq(finishReasonOf(finish).unified, AiFinishReason.Error, "error chunk finish");
	}

	static function invalidChunks():Void {
		expectInvalid(() -> CopilotChatStream.collect([
			{
				choices: [{delta: {reasoning_opaque: "one"}},],
			},
			{
				choices: [{delta: {reasoning_opaque: "two"}},],
			},
		]), "multiple opaque");

		expectInvalid(() -> CopilotChatStream.collect([
			{
				choices: [
					{
						delta: {
							tool_calls: [
								{
									index: 0,
									fn: {
										name: "read_file",
										arguments: "{}",
									},
								},
							],
						},
					},
				],
			},
		]), "missing tool id");

		expectInvalid(() -> CopilotChatStream.collect([
			{
				choices: [
					{
						delta: {
							tool_calls: [
								{
									index: 0,
									id: "call_missing_name",
									fn: {
										name: null,
										arguments: "{}",
									},
								},
							],
						},
					},
				],
			},
		]), "missing tool name");
	}

	static function emptyUsage():CopilotTokenUsage {
		return {
			prompt_tokens: 0,
			completion_tokens: 0,
			total_tokens: 0,
			prompt_tokens_details: {cached_tokens: 0},
			completion_tokens_details: {reasoning_tokens: 0},
		};
	}

	static function first(events:Array<CopilotChatStreamEvent>, type:CopilotChatStreamEventType):CopilotChatStreamEvent {
		for (event in events) {
			if (event.type == type)
				return event;
		}
		throw 'Missing event ${type}';
	}

	static function only(events:Array<CopilotChatStreamEvent>, types:Array<CopilotChatStreamEventType>):Array<CopilotChatStreamEvent> {
		final result:Array<CopilotChatStreamEvent> = [];
		for (event in events) {
			if (types.indexOf(event.type) >= 0)
				result.push(event);
		}
		return result;
	}

	static function indexOf(events:Array<CopilotChatStreamEvent>, expected:CopilotChatStreamEvent):Int {
		for (i in 0...events.length) {
			if (events[i] == expected)
				return i;
		}
		throw "Event not found";
	}

	static function reasoningOpaque(event:CopilotChatStreamEvent):String {
		final metadata = metadataOf(event);
		final opaque = metadata.copilot.reasoningOpaque.orNull();
		if (opaque == null)
			throw "Expected reasoning opaque metadata";
		return opaque;
	}

	static function metadataOf(event:CopilotChatStreamEvent):CopilotChatStreamProviderMetadata {
		final metadata = event.providerMetadata.orNull();
		if (metadata == null)
			throw "Expected provider metadata";
		return metadata;
	}

	static function usageOf(event:CopilotChatStreamEvent):CopilotMappedStreamUsage {
		final usage = event.usage.orNull();
		if (usage == null)
			throw "Expected stream usage";
		return usage;
	}

	static function finishReasonOf(event:CopilotChatStreamEvent):CopilotMappedFinishReason {
		final finishReason = event.finishReason.orNull();
		if (finishReason == null)
			throw "Expected finish reason";
		return finishReason;
	}

	static function timestampOf(event:CopilotChatStreamEvent):js.lib.Date {
		final timestamp = event.timestamp.orNull();
		if (timestamp == null)
			throw "Expected timestamp";
		return timestamp;
	}

	static function expectInvalid(run:Void->Void, label:String):Void {
		try {
			run();
		} catch (_:CopilotInvalidStreamChunkError) {
			return;
		}
		throw 'Expected invalid stream chunk for ${label}';
	}

	static function lt(actual:Int, expectedUpperBound:Int, label:String):Void {
		if (actual >= expectedUpperBound)
			throw '$label: expected ${actual} to be less than ${expectedUpperBound}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
