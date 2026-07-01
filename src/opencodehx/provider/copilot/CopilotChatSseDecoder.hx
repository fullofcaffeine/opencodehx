package opencodehx.provider.copilot;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
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
	// only typed stream chunks escape after all consumed fields are checked.
	static function parseJson(rawValue:String):UnknownRecord {
		try {
			final record = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(rawValue)));
			if (record == null)
				throw new CopilotInvalidStreamChunkError("Expected SSE chunk to be an object.");
			return record;
		} catch (error:haxe.Exception) {
			// JSON.parse can throw native JavaScript errors. Catching haxe.Exception
			// wraps that host error without letting it escape the decoder boundary.
			throw new CopilotInvalidStreamChunkError('Invalid SSE JSON chunk: ${Std.string(error)}');
		}
	}

	static function decodeChoices(value:Unknown):Array<CopilotChatStreamChoice> {
		final array = UnknownNarrow.array(value);
		if (array == null)
			throw new CopilotInvalidStreamChunkError("Expected 'choices' to be an array.");
		return decodeChoiceArray(array);
	}

	static function optionalChoices(value:Unknown):Array<CopilotChatStreamChoice> {
		if (isNullish(value))
			return [];
		final array = UnknownNarrow.array(value);
		if (array == null)
			throw new CopilotInvalidStreamChunkError("Expected 'choices' to be an array.");
		return decodeChoiceArray(array);
	}

	static function decodeChoiceArray(items:UnknownArray):Array<CopilotChatStreamChoice> {
		final out:Array<CopilotChatStreamChoice> = [];
		for (index in 0...items.length)
			out.push(decodeChoice(items.get(index)));
		return out;
	}

	static function decodeChoice(value:Unknown):CopilotChatStreamChoice {
		final record = requireRecord(value, "choice");
		return {
			delta: decodeDelta(field(record, "delta")),
			finish_reason: optionalString(field(record, "finish_reason"), "finish_reason"),
		};
	}

	static function decodeDelta(value:Unknown):Null<CopilotChatStreamDelta> {
		if (isNullish(value))
			return null;
		final record = requireRecord(value, "delta");
		return {
			content: optionalString(field(record, "content"), "delta.content"),
			reasoning_text: optionalString(field(record, "reasoning_text"), "delta.reasoning_text"),
			reasoning_opaque: optionalString(field(record, "reasoning_opaque"), "delta.reasoning_opaque"),
			tool_calls: decodeToolCalls(field(record, "tool_calls")),
		};
	}

	static function decodeToolCalls(value:Unknown):Null<Array<CopilotChatStreamToolCallDelta>> {
		if (isNullish(value))
			return null;
		final items = UnknownNarrow.array(value);
		if (items == null)
			throw new CopilotInvalidStreamChunkError("Expected 'delta.tool_calls' to be an array.");
		final out:Array<CopilotChatStreamToolCallDelta> = [];
		for (index in 0...items.length)
			out.push(decodeToolCall(items.get(index)));
		return out;
	}

	static function decodeToolCall(value:Unknown):CopilotChatStreamToolCallDelta {
		final record = requireRecord(value, "tool call");
		return {
			index: requiredInt(field(record, "index"), "tool_calls.index"),
			id: optionalString(field(record, "id"), "tool_calls.id"),
			fn: decodeFunction(field(record, "function")),
		};
	}

	static function decodeFunction(value:Unknown):Null<CopilotChatStreamFunctionDelta> {
		if (isNullish(value))
			return null;
		final record = requireRecord(value, "tool call function");
		return {
			name: optionalString(field(record, "name"), "tool_calls.function.name"),
			arguments: optionalString(field(record, "arguments"), "tool_calls.function.arguments"),
		};
	}

	static function decodeUsage(value:Unknown):Null<CopilotTokenUsage> {
		if (isNullish(value))
			return null;
		final record = requireRecord(value, "usage");
		return {
			prompt_tokens: optionalNumber(field(record, "prompt_tokens"), "usage.prompt_tokens"),
			completion_tokens: optionalNumber(field(record, "completion_tokens"), "usage.completion_tokens"),
			total_tokens: optionalNumber(field(record, "total_tokens"), "usage.total_tokens"),
			prompt_tokens_details: decodePromptTokensDetails(field(record, "prompt_tokens_details")),
			completion_tokens_details: decodeCompletionTokensDetails(field(record, "completion_tokens_details")),
		};
	}

	static function decodePromptTokensDetails(value:Unknown):Null<CopilotPromptTokensDetails> {
		if (isNullish(value))
			return null;
		final record = requireRecord(value, "prompt_tokens_details");
		return {
			cached_tokens: optionalNumber(field(record, "cached_tokens"), "prompt_tokens_details.cached_tokens"),
		};
	}

	static function decodeCompletionTokensDetails(value:Unknown):Null<CopilotCompletionTokensDetails> {
		if (isNullish(value))
			return null;
		final record = requireRecord(value, "completion_tokens_details");
		return {
			reasoning_tokens: optionalNumber(field(record, "reasoning_tokens"), "completion_tokens_details.reasoning_tokens"),
			accepted_prediction_tokens: optionalNumber(field(record, "accepted_prediction_tokens"), "completion_tokens_details.accepted_prediction_tokens"),
			rejected_prediction_tokens: optionalNumber(field(record, "rejected_prediction_tokens"), "completion_tokens_details.rejected_prediction_tokens"),
		};
	}

	static function decodeError(value:Unknown):Null<CopilotChatStreamError> {
		if (isNullish(value))
			return null;
		final record = requireRecord(value, "error");
		return {
			message: requiredString(field(record, "message"), "error.message"),
		};
	}

	static function optionalString(value:Unknown, path:String):Null<String> {
		if (isNullish(value))
			return null;
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a string.');
		return text;
	}

	static function requiredString(value:Unknown, path:String):String {
		final result = optionalString(value, path);
		if (result == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a string.');
		return result;
	}

	static function optionalNumber(value:Unknown, path:String):Null<Float> {
		if (isNullish(value))
			return null;
		final number = UnknownNarrow.number(value);
		if (number == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a number.');
		return number;
	}

	static function requiredInt(value:Unknown, path:String):Int {
		final number = optionalNumber(value, path);
		if (number == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be a number.');
		final present:Float = number;
		if (present != Math.floor(present))
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be an integer.');
		return Std.int(present);
	}

	static function requireRecord(value:Unknown, path:String):UnknownRecord {
		final record = UnknownNarrow.record(value);
		if (record == null)
			throw new CopilotInvalidStreamChunkError('Expected ${path} to be an object.');
		return record;
	}

	static function field(value:UnknownRecord, name:String):Unknown {
		return value.get(name);
	}

	static function isNullish(value:Unknown):Bool {
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value);
	}
}
