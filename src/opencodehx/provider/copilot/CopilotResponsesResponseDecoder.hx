package opencodehx.provider.copilot;

import haxe.Json;
import opencodehx.externs.ai.AiSdk.AiJsonValue;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesAnnotation;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesErrorBody;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesIncompleteDetails;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesInputTokensDetails;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesOutputItem;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesOutputText;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesOutputTokensDetails;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesResponseBody;
import opencodehx.provider.copilot.CopilotResponsesCompletion.CopilotResponsesUsage;
import opencodehx.provider.copilot.CopilotResponsesRequest.CopilotResponsesSummaryPart;

class CopilotInvalidResponsesResponseError extends haxe.Exception {}

/**
 * Local JSON decoder for untrusted `/responses` HTTP bodies.
 *
 * Haxe's std JSON parser returns `Dynamic`; this file is the containment
 * boundary for that weak value. Every consumed field is checked before a typed
 * Responses DTO leaves the decoder, so application/model code does not receive
 * raw `Dynamic` values.
 */
class CopilotResponsesResponseDecoder {
	public static function decodeResponse(rawValue:String):CopilotResponsesResponseBody {
		final parsed = parseObject(rawValue, "Responses response");
		return {
			id: requiredString(parsed, "id"),
			created_at: requiredNumber(parsed, "created_at"),
			error: optionalError(field(parsed, "error")),
			model: requiredString(parsed, "model"),
			output: outputArray(field(parsed, "output")),
			service_tier: optionalString(field(parsed, "service_tier")),
			incomplete_details: optionalIncomplete(field(parsed, "incomplete_details")),
			usage: usage(field(parsed, "usage")),
		};
	}

	public static function decodeErrorMessage(rawValue:String, fallback:String):String {
		try {
			final parsed = parseObject(rawValue, "Responses error response");
			final error = field(parsed, "error");
			if (isObject(error)) {
				final message = optionalString(field(error, "message"));
				if (message != null && message != "")
					return message;
			}
		} catch (_:Dynamic) {
			// The provider may return non-JSON error bodies. Keep the original
			// HTTP status text rather than weakening the public error type.
		}
		return fallback;
	}

	static function parseObject(rawValue:String, label:String):Dynamic {
		final parsed:Dynamic = Json.parse(rawValue);
		if (!isObject(parsed) || Std.isOfType(parsed, Array))
			throw new CopilotInvalidResponsesResponseError('${label}: expected object.');
		return parsed;
	}

	static function outputArray(value:Dynamic):Array<CopilotResponsesOutputItem> {
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidResponsesResponseError("Responses response: expected output to be an array.");
		final raw:Array<Dynamic> = value;
		final out:Array<CopilotResponsesOutputItem> = [];
		for (item in raw)
			out.push(outputItem(item));
		return out;
	}

	static function outputItem(value:Dynamic):CopilotResponsesOutputItem {
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses output item: expected object.");
		final type = requiredString(value, "type");
		return {
			type: type,
			role: optionalString(field(value, "role")),
			id: optionalString(field(value, "id")),
			content: optionalOutputTextArray(field(value, "content")),
			call_id: optionalString(field(value, "call_id")),
			name: optionalString(field(value, "name")),
			arguments: optionalString(field(value, "arguments")),
			encrypted_content: optionalString(field(value, "encrypted_content")),
			summary: CopilotResponsesResponseDecoder.summaryArray(field(value, "summary")),
			status: optionalString(field(value, "status")),
			queries: stringArray(field(value, "queries")),
			results: null,
			code: optionalString(field(value, "code")),
			container_id: optionalString(field(value, "container_id")),
			outputs: jsonValueOrNull(field(value, "outputs")),
			result: jsonValueOrNull(field(value, "result")),
			action: jsonValueOrNull(field(value, "action")),
		};
	}

