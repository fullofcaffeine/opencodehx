package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import opencodehx.externs.ai.AiSdk.AiFinishReason;

typedef CopilotPromptTokensDetails = {
	@:optional final cached_tokens:Null<Float>;
}

typedef CopilotCompletionTokensDetails = {
	@:optional final reasoning_tokens:Null<Float>;
	@:optional final accepted_prediction_tokens:Null<Float>;
	@:optional final rejected_prediction_tokens:Null<Float>;
}

typedef CopilotTokenUsage = {
	@:optional final prompt_tokens:Null<Float>;
	@:optional final completion_tokens:Null<Float>;
	@:optional final total_tokens:Null<Float>;
	@:optional final prompt_tokens_details:Null<CopilotPromptTokensDetails>;
	@:optional final completion_tokens_details:Null<CopilotCompletionTokensDetails>;
}

typedef CopilotMappedFinishReason = {
	final unified:AiFinishReason;
	final raw:Undefinable<String>;
}

typedef CopilotMappedInputTokens = {
	final total:Undefinable<Float>;
	final noCache:Undefinable<Float>;
	final cacheRead:Undefinable<Float>;
	final cacheWrite:Undefinable<Float>;
}

typedef CopilotMappedOutputTokens = {
	final total:Undefinable<Float>;
	final text:Undefinable<Float>;
	final reasoning:Undefinable<Float>;
}

typedef CopilotMappedResponseUsage = {
	final inputTokens:CopilotMappedInputTokens;
	final outputTokens:CopilotMappedOutputTokens;
	final raw:Undefinable<CopilotTokenUsage>;
}

typedef CopilotStreamRawUsage = {
	final prompt_tokens:Null<Float>;
	final completion_tokens:Null<Float>;
	final total_tokens:Null<Float>;
}

typedef CopilotMappedStreamUsage = {
	final inputTokens:CopilotMappedInputTokens;
	final outputTokens:CopilotMappedOutputTokens;
	final raw:CopilotStreamRawUsage;
}

typedef CopilotPredictionMetadata = {
	final acceptedPredictionTokens:Undefinable<Float>;
	final rejectedPredictionTokens:Undefinable<Float>;
}

class CopilotChatCompletion {
	public static function mapOpenAICompatibleFinishReason(finishReason:Null<String>):AiFinishReason {
		return switch finishReason {
			case "stop":
				AiFinishReason.Stop;
			case "length":
				AiFinishReason.Length;
			case "content_filter":
				AiFinishReason.ContentFilter;
			case "function_call" | "tool_calls":
				AiFinishReason.ToolCalls;
			case _:
				AiFinishReason.Other;
		}
	}

	public static function finishReason(finishReason:Null<String>):CopilotMappedFinishReason {
		return {
			unified: mapOpenAICompatibleFinishReason(finishReason),
			raw: stringOrAbsent(finishReason),
		};
	}

	public static function responseUsage(usage:Null<CopilotTokenUsage>):CopilotMappedResponseUsage {
		final prompt = promptTokens(usage);
		final cached = cachedTokens(usage);
		final completion = completionTokens(usage);
		final reasoning = reasoningTokens(usage);
		final inputTokens:CopilotMappedInputTokens = {
			total: numberOrAbsent(prompt),
			noCache: Undefinable.absent(),
			cacheRead: numberOrAbsent(cached),
			cacheWrite: Undefinable.absent(),
		};
		final outputTokens:CopilotMappedOutputTokens = {
			total: numberOrAbsent(completion),
			text: Undefinable.absent(),
			reasoning: numberOrAbsent(reasoning),
		};
		return {
			inputTokens: inputTokens,
			outputTokens: outputTokens,
			raw: usageOrAbsent(usage),
		};
	}

	public static function streamUsage(usage:Null<CopilotTokenUsage>):CopilotMappedStreamUsage {
		final prompt = promptTokens(usage);
		final cached = cachedTokens(usage);
		final completion = completionTokens(usage);
		final total = totalTokens(usage);
		final reasoning = reasoningTokens(usage);
		final noCache:Null<Float> = prompt != null && cached != null ? prompt - cached : null;
		final inputTokens:CopilotMappedInputTokens = {
			total: numberOrAbsent(prompt),
			noCache: numberOrAbsent(noCache),
			cacheRead: numberOrAbsent(cached),
			cacheWrite: Undefinable.absent(),
		};
		final outputTokens:CopilotMappedOutputTokens = {
			total: numberOrAbsent(completion),
			text: Undefinable.absent(),
			reasoning: numberOrAbsent(reasoning),
		};
		final raw:CopilotStreamRawUsage = {
			prompt_tokens: prompt,
			completion_tokens: completion,
			total_tokens: total,
		};

		return {
			inputTokens: inputTokens,
			outputTokens: outputTokens,
			raw: raw,
		};
	}

	public static function predictionMetadata(usage:Null<CopilotTokenUsage>):CopilotPredictionMetadata {
		return {
			acceptedPredictionTokens: numberOrAbsent(acceptedPredictionTokens(usage)),
			rejectedPredictionTokens: numberOrAbsent(rejectedPredictionTokens(usage)),
		};
	}

	static function promptTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		return usage == null ? null : usage.prompt_tokens;
	}

	static function completionTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		return usage == null ? null : usage.completion_tokens;
	}

	static function totalTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		return usage == null ? null : usage.total_tokens;
	}

	static function cachedTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		final details:Null<CopilotPromptTokensDetails> = usage == null ? null : usage.prompt_tokens_details;
		return details == null ? null : details.cached_tokens;
	}

	static function reasoningTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		final details:Null<CopilotCompletionTokensDetails> = usage == null ? null : usage.completion_tokens_details;
		return details == null ? null : details.reasoning_tokens;
	}

	static function acceptedPredictionTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		final details:Null<CopilotCompletionTokensDetails> = usage == null ? null : usage.completion_tokens_details;
		return details == null ? null : details.accepted_prediction_tokens;
	}

	static function rejectedPredictionTokens(usage:Null<CopilotTokenUsage>):Null<Float> {
		final details:Null<CopilotCompletionTokensDetails> = usage == null ? null : usage.completion_tokens_details;
		return details == null ? null : details.rejected_prediction_tokens;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		if (value == null)
			return Undefinable.absent();
		final present:Float = value;
		return present;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		if (value == null)
			return Undefinable.absent();
		final present:String = value;
		return present;
	}

	static function usageOrAbsent(value:Null<CopilotTokenUsage>):Undefinable<CopilotTokenUsage> {
		if (value == null)
			return Undefinable.absent();
		final present:CopilotTokenUsage = value;
		return present;
	}
}
