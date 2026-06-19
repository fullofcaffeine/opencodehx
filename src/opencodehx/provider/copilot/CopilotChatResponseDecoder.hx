package opencodehx.provider.copilot;

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
		requireRecord(value, "chat response");
		return {
			id: optionalString(field(value, "id"), "id"),
			created: optionalNumber(field(value, "created"), "created"),
			model: optionalString(field(value, "model"), "model"),
			choices: decodeChoices(field(value, "choices")),
			usage: decodeUsage(field(value, "usage")),
		};
	}

	public static function decodeErrorMessage(rawValue:String, fallback:String):String {
		final parsed = parseJsonOrNull(rawValue);
		if (isRecord(parsed)) {
			final error = field(parsed, "error");
			if (isRecord(error)) {
				final message = field(error, "message");
				if (Std.isOfType(message, String))
					return message;
			}
		}
		return fallback;
	}

	// Runtime JSON decoder boundary: provider responses arrive as untrusted text
	// and Haxe's Json/Reflect APIs expose parsed values as Dynamic. The weak
	// reads below are private, shape-checked, and only typed response records or
	// explicit decoder errors escape.
	static function parseJson(rawValue:String):Dynamic {
		try {
			return Json.parse(rawValue);
		} catch (error:haxe.Exception) {
			throw new CopilotInvalidChatResponseError('Invalid Copilot chat JSON response: ${Std.string(error)}');
		}
	}

	static function parseJsonOrNull(rawValue:String):Dynamic {
		try {
			return Json.parse(rawValue);
		} catch (_:haxe.Exception) {
			return null;
		}
	}

	static function decodeChoices(value:Dynamic):Array<CopilotChatResponseChoice> {
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidChatResponseError("Expected 'choices' to be an array.");
		// Json.parse returns erased arrays. The guard above proves the container
		// shape; each element is checked before becoming a typed choice.
		final items:Array<Dynamic> = cast value;
		final out:Array<CopilotChatResponseChoice> = [];
		for (item in items)
			out.push(decodeChoice(item));
		return out;
	}

	static function decodeChoice(value:Dynamic):CopilotChatResponseChoice {
		requireRecord(value, "choice");
		return {
			message: decodeMessage(field(value, "message")),
			finish_reason: optionalString(field(value, "finish_reason"), "finish_reason"),
		};
	}

	static function decodeMessage(value:Dynamic):CopilotChatResponseMessage {
		requireRecord(value, "message");
		return {
			content: optionalString(field(value, "content"), "message.content"),
			reasoning_text: optionalString(field(value, "reasoning_text"), "message.reasoning_text"),
			reasoning_opaque: optionalString(field(value, "reasoning_opaque"), "message.reasoning_opaque"),
			tool_calls: decodeToolCalls(field(value, "tool_calls")),
		};
	}

	static function decodeToolCalls(value:Dynamic):Null<Array<CopilotChatResponseToolCall>> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidChatResponseError("Expected 'message.tool_calls' to be an array.");
		// Json.parse returns erased arrays. The guard above proves the container
		// shape; each tool call is checked before becoming a typed record.
		final items:Array<Dynamic> = cast value;
		final out:Array<CopilotChatResponseToolCall> = [];
		for (item in items)
			out.push(decodeToolCall(item));
		return out;
	}

	static function decodeToolCall(value:Dynamic):CopilotChatResponseToolCall {
		requireRecord(value, "tool call");
		return {
			id: optionalString(field(value, "id"), "tool_call.id"),
			fn: decodeFunction(field(value, "function")),
		};
	}

	static function decodeFunction(value:Dynamic):CopilotChatResponseFunctionCall {
		requireRecord(value, "tool call function");
		return {
			name: requiredString(field(value, "name"), "tool_call.function.name"),
			arguments: requiredString(field(value, "arguments"), "tool_call.function.arguments"),
		};
	}

	static function decodeUsage(value:Dynamic):Null<CopilotTokenUsage> {
		if (value == null)
			return null;
		requireRecord(value, "usage");
		return {
			prompt_tokens: optionalNumber(field(value, "prompt_tokens"), "usage.prompt_tokens"),
			completion_tokens: optionalNumber(field(value, "completion_tokens"), "usage.completion_tokens"),
			total_tokens: optionalNumber(field(value, "total_tokens"), "usage.total_tokens"),
			prompt_tokens_details: decodePromptTokensDetails(field(value, "prompt_tokens_details")),
			completion_tokens_details: decodeCompletionTokensDetails(field(value, "completion_tokens_details")),
		};
	}

	static function decodePromptTokensDetails(value:Dynamic):Null<CopilotPromptTokensDetails> {
		if (value == null)
			return null;
		requireRecord(value, "prompt_tokens_details");
		return {
			cached_tokens: optionalNumber(field(value, "cached_tokens"), "prompt_tokens_details.cached_tokens"),
		};
	}

	static function decodeCompletionTokensDetails(value:Dynamic):Null<CopilotCompletionTokensDetails> {
		if (value == null)
			return null;
		requireRecord(value, "completion_tokens_details");
		return {
			reasoning_tokens: optionalNumber(field(value, "reasoning_tokens"), "completion_tokens_details.reasoning_tokens"),
			accepted_prediction_tokens: optionalNumber(field(value, "accepted_prediction_tokens"), "completion_tokens_details.accepted_prediction_tokens"),
			rejected_prediction_tokens: optionalNumber(field(value, "rejected_prediction_tokens"), "completion_tokens_details.rejected_prediction_tokens"),
		};
	}

	static function optionalString(value:Dynamic, path:String):Null<String> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, String))
			throw new CopilotInvalidChatResponseError('Expected ${path} to be a string.');
		return value;
	}

	static function requiredString(value:Dynamic, path:String):String {
		final result = optionalString(value, path);
		if (result == null)
			throw new CopilotInvalidChatResponseError('Expected ${path} to be a string.');
		return result;
	}

	static function optionalNumber(value:Dynamic, path:String):Null<Float> {
		if (value == null)
			return null;
		if (!isNumber(value))
			throw new CopilotInvalidChatResponseError('Expected ${path} to be a number.');
		return value;
	}

	static function requireRecord(value:Dynamic, path:String):Void {
		if (!isRecord(value))
			throw new CopilotInvalidChatResponseError('Expected ${path} to be an object.');
	}

	static function field(value:Dynamic, name:String):Dynamic {
		return Reflect.field(value, name);
	}

	static function isRecord(value:Dynamic):Bool {
		if (value == null
			|| Std.isOfType(value, Array)
			|| Std.isOfType(value, String)
			|| Std.isOfType(value, Bool)
			|| isNumber(value))
			return false;
		return Reflect.isObject(value);
	}

	static function isNumber(value:Dynamic):Bool {
		return Std.isOfType(value, Int) || Std.isOfType(value, Float);
	}
}