	static function optionalOutputTextArray(value:Dynamic):Array<CopilotResponsesOutputText> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidResponsesResponseError("Responses message content: expected array.");
		final raw:Array<Dynamic> = value;
		final out:Array<CopilotResponsesOutputText> = [];
		for (item in raw)
			out.push(outputText(item));
		return out;
	}

	static function outputText(value:Dynamic):CopilotResponsesOutputText {
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses output text: expected object.");
		return {
			type: requiredString(value, "type"),
			text: requiredString(value, "text"),
			annotations: annotationArray(field(value, "annotations")),
		};
	}

	static function annotationArray(value:Dynamic):Array<CopilotResponsesAnnotation> {
		if (value == null)
			return [];
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidResponsesResponseError("Responses annotations: expected array.");
		final raw:Array<Dynamic> = value;
		final out:Array<CopilotResponsesAnnotation> = [];
		for (item in raw) {
			if (!isObject(item))
				throw new CopilotInvalidResponsesResponseError("Responses annotation: expected object.");
			out.push({
				type: requiredString(item, "type"),
				url: optionalString(field(item, "url")),
				title: optionalString(field(item, "title")),
				file_id: optionalString(field(item, "file_id")),
				filename: optionalString(field(item, "filename")),
				quote: optionalString(field(item, "quote")),
			});
		}
		return out;
	}

	static function summaryArray(value:Dynamic):Array<CopilotResponsesSummaryPart> {
		if (value == null)
			return [];
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidResponsesResponseError("Responses reasoning summary: expected array.");
		final raw:Array<Dynamic> = value;
		final out:Array<CopilotResponsesSummaryPart> = [];
		for (item in raw) {
			if (!isObject(item))
				throw new CopilotInvalidResponsesResponseError("Responses reasoning summary item: expected object.");
			out.push({
				type: requiredString(item, "type"),
				text: requiredString(item, "text"),
			});
		}
		return out;
	}

	static function usage(value:Dynamic):CopilotResponsesUsage {
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses usage: expected object.");
		return {
			input_tokens: requiredNumber(value, "input_tokens"),
			input_tokens_details: inputDetails(field(value, "input_tokens_details")),
			output_tokens: requiredNumber(value, "output_tokens"),
			output_tokens_details: outputDetails(field(value, "output_tokens_details")),
		};
	}

	static function inputDetails(value:Dynamic):Null<CopilotResponsesInputTokensDetails> {
		if (value == null)
			return null;
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses input token details: expected object.");
		return {cached_tokens: optionalNumber(field(value, "cached_tokens"))};
	}

	static function outputDetails(value:Dynamic):Null<CopilotResponsesOutputTokensDetails> {
		if (value == null)
			return null;
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses output token details: expected object.");
		return {reasoning_tokens: optionalNumber(field(value, "reasoning_tokens"))};
	}

	static function optionalIncomplete(value:Dynamic):Null<CopilotResponsesIncompleteDetails> {
		if (value == null)
			return null;
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses incomplete details: expected object.");
		return {reason: optionalString(field(value, "reason"))};
	}

	static function optionalError(value:Dynamic):Null<CopilotResponsesErrorBody> {
		if (value == null)
			return null;
		if (!isObject(value))
			throw new CopilotInvalidResponsesResponseError("Responses error: expected object.");
		return {
			code: requiredString(value, "code"),
			message: requiredString(value, "message"),
		};
	}

	static function stringArray(value:Dynamic):Array<String> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, Array))
			throw new CopilotInvalidResponsesResponseError("Responses string array: expected array.");
		final raw:Array<Dynamic> = value;
		final out:Array<String> = [];
		for (item in raw) {
			if (!Std.isOfType(item, String))
				throw new CopilotInvalidResponsesResponseError("Responses string array: expected string item.");
			final text:String = item;
			out.push(text);
		}
		return out;
	}

	static function requiredString(object:Dynamic, name:String):String {
		final value = field(object, name);
		if (!Std.isOfType(value, String))
			throw new CopilotInvalidResponsesResponseError('Responses field ${name}: expected string.');
		final text:String = value;
		return text;
	}

	static function optionalString(value:Dynamic):Null<String> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, String))
			throw new CopilotInvalidResponsesResponseError("Responses optional field: expected string.");
		final text:String = value;
		return text;
	}

	static function requiredNumber(object:Dynamic, name:String):Float {
		final value = field(object, name);
		if (!Std.isOfType(value, Float) && !Std.isOfType(value, Int))
			throw new CopilotInvalidResponsesResponseError('Responses field ${name}: expected number.');
		final number:Float = value;
		return number;
	}

	static function optionalNumber(value:Dynamic):Null<Float> {
		if (value == null)
			return null;
		if (!Std.isOfType(value, Float) && !Std.isOfType(value, Int))
			throw new CopilotInvalidResponsesResponseError("Responses optional field: expected number.");
		final number:Float = value;
		return number;
	}

	static function jsonValueOrNull(value:Dynamic):Null<AiJsonValue> {
		return value == null ? null : AiJsonValue.fromBoundary(value);
	}

	static function field(object:Dynamic, name:String):Dynamic {
		return Reflect.field(object, name);
	}

	static function isObject(value:Dynamic):Bool {
		return value != null && Reflect.isObject(value);
	}
}
