package opencodehx.smoke;

import genes.ts.Undefinable;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.provider.copilot.CopilotChatCompletion;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;

class CopilotChatCompletionSmoke {
	public static function run():Void {
		finishReasons();
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

	static function absent<T>(value:Undefinable<T>, label:String):Void {
		if (value.orNull() != null)
			throw '$label: expected absent value, got ${value.orNull()}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
