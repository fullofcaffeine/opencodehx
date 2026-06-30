package opencodehx.provider.copilot;

import genes.ts.Unknown;
import genes.ts.JsonCodec;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
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
			final errorRecord = optionalObject(error);
			if (errorRecord != null) {
				final message = optionalString(field(errorRecord, "message"));
				if (message != null && message != "")
					return message;
			}
		} catch (_:Dynamic) {
			// The provider may return non-JSON error bodies. Keep the original
			// HTTP status text rather than weakening the public error type.
		}
		return fallback;
	}

	static function parseObject(rawValue:String, label:String):UnknownRecord {
		final parsed = Unknown.fromBoundary(Json.parse(rawValue));
		final record = optionalObject(parsed);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError('${label}: expected object.');
		return record;
	}

	static function outputArray(value:Unknown):Array<CopilotResponsesOutputItem> {
		final raw = UnknownNarrow.array(value);
		if (raw == null)
			throw new CopilotInvalidResponsesResponseError("Responses response: expected output to be an array.");
		final out:Array<CopilotResponsesOutputItem> = [];
		for (index in 0...raw.length)
			out.push(outputItem(raw.get(index)));
		return out;
	}

	static function outputItem(value:Unknown):CopilotResponsesOutputItem {
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses output item: expected object.");
		final type = requiredString(record, "type");
		return {
			type: type,
			role: optionalString(field(record, "role")),
			id: optionalString(field(record, "id")),
			content: optionalOutputTextArray(field(record, "content")),
			call_id: optionalString(field(record, "call_id")),
			name: optionalString(field(record, "name")),
			arguments: optionalString(field(record, "arguments")),
			encrypted_content: optionalString(field(record, "encrypted_content")),
			summary: CopilotResponsesResponseDecoder.summaryArray(field(record, "summary")),
			status: optionalString(field(record, "status")),
			queries: stringArray(field(record, "queries")),
			results: null,
			code: optionalString(field(record, "code")),
			container_id: optionalString(field(record, "container_id")),
			outputs: jsonValueOrNull(field(record, "outputs")),
			result: jsonValueOrNull(field(record, "result")),
			action: jsonValueOrNull(field(record, "action")),
		};
	}

	static function optionalOutputTextArray(value:Unknown):Array<CopilotResponsesOutputText> {
		if (isNullish(value))
			return null;
		final raw = UnknownNarrow.array(value);
		if (raw == null)
			throw new CopilotInvalidResponsesResponseError("Responses message content: expected array.");
		final out:Array<CopilotResponsesOutputText> = [];
		for (index in 0...raw.length)
			out.push(outputText(raw.get(index)));
		return out;
	}

	static function outputText(value:Unknown):CopilotResponsesOutputText {
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses output text: expected object.");
		return {
			type: requiredString(record, "type"),
			text: requiredString(record, "text"),
			annotations: annotationArray(field(record, "annotations")),
		};
	}

	static function annotationArray(value:Unknown):Array<CopilotResponsesAnnotation> {
		if (isNullish(value))
			return [];
		final raw = UnknownNarrow.array(value);
		if (raw == null)
			throw new CopilotInvalidResponsesResponseError("Responses annotations: expected array.");
		final out:Array<CopilotResponsesAnnotation> = [];
		for (index in 0...raw.length) {
			final item = optionalObject(raw.get(index));
			if (item == null)
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

	static function summaryArray(value:Unknown):Array<CopilotResponsesSummaryPart> {
		if (isNullish(value))
			return [];
		final raw = UnknownNarrow.array(value);
		if (raw == null)
			throw new CopilotInvalidResponsesResponseError("Responses reasoning summary: expected array.");
		final out:Array<CopilotResponsesSummaryPart> = [];
		for (index in 0...raw.length) {
			final item = optionalObject(raw.get(index));
			if (item == null)
				throw new CopilotInvalidResponsesResponseError("Responses reasoning summary item: expected object.");
			out.push({
				type: requiredString(item, "type"),
				text: requiredString(item, "text"),
			});
		}
		return out;
	}

	static function usage(value:Unknown):CopilotResponsesUsage {
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses usage: expected object.");
		return {
			input_tokens: requiredNumber(record, "input_tokens"),
			input_tokens_details: inputDetails(field(record, "input_tokens_details")),
			output_tokens: requiredNumber(record, "output_tokens"),
			output_tokens_details: outputDetails(field(record, "output_tokens_details")),
		};
	}

	static function inputDetails(value:Unknown):Null<CopilotResponsesInputTokensDetails> {
		if (isNullish(value))
			return null;
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses input token details: expected object.");
		return {cached_tokens: optionalNumber(field(record, "cached_tokens"))};
	}

	static function outputDetails(value:Unknown):Null<CopilotResponsesOutputTokensDetails> {
		if (isNullish(value))
			return null;
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses output token details: expected object.");
		return {reasoning_tokens: optionalNumber(field(record, "reasoning_tokens"))};
	}

	static function optionalIncomplete(value:Unknown):Null<CopilotResponsesIncompleteDetails> {
		if (isNullish(value))
			return null;
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses incomplete details: expected object.");
		return {reason: optionalString(field(record, "reason"))};
	}

	static function optionalError(value:Unknown):Null<CopilotResponsesErrorBody> {
		if (isNullish(value))
			return null;
		final record = optionalObject(value);
		if (record == null)
			throw new CopilotInvalidResponsesResponseError("Responses error: expected object.");
		return {
			code: requiredString(record, "code"),
			message: requiredString(record, "message"),
		};
	}

	static function stringArray(value:Unknown):Array<String> {
		if (isNullish(value))
			return null;
		final raw = UnknownNarrow.array(value);
		if (raw == null)
			throw new CopilotInvalidResponsesResponseError("Responses string array: expected array.");
		final out:Array<String> = [];
		for (index in 0...raw.length) {
			final text = UnknownNarrow.string(raw.get(index));
			if (text == null)
				throw new CopilotInvalidResponsesResponseError("Responses string array: expected string item.");
			out.push(text);
		}
		return out;
	}

	static function requiredString(object:UnknownRecord, name:String):String {
		final value = field(object, name);
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw new CopilotInvalidResponsesResponseError('Responses field ${name}: expected string.');
		return text;
	}

	static function optionalString(value:Unknown):Null<String> {
		if (isNullish(value))
			return null;
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw new CopilotInvalidResponsesResponseError("Responses optional field: expected string.");
		return text;
	}

	static function requiredNumber(object:UnknownRecord, name:String):Float {
		final value = field(object, name);
		final number = UnknownNarrow.number(value);
		if (number == null)
			throw new CopilotInvalidResponsesResponseError('Responses field ${name}: expected number.');
		return number;
	}

	static function optionalNumber(value:Unknown):Null<Float> {
		if (isNullish(value))
			return null;
		final number = UnknownNarrow.number(value);
		if (number == null)
			throw new CopilotInvalidResponsesResponseError("Responses optional field: expected number.");
		return number;
	}

	static function jsonValueOrNull(value:Unknown):Null<AiJsonValue> {
		if (isNullish(value))
			return null;
		final json = JsonCodec.narrow(value);
		if (json == null)
			throw new CopilotInvalidResponsesResponseError("Responses JSON field: expected JSON-compatible value.");
		return AiJsonValue.fromJson(json);
	}

	static function field(object:UnknownRecord, name:String):Unknown {
		return object.get(name);
	}

	static function optionalObject(value:Unknown):Null<UnknownRecord> {
		return UnknownNarrow.record(value);
	}

	static function isNullish(value:Unknown):Bool {
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value);
	}
}
