package opencodehx.smoke;

import genes.ts.Undefinable;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseBody;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotGeneratedContent;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotGeneratedContentType;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;

class CopilotChatCompletionSmoke {
	public static function run():Void {
		finishReasons();
		responseMetadata();
		responseContent();
		responseUsage();
		streamUsage();
		predictionMetadata();
	}

	static function finishReasons():Void {
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason("stop"), AiFinishReason.Stop, "stop finish");
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason("length"), AiFinishReason.Length, "length finish");
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason("content_filter"), AiFinishReason.ContentFilter, "content filter finish");
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason("function_call"), AiFinishReason.ToolCalls, "function call finish");
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason("tool_calls"), AiFinishReason.ToolCalls, "tool calls finish");
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason("vendor_specific"), AiFinishReason.Other, "unknown finish");
		eq(CopilotChatCompletion.mapOpenAICompatibleFinishReason(null), AiFinishReason.Other, "null finish");

		final custom = CopilotChatCompletion.finishReason("vendor_specific");
		eq(custom.unified, AiFinishReason.Other, "finish struct unified");
		eq(custom.raw.orNull(), "vendor_specific", "finish struct raw");
		absent(CopilotChatCompletion.finishReason(null).raw, "null finish raw");
	}

	static function responseMetadata():Void {
		final result = CopilotChatCompletion.responseMetadata(sampleResponse());
		eq(result.id.orNull(), "chatcmpl-123", "response metadata id");
		eq(result.modelId.orNull(), "gemini-2.0-flash-001", "response metadata model");
		final timestamp = result.timestamp.orNull();
		if (timestamp == null)
			throw "response metadata timestamp missing";
		eq(timestamp.getTime(), 1677652288000.0, "response metadata timestamp");

		final empty = CopilotChatCompletion.responseMetadata({choices: []});
		absent(empty.id, "empty response metadata id");
		absent(empty.modelId, "empty response metadata model");
		absent(empty.timestamp, "empty response metadata timestamp");
	}

	static function responseContent():Void {
		var generated = 0;
		final result = CopilotChatCompletion.responseContent(sampleResponse(), () -> {
			generated++;
			return 'generated-${generated}';
		});
		eq(result.length, 3, "response content count");
		eq(result[0].type, CopilotGeneratedContentType.Text, "response text type");
		eq(result[0].text.orNull(), "Hello world", "response text");
		eq(reasoningOpaque(result[0]), "opaque-123", "response text metadata");
		eq(result[1].type, CopilotGeneratedContentType.Reasoning, "response reasoning type");
		eq(result[1].text.orNull(), "Thinking...", "response reasoning text");
		eq(reasoningOpaque(result[1]), "opaque-123", "response reasoning metadata");
		eq(result[2].type, CopilotGeneratedContentType.ToolCall, "response tool type");
		eq(result[2].toolCallId.orNull(), "generated-1", "response generated tool id");
		eq(result[2].toolName.orNull(), "read_file", "response tool name");
		eq(result[2].input.orNull(), "{\"filePath\":\"/README.md\"}", "response tool input");
		eq(reasoningOpaque(result[2]), "opaque-123", "response tool metadata");

		final withoutOpaque = CopilotChatCompletion.responseContent({
			choices: [
				{
					message: {
						content: "Plain",
					},
				},
			],
		}, () -> "unused");
		eq(withoutOpaque.length, 1, "plain content count");
		eq(withoutOpaque[0].providerMetadata.orNull() == null, true, "plain content metadata absent");

		final emptyContent = CopilotChatCompletion.responseContent({
			choices: [
				{
					message: {
						content: "",
						reasoning_text: "",
						tool_calls: [],
					},
				},
			],
		}, () -> "unused");
		eq(emptyContent.length, 0, "empty content filtered");
	}

	static function responseUsage():Void {
		final result = CopilotChatCompletion.responseUsage(sampleUsage());
		eq(result.inputTokens.total.orNull(), 19581.0, "response input total");
		absent(result.inputTokens.noCache, "response noCache absent");
		eq(result.inputTokens.cacheRead.orNull(), 17068.0, "response cache read");
		absent(result.inputTokens.cacheWrite, "response cache write absent");
		eq(result.outputTokens.total.orNull(), 53.0, "response output total");
		absent(result.outputTokens.text, "response text absent");
		eq(result.outputTokens.reasoning.orNull(), 12.0, "response reasoning");
		final raw = result.raw.orNull();
		if (raw == null)
			throw "response raw missing";
		eq(raw.total_tokens, 19634.0, "response raw preserved");

		final empty = CopilotChatCompletion.responseUsage(null);
		absent(empty.inputTokens.total, "empty response input");
		absent(empty.outputTokens.total, "empty response output");
		absent(empty.raw, "empty response raw");
	}

	static function streamUsage():Void {
		final result = CopilotChatCompletion.streamUsage(sampleUsage());
		eq(result.inputTokens.total.orNull(), 19581.0, "stream input total");
		eq(result.inputTokens.noCache.orNull(), 2513.0, "stream no cache");
		eq(result.inputTokens.cacheRead.orNull(), 17068.0, "stream cache read");
		absent(result.inputTokens.cacheWrite, "stream cache write absent");
		eq(result.outputTokens.total.orNull(), 53.0, "stream output total");
		absent(result.outputTokens.text, "stream text absent");
		eq(result.outputTokens.reasoning.orNull(), 12.0, "stream reasoning");
		eq(result.raw.prompt_tokens, 19581.0, "stream raw prompt");
		eq(result.raw.completion_tokens, 53.0, "stream raw completion");
		eq(result.raw.total_tokens, 19634.0, "stream raw total");

		final empty = CopilotChatCompletion.streamUsage(null);
		absent(empty.inputTokens.total, "empty stream input");
		eq(empty.raw.prompt_tokens == null, true, "empty stream raw prompt null");
		eq(empty.raw.completion_tokens == null, true, "empty stream raw completion null");
		eq(empty.raw.total_tokens == null, true, "empty stream raw total null");
	}

	static function predictionMetadata():Void {
		final result = CopilotChatCompletion.predictionMetadata(sampleUsage());
		eq(result.acceptedPredictionTokens.orNull(), 7.0, "accepted prediction tokens");
		eq(result.rejectedPredictionTokens.orNull(), 3.0, "rejected prediction tokens");

		final empty = CopilotChatCompletion.predictionMetadata(null);
		absent(empty.acceptedPredictionTokens, "empty accepted prediction tokens");
		absent(empty.rejectedPredictionTokens, "empty rejected prediction tokens");
	}

	static function sampleUsage():CopilotTokenUsage {
		return {
			prompt_tokens: 19581,
			completion_tokens: 53,
			total_tokens: 19634,
			prompt_tokens_details: {
				cached_tokens: 17068,
			},
			completion_tokens_details: {
				reasoning_tokens: 12,
				accepted_prediction_tokens: 7,
				rejected_prediction_tokens: 3,
			},
		};
	}

	static function sampleResponse():CopilotChatResponseBody {
		return {
			id: "chatcmpl-123",
			created: 1677652288,
			model: "gemini-2.0-flash-001",
			choices: [
				{
					message: {
						content: "Hello world",
						reasoning_text: "Thinking...",
						reasoning_opaque: "opaque-123",
						tool_calls: [
							{
								id: null,
								fn: {
									name: "read_file",
									arguments: "{\"filePath\":\"/README.md\"}",
								},
							},
						],
					},
					finish_reason: "tool_calls",
				},
			],
			usage: sampleUsage(),
		};
	}

	static function reasoningOpaque(content:CopilotGeneratedContent):String {
		final metadata = content.providerMetadata.orNull();
		if (metadata == null)
			throw "Expected content provider metadata";
		return metadata.copilot.reasoningOpaque;
	}

	static function absent<T>(value:Undefinable<T>, label:String):Void {
		if (value.orNull() != null)
			throw '$label: expected absent value, got ${value.orNull()}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
