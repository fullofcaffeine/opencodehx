package opencodehx.provider.copilot;

import haxe.Json;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotCompletionTokensDetails;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotPromptTokensDetails;
import opencodehx.provider.copilot.CopilotChatCompletion.CopilotTokenUsage;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatRawStreamChunk;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamChoice;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamChunk;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamDelta;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamError;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamFunctionDelta;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamToolCallDelta;
import opencodehx.provider.copilot.CopilotChatStream.CopilotInvalidStreamChunkError;

using StringTools;

class CopilotChatSseDecoder {
	public static function decodeText(text:String):Array<CopilotChatRawStreamChunk> {
		final out:Array<CopilotChatRawStreamChunk> = [];
		for (data in dataFrames(text)) {
			if (data == "" || data == "[DONE]")
				continue;
			out.push({
				rawValue: data,
				chunk: decodeChunk(data),
			});
		}
		return out;
	}

	public static function decodeChunk(rawValue:String):CopilotChatStreamChunk {
		final value = parseJson(rawValue);
		requireRecord(value, "SSE chunk");
		final error = decodeError(field(value, "error"));
		return {
			id: optionalString(field(value, "id"), "id"),
			created: optionalNumber(field(value, "created"), "created"),
			model: optionalString(field(value, "model"), "model"),
			choices: error == null ? decodeChoices(field(value, "choices")) : optionalChoices(field(value, "choices")),
			usage: decodeUsage(field(value, "usage")),
			error: error,
		};
	}

	static function dataFrames(text:String):Array<String> {
		final frames:Array<String> = [];
		final lines = text.split("\n");
		final current:Array<String> = [];
		for (rawLine in lines) {
			final line = rawLine.endsWith("\r") ? rawLine.substr(0, rawLine.length - 1) : rawLine;
			if (line == "") {
				flushFrame(current, frames);
				continue;
			}
			if (line.startsWith(":"))
				continue;
			if (!line.startsWith("data:"))
				continue;
			var data = line.substr("data:".length);
			if (data.startsWith(" "))
				data = data.substr(1);
			current.push(data);
		}
		flushFrame(current, frames);
		return frames;
	}

	static function flushFrame(current:Array<String>, frames:Array<String>):Void {
		if (current.length == 0)
			return;
		frames.push(current.join("\n"));
		current.resize(0);
	}

	// Runtime JSON decoder boundary: SSE chunks arrive as untrusted text and
	// Haxe's Json/Reflect APIs expose parsed values as Dynamic. The weak reads
	// below are private, shape-checked, and only typed stream chunks escape.
	static function parseJson(rawValue:String):Dynamic {
		try {
			return Json.parse(rawValue);
		} catch (error:haxe.Exception) {
			// JSON.parse can throw native JavaScript errors. Catching haxe.Exception
			// wraps that host error without letting it escape the decoder boundary.
			throw new CopilotInvalidStreamChunkError('Invalid SSE JSON chunk: ${Std.string(error)}');
		}
	}

	static function decodeChoices(value:Dynamic):Array<CopilotChatStreamChoice> {
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidStreamChunkError("Expected 'choices' to be an array.");
		return decodeChoiceArray(value);
	}

	static function optionalChoices(value:Dynamic):Array<CopilotChatStreamChoice> {
		if (value == null)
			return [];
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidStreamChunkError("Expected 'choices' to be an array.");
		return decodeChoiceArray(value);
	}

	static function decodeChoiceArray(value:Dynamic):Array<CopilotChatStreamChoice> {
		// Json.parse returns erased arrays. The guard before this call proves the
		// container shape; this cast stays inside the decoder while elements are
		// converted into typed records.
		final items:Array<Dynamic> = cast value;
		final out:Array<CopilotChatStreamChoice> = [];
		for (item in items)
			out.push(decodeChoice(item));
		return out;
	}

	static function decodeChoice(value:Dynamic):CopilotChatStreamChoice {
		requireRecord(value, "choice");
		return {
			delta: decodeDelta(field(value, "delta")),
			finish_reason: optionalString(field(value, "finish_reason"), "finish_reason"),
		};
	}

	static function decodeDelta(value:Dynamic):Null<CopilotChatStreamDelta> {
		if (value == null)
			return null;
		requireRecord(value, "delta");
		return {
			content: optionalString(field(value, "content"), "delta.content"),
			reasoning_text: optionalString(field(value, "reasoning_text"), "delta.reasoning_text"),
			reasoning_opaque: optionalString(field(value, "reasoning_opaque"), "delta.reasoning_opaque"),
			tool_calls: decodeToolCalls(field(value, "tool_calls")),
		};
	}

	static function decodeToolCalls(value:Dynamic):Null<Array<CopilotChatStreamToolCallDelta>> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidStreamChunkError("Expected 'delta.tool_calls' to be an array.");
		// Json.parse returns erased arrays. The guard above proves the container
		// shape; each element is still checked before it becomes a typed delta.
		final items:Array<Dynamic> = cast value;
		final out:Array<CopilotChatStreamToolCallDelta> = [];
		for (item in items)
			out.push(decodeToolCall(item));
		return out;
	}

	static function decodeToolCall(value:Dynamic):CopilotChatStreamToolCallDelta {
		requireRecord(value, "tool call");
		return {
			index: requiredInt(field(value, "index"), "tool_calls.index"),
			id: optionalString(field(value, "id"), "tool_calls.id"),
			fn: decodeFunction(field(value, "function")),
		};
	}

	static function decodeFunction(value:Dynamic):Null<CopilotChatStreamFunctionDelta> {
		if (value == null)
			return null;
		requireRecord(value, "tool call function");
		return {
			name: optionalString(field(value, "name"), "tool_calls.function.name"),
			arguments: optionalString(field(value, "arguments"), "tool_calls.function.arguments"),
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

	static function decodeError(value:Dynamic):Null<CopilotChatStreamError> {
		if (value == null)
			return null;
		requireRecord(value, "error");
		return {
			message: requiredString(field(value, "message"), "error.message"),
		};
	}

	static function optionalString(value:Dynamic, path:String):Null<String> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, String))
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a string.');
		return value;
	}

	static function requiredString(value:Dynamic, path:String):String {
		final result = optionalString(value, path);
		if (result == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a string.');
		return result;
	}

	static function optionalNumber(value:Dynamic, path:String):Null<Float> {
		if (value == null)
			return null;
		if (!isNumber(value))
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a number.');
		return value;
	}

	static function requiredInt(value:Dynamic, path:String):Int {
		final number = optionalNumber(value, path);
		if (number == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a number.');
		final present:Float = number;
		if (present != Math.floor(present))
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be an integer.');
		return Std.int(present);
	}

	static function requireRecord(value:Dynamic, path:String):Void {
		if (!isRecord(value))
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be an object.');
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
