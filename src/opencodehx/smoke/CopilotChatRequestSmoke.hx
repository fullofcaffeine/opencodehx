package opencodehx.smoke;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import opencodehx.provider.copilot.CopilotChatRequest;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotChatResponseFormat;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotOpenAIResponseFormatType;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;

class CopilotChatRequestSmoke {
	public static function run():Void {
		absentForText();
		jsonObjectFormat();
		structuredJsonSchemaFormat();
		unsupportedJsonSchemaWarning();
	}

	static function absentForText():Void {
		absent(CopilotChatRequest.responseFormat(null, false).responseFormat, "null response format");
		absent(CopilotChatRequest.responseFormat(CopilotChatResponseFormat.Text, true).responseFormat, "text response format");
	}

	static function jsonObjectFormat():Void {
		final result = CopilotChatRequest.responseFormat(CopilotChatRequest.jsonResponseFormat(), false);
		final responseFormat = present(result.responseFormat, "json object response format");
		eq(responseFormat.type, CopilotOpenAIResponseFormatType.JsonObject, "json object type");
		absent(responseFormat.json_schema, "json object schema absent");
		eq(result.warnings.length, 0, "json object warnings");
	}

	static function structuredJsonSchemaFormat():Void {
		final schema = schema();
		final result = CopilotChatRequest.responseFormat(CopilotChatRequest.jsonResponseFormat(schema, "weather_response", "Weather response payload"), true);
		final responseFormat = present(result.responseFormat, "json schema response format");
		eq(responseFormat.type, CopilotOpenAIResponseFormatType.JsonSchema, "json schema type");
		final jsonSchema = present(responseFormat.json_schema, "json schema payload");
		eq(jsonSchema.schema, schema, "json schema preserved");
		eq(jsonSchema.name, "weather_response", "json schema name");
		eq(jsonSchema.description.orNull(), "Weather response payload", "json schema description");

		final defaultName = present(CopilotChatRequest.responseFormat(CopilotChatRequest.jsonResponseFormat(schema), true).responseFormat,
			"default schema response format");
		eq(present(defaultName.json_schema, "default schema payload").name, "response", "json schema default name");
	}

	static function unsupportedJsonSchemaWarning():Void {
		final result = CopilotChatRequest.responseFormat(CopilotChatRequest.jsonResponseFormat(schema()), false);
		final responseFormat = present(result.responseFormat, "unsupported schema response format");
		eq(responseFormat.type, CopilotOpenAIResponseFormatType.JsonObject, "unsupported schema downgrades to json object");
		eq(result.warnings.length, 1, "unsupported schema warning count");
		eq(result.warnings[0].type, CopilotChatWarningType.Unsupported, "unsupported schema warning type");
		eq(result.warnings[0].feature, "responseFormat", "unsupported schema feature");
		eq(result.warnings[0].details.orNull(), "JSON response format schema is only supported with structuredOutputs", "unsupported schema details");
	}

	static function schema():Unknown {
		// Mirrors AI SDK JSON Schema passthrough: the schema object is open
		// boundary data, while the response-format wrapper remains typed.
		return Unknown.fromBoundary({
			type: "object",
			properties: {
				location: {type: "string"},
			},
			required: ["location"],
		});
	}

	static function absent<T>(value:Undefinable<T>, label:String):Void {
		if (value.orNull() != null)
			throw '$label: expected absent value, got ${value.orNull()}';
	}

	static function present<T>(value:Undefinable<T>, label:String):T {
		final unwrapped = value.orNull();
		if (unwrapped == null)
			throw '$label: expected present value';
		return unwrapped;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
