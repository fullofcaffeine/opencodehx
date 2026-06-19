package opencodehx.smoke;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import opencodehx.provider.copilot.CopilotChatRequest;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotChatResponseFormat;
import opencodehx.provider.copilot.CopilotChatRequest.CopilotOpenAIResponseFormatType;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatibleRole;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatTool;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatToolChoice;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;
import opencodehx.provider.copilot.CopilotChatTools.CopilotOpenAIToolType;

class CopilotChatRequestSmoke {
	public static function run():Void {
		preparedArgs();
		combinedWarnings();
		streamArgsWithoutUsage();
		streamArgsWithUsage();
		absentForText();
		jsonObjectFormat();
		structuredJsonSchemaFormat();
		unsupportedJsonSchemaWarning();
	}

	static function preparedArgs():Void {
		final input = CopilotChatRequest.options("gemini-2.0-flash-001", [CopilotPromptMessage.User([CopilotPromptPart.Text("Hello")])]);
		input.maxOutputTokens = 128;
		input.temperature = 0.2;
		input.topP = 0.9;
		input.frequencyPenalty = 0.1;
		input.presencePenalty = 0.3;
		input.stopSequences = ["END"];
		input.seed = 42;
		input.providerOptions = CopilotChatRequest.providerOptions("user-123", "high", "low", 4096);
		input.responseFormat = CopilotChatRequest.jsonResponseFormat(schema(), "weather_response");
		input.supportsStructuredOutputs = true;
		input.tools = [weatherTool()];
		input.toolChoice = CopilotChatToolChoice.Tool("get_weather");

		final result = CopilotChatRequest.prepare(input);
		eq(result.warnings.length, 0, "prepared args warnings");
		eq(result.args.model, "gemini-2.0-flash-001", "prepared model");
		eq(result.args.user.orNull(), "user-123", "prepared user");
		eq(result.args.max_tokens.orNull(), 128.0, "prepared max tokens");
		eq(result.args.temperature.orNull(), 0.2, "prepared temperature");
		eq(result.args.top_p.orNull(), 0.9, "prepared top p");
		eq(result.args.frequency_penalty.orNull(), 0.1, "prepared frequency penalty");
		eq(result.args.presence_penalty.orNull(), 0.3, "prepared presence penalty");
		eq(present(result.args.stop, "prepared stop").join(","), "END", "prepared stop");
		eq(result.args.seed.orNull(), 42.0, "prepared seed");
		eq(result.args.reasoning_effort.orNull(), "high", "prepared reasoning effort");
		eq(result.args.verbosity.orNull(), "low", "prepared verbosity");
		eq(result.args.thinking_budget.orNull(), 4096.0, "prepared thinking budget");
		eq(result.args.messages.length, 1, "prepared message count");
		eq(result.args.messages[0].role, OpenAICompatibleRole.User, "prepared message role");
		final responseFormat = present(result.args.response_format, "prepared response format");
		eq(responseFormat.type, CopilotOpenAIResponseFormatType.JsonSchema, "prepared response format type");
		eq(present(responseFormat.json_schema, "prepared response schema").name, "weather_response", "prepared response schema name");
		final tools = present(result.args.tools, "prepared tools");
		eq(tools.length, 1, "prepared tool count");
		eq(tools[0].type, CopilotOpenAIToolType.Function, "prepared tool type");
		eq(tools[0].fn.name, "get_weather", "prepared tool name");
		present(result.args.tool_choice, "prepared tool choice");
	}

	static function combinedWarnings():Void {
		final input = CopilotChatRequest.options("test-model", [CopilotPromptMessage.User([CopilotPromptPart.Text("Hello")])]);
		input.topK = 64;
		input.responseFormat = CopilotChatRequest.jsonResponseFormat(schema());
		input.tools = [CopilotChatTool.Provider];

		final result = CopilotChatRequest.prepare(input);
		eq(result.warnings.length, 3, "combined warning count");
		eq(result.warnings[0].type, CopilotChatWarningType.Unsupported, "topK warning type");
		eq(result.warnings[0].feature, "topK", "topK warning feature");
		eq(result.warnings[1].feature, "responseFormat", "response format warning feature");
		eq(result.warnings[2].feature, "tool type: provider", "provider tool warning feature");
		eq(present(result.args.response_format, "warning response format").type, CopilotOpenAIResponseFormatType.JsonObject,
			"warning response format fallback");
		eq(present(result.args.tools, "provider-only tools").length, 0, "provider-only tools filtered");
	}

	static function streamArgsWithoutUsage():Void {
		final input = CopilotChatRequest.options("stream-model", [CopilotPromptMessage.User([CopilotPromptPart.Text("Stream")])]);
		input.temperature = 0.4;

		final result = CopilotChatRequest.prepareStream(input, false);
		eq(result.warnings.length, 0, "stream warnings");
		eq(result.args.model, "stream-model", "stream model");
		eq(result.args.stream, true, "stream flag");
		absent(result.args.stream_options, "stream options absent");
		eq(result.args.temperature.orNull(), 0.4, "stream temperature");
		eq(result.args.messages.length, 1, "stream message count");
	}

	static function streamArgsWithUsage():Void {
		final input = CopilotChatRequest.options("stream-usage-model", [CopilotPromptMessage.User([CopilotPromptPart.Text("Stream")])]);
		input.topK = 16;

		final result = CopilotChatRequest.prepareStream(input, true);
		eq(result.args.stream, true, "stream usage flag");
		eq(present(result.args.stream_options, "stream options").include_usage, true, "include usage");
		eq(result.warnings.length, 1, "stream retains warnings");
		eq(result.warnings[0].feature, "topK", "stream warning feature");
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

	static function weatherTool():CopilotChatTool {
		return CopilotChatTool.Function({
			name: "get_weather",
			description: "Get the weather for a location",
			inputSchema: schema(),
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
