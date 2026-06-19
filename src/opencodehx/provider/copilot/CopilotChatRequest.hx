package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import opencodehx.provider.copilot.CopilotChatMessages;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.OpenAICompatibleMessage;
import opencodehx.provider.copilot.CopilotChatTools;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatTool;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatToolChoice;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;
import opencodehx.provider.copilot.CopilotChatTools.CopilotOpenAITool;
import opencodehx.provider.copilot.CopilotChatTools.CopilotPreparedToolChoice;

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

typedef CopilotCompatibleProviderOptions = {
	final user:Undefinable<String>;
	final reasoningEffort:Undefinable<String>;
	final textVerbosity:Undefinable<String>;
	final thinkingBudget:Undefinable<Float>;
}

typedef CopilotChatRequestOptions = {
	final modelId:String;
	final prompt:Array<CopilotPromptMessage>;
	var maxOutputTokens:Undefinable<Float>;
	var temperature:Undefinable<Float>;
	var topP:Undefinable<Float>;
	var topK:Undefinable<Float>;
	var frequencyPenalty:Undefinable<Float>;
	var presencePenalty:Undefinable<Float>;
	var stopSequences:Undefinable<Array<String>>;
	var seed:Undefinable<Float>;
	var responseFormat:Null<CopilotChatResponseFormat>;
	var supportsStructuredOutputs:Bool;
	var providerOptions:CopilotCompatibleProviderOptions;
	var tools:Array<CopilotChatTool>;
	var toolChoice:Null<CopilotChatToolChoice>;
}

typedef CopilotOpenAIChatArgs = {
	final model:String;
	final user:Undefinable<String>;
	final max_tokens:Undefinable<Float>;
	final temperature:Undefinable<Float>;
	final top_p:Undefinable<Float>;
	final frequency_penalty:Undefinable<Float>;
	final presence_penalty:Undefinable<Float>;
	final response_format:Undefinable<CopilotOpenAIResponseFormat>;
	final stop:Undefinable<Array<String>>;
	final seed:Undefinable<Float>;
	final messages:Array<OpenAICompatibleMessage>;
	final tools:Undefinable<Array<CopilotOpenAITool>>;
	final tool_choice:Undefinable<CopilotPreparedToolChoice>;
	final reasoning_effort:Undefinable<String>;
	final verbosity:Undefinable<String>;
	final thinking_budget:Undefinable<Float>;
}

typedef CopilotPreparedChatRequest = {
	final args:CopilotOpenAIChatArgs;
	final warnings:Array<CopilotChatWarning>;
}

class CopilotChatRequest {
	public static function options(modelId:String, prompt:Array<CopilotPromptMessage>):CopilotChatRequestOptions {
		return {
			modelId: modelId,
			prompt: prompt,
			maxOutputTokens: Undefinable.absent(),
			temperature: Undefinable.absent(),
			topP: Undefinable.absent(),
			topK: Undefinable.absent(),
			frequencyPenalty: Undefinable.absent(),
			presencePenalty: Undefinable.absent(),
			stopSequences: Undefinable.absent(),
			seed: Undefinable.absent(),
			responseFormat: null,
			supportsStructuredOutputs: false,
			providerOptions: providerOptions(),
			tools: [],
			toolChoice: null,
		};
	}

	public static function providerOptions(?user:String, ?reasoningEffort:String, ?textVerbosity:String,
			?thinkingBudget:Float):CopilotCompatibleProviderOptions {
		return {
			user: stringOrAbsent(user),
			reasoningEffort: stringOrAbsent(reasoningEffort),
			textVerbosity: stringOrAbsent(textVerbosity),
			thinkingBudget: numberOrAbsent(thinkingBudget),
		};
	}

	public static function jsonResponseFormat(?schema:Unknown, ?name:String, ?description:String):CopilotChatResponseFormat {
		return CopilotChatResponseFormat.Json({
			schema: unknownOrAbsent(schema),
			name: stringOrAbsent(name),
			description: stringOrAbsent(description),
		});
	}

	public static function prepare(options:CopilotChatRequestOptions):CopilotPreparedChatRequest {
		final warnings:Array<CopilotChatWarning> = [];
		if (options.topK.orNull() != null) {
			warnings.push({
				type: CopilotChatWarningType.Unsupported,
				feature: "topK",
			});
		}

		final preparedResponseFormat = responseFormat(options.responseFormat, options.supportsStructuredOutputs);
		appendWarnings(warnings, preparedResponseFormat.warnings);
		final preparedTools = CopilotChatTools.prepare(options.tools, options.toolChoice);
		appendWarnings(warnings, preparedTools.toolWarnings);

		return {
			args: {
				model: options.modelId,
				user: options.providerOptions.user,
				max_tokens: options.maxOutputTokens,
				temperature: options.temperature,
				top_p: options.topP,
				frequency_penalty: options.frequencyPenalty,
				presence_penalty: options.presencePenalty,
				response_format: preparedResponseFormat.responseFormat,
				stop: options.stopSequences,
				seed: options.seed,
				messages: CopilotChatMessages.convertToOpenAICompatibleChatMessages(options.prompt),
				tools: preparedTools.tools,
				tool_choice: preparedTools.toolChoice,
				reasoning_effort: options.providerOptions.reasoningEffort,
				verbosity: options.providerOptions.textVerbosity,
				thinking_budget: options.providerOptions.thinkingBudget,
			},
			warnings: warnings,
		};
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

	static function appendWarnings(target:Array<CopilotChatWarning>, source:Array<CopilotChatWarning>):Void {
		for (warning in source)
			target.push(warning);
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

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		if (value == null)
			return Undefinable.absent();
		final present:Float = value;
		return present;
	}
}
