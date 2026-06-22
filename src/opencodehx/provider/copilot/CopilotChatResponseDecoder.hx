package opencodehx.provider.copilot;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.Json;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseBody;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseChoice;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseFunctionCall;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseMessage;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotChatResponseToolCall;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotCompletionTokensDetails;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotPromptTokensDetails;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;

class CopilotInvalidChatResponseError {
	public final message:String;

	public function new(message:String) {
		this.message = message;
	}

	public function toString():String {
		return message;
	}
}

class CopilotChatResponseDecoder {
	public static function decodeResponse(rawValue:String):CopilotChatResponseBody {
		final value = parseJson(rawValue);
		final record = requireRecord(value, "chat response");
		return {
			id: optionalString(record.get("id"), "id"),
			created: optionalNumber(record.get("created"), "created"),
			model: optionalString(record.get("model"), "model"),
			choices: decodeChoices(record.get("choices")),
			usage: decodeUsage(record.get("usage")),
		};
	}

	public static function decodeErrorMessage(rawValue:String, fallback:String):String {
		final parsed = parseJsonOrNull(rawValue);
		if (parsed != null) {
			final record = UnknownNarrow.record(parsed);
			if (record != null) {
				final error = UnknownNarrow.record(record.get("error"));
				if (error != null) {
					final message = UnknownNarrow.string(error.get("message"));
					if (message != null)
						return message;
				}
			}
		}
		return fallback;
	}

	// Runtime JSON decoder boundary: provider responses arrive as untrusted
	// text. Keep parsed values as Unknown, narrow every consumed field, then
	// copy into typed response records.
	static function parseJson(rawValue:String):Unknown {
		try {
			return Unknown.fromBoundary(Json.parse(rawValue));
		} catch (error:haxe.Exception) {
			throw new CopilotInvalidChatResponseError('Invalid Copilot chat JSON response: ${Std.string(error)}');
		}
	}

	static function parseJsonOrNull(rawValue:String):Null<Unknown> {
		try {
			return Unknown.fromBoundary(Json.parse(rawValue));
		} catch (_:haxe.Exception) {
			return null;
		}
	}

	static function decodeChoices(value:Unknown):Array<CopilotChatResponseChoice> {
		final items = UnknownNarrow.array(value);
		if (items == null)
			throw new CopilotInvalidChatResponseError("Expected 'choices' to be an array.");
		final out:Array<CopilotChatResponseChoice> = [];
		for (index in 0...items.length)
			out.push(decodeChoice(items.get(index)));
		return out;
	}

	static function decodeChoice(value:Unknown):CopilotChatResponseChoice {
		final record = requireRecord(value, "choice");
		return {
			message: decodeMessage(record.get("message")),
			finish_reason: optionalString(record.get("finish_reason"), "finish_reason"),
		};
	}

	static function decodeMessage(value:Unknown):CopilotChatResponseMessage {
		final record = requireRecord(value, "message");
		return {
			content: optionalString(record.get("content"), "message.content"),
			reasoning_text: optionalString(record.get("reasoning_text"), "message.reasoning_text"),
			reasoning_opaque: optionalString(record.get("reasoning_opaque"), "message.reasoning_opaque"),
			tool_calls: decodeToolCalls(record.get("tool_calls")),
		};
	}

	static function decodeToolCalls(value:Unknown):Null<Array<CopilotChatResponseToolCall>> {
		if (isAbsent(value))
			return null;
		final items = UnknownNarrow.array(value);
		if (items == null)
			throw new CopilotInvalidChatResponseError("Expected 'message.tool_calls' to be an array.");
		final out:Array<CopilotChatResponseToolCall> = [];
		for (index in 0...items.length)
			out.push(decodeToolCall(items.get(index)));
		return out;
	}

	static function decodeToolCall(value:Unknown):CopilotChatResponseToolCall {
		final record = requireRecord(value, "tool call");
		return {
			id: optionalString(record.get("id"), "tool_call.id"),
			fn: decodeFunction(record.get("function")),
		};
	}

	static function decodeFunction(value:Unknown):CopilotChatResponseFunctionCall {
		final record = requireRecord(value, "tool call function");
		return {
			name: requiredString(record.get("name"), "tool_call.function.name"),
			arguments: requiredString(record.get("arguments"), "tool_call.function.arguments"),
		};
	}

	static function decodeUsage(value:Unknown):Null<CopilotTokenUsage> {
		if (isAbsent(value))
			return null;
		final record = requireRecord(value, "usage");
		return {
			prompt_tokens: optionalNumber(record.get("prompt_tokens"), "usage.prompt_tokens"),
			completion_tokens: optionalNumber(record.get("completion_tokens"), "usage.completion_tokens"),
			total_tokens: optionalNumber(record.get("total_tokens"), "usage.total_tokens"),
			prompt_tokens_details: decodePromptTokensDetails(record.get("prompt_tokens_details")),
			completion_tokens_details: decodeCompletionTokensDetails(record.get("completion_tokens_details")),
		};
	}

	static function decodePromptTokensDetails(value:Unknown):Null<CopilotPromptTokensDetails> {
		if (isAbsent(value))
			return null;
		final record = requireRecord(value, "prompt_tokens_details");
		return {
			cached_tokens: optionalNumber(record.get("cached_tokens"), "prompt_tokens_details.cached_tokens"),
		};
	}

	static function decodeCompletionTokensDetails(value:Unknown):Null<CopilotCompletionTokensDetails> {
		if (isAbsent(value))
			return null;
		final record = requireRecord(value, "completion_tokens_details");
		return {
			reasoning_tokens: optionalNumber(record.get("reasoning_tokens"), "completion_tokens_details.reasoning_tokens"),
			accepted_prediction_tokens: optionalNumber(record.get("accepted_prediction_tokens"), "completion_tokens_details.accepted_prediction_tokens"),
			rejected_prediction_tokens: optionalNumber(record.get("rejected_prediction_tokens"), "completion_tokens_details.rejected_prediction_tokens"),
		};
	}

	static function optionalString(value:Unknown, path:String):Null<String> {
		if (isAbsent(value))
			return null;
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw new CopilotInvalidChatResponseError('Expected ${path} to be a string.');
		return text;
	}

	static function requiredString(value:Unknown, path:String):String {
		final result = optionalString(value, path);
		if (result == null)
			throw new CopilotInvalidChatResponseError('Expected ${path} to be a string.');
		return result;
	}

	static function optionalNumber(value:Unknown, path:String):Null<Float> {
		if (isAbsent(value))
			return null;
		final number = UnknownNarrow.number(value);
		if (number == null)
			throw new CopilotInvalidChatResponseError('Expected ${path} to be a number.');
		return number;
	}

	static function requireRecord(value:Unknown, path:String):UnknownRecord {
		final record = UnknownNarrow.record(value);
		if (record == null)
			throw new CopilotInvalidChatResponseError('Expected ${path} to be an object.');
		return record;
	}

	static function isAbsent(value:Unknown):Bool {
		return UnknownNarrow.isUndefined(value) || UnknownNarrow.isNull(value);
	}
}
