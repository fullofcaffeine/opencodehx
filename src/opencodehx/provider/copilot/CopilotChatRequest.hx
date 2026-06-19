package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;

// JSON Schema is an open AI SDK/provider boundary payload. Keep it as Unknown
// here and let schema-owning callers validate or generate narrower structures.
typedef CopilotJsonResponseFormat = {
	final schema:Undefinable<Unknown>;
	final name:Undefinable<String>;
	final description:Undefinable<String>;
}

enum CopilotChatResponseFormat {
	Text;
	Json(options:CopilotJsonResponseFormat);
}

enum abstract CopilotOpenAIResponseFormatType(String) from String to String {
	final JsonObject = "json_object";
	final JsonSchema = "json_schema";
}

typedef CopilotOpenAIJsonSchemaResponseFormat = {
	final schema:Unknown;
	final name:String;
	final description:Undefinable<String>;
}

typedef CopilotOpenAIResponseFormat = {
	final type:CopilotOpenAIResponseFormatType;
	final json_schema:Undefinable<CopilotOpenAIJsonSchemaResponseFormat>;
}

typedef CopilotPreparedResponseFormat = {
	final responseFormat:Undefinable<CopilotOpenAIResponseFormat>;
	final warnings:Array<CopilotChatWarning>;
}

class CopilotChatRequest {
	public static function jsonResponseFormat(?schema:Unknown, ?name:String, ?description:String):CopilotChatResponseFormat {
		return CopilotChatResponseFormat.Json({
			schema: unknownOrAbsent(schema),
			name: stringOrAbsent(name),
			description: stringOrAbsent(description),
		});
	}

	public static function responseFormat(format:Null<CopilotChatResponseFormat>, supportsStructuredOutputs:Bool):CopilotPreparedResponseFormat {
		final warnings:Array<CopilotChatWarning> = [];
		if (format == null || format == CopilotChatResponseFormat.Text) {
			return {
				responseFormat: Undefinable.absent(),
				warnings: warnings,
			};
		}

		return switch format {
			case Json(options):
				final schema = options.schema.orNull();
				if (schema != null && supportsStructuredOutputs) {
					{
						responseFormat: {
							type: CopilotOpenAIResponseFormatType.JsonSchema,
							json_schema: {
								schema: schema,
								name: responseFormatName(options.name),
								description: responseFormatDescription(options.description),
							},
						},
						warnings: warnings,
					};
				} else {
					if (schema != null) {
						warnings.push({
							type: CopilotChatWarningType.Unsupported,
							feature: "responseFormat",
							details: "JSON response format schema is only supported with structuredOutputs",
						});
					}
					{
						responseFormat: {
							type: CopilotOpenAIResponseFormatType.JsonObject,
							json_schema: Undefinable.absent(),
						},
						warnings: warnings,
					};
				}
			case Text:
				{
					responseFormat: Undefinable.absent(),
					warnings: warnings,
				};
		}
	}

	static function responseFormatName(name:Undefinable<String>):String {
		final present = name.orNull();
		if (present == null || present == "")
			return "response";
		return present;
	}

	static function responseFormatDescription(description:Undefinable<String>):Undefinable<String> {
		final present = description.orNull();
		if (present == null)
			return Undefinable.absent();
		return present;
	}

	static function unknownOrAbsent(value:Null<Unknown>):Undefinable<Unknown> {
		if (value == null)
			return Undefinable.absent();
		final present:Unknown = value;
		return present;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		if (value == null)
			return Undefinable.absent();
		final present:String = value;
		return present;
	}
}
