package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import haxe.extern.EitherType;
import js.html.URL;
import opencodehx.externs.ai.AiSdk.AiJsonValue;
import opencodehx.externs.ai.AiSdk.AiLanguageModelResponseFormat;
import opencodehx.externs.ai.AiSdk.AiLanguageModelResponseFormatType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelTool;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolChoice;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolChoiceType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelToolType;
import opencodehx.externs.ai.AiSdk.AiOpenAICompatibleProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderOptions;
import opencodehx.externs.ai.AiSdk.AiProviderOptionsMap;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotFileData;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotUnsupportedFunctionalityError;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptMessage;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotPromptPart;
import opencodehx.provider.copilot.CopilotChatMessages.CopilotToolOutput;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarning;
import opencodehx.provider.copilot.CopilotChatTools.CopilotChatWarningType;

using StringTools;

enum abstract CopilotResponsesSystemMessageMode(String) from String to String {
	final System = "system";
	final Developer = "developer";
	final Remove = "remove";
}

typedef CopilotResponsesModelConfig = {
	final isReasoningModel:Bool;
	final systemMessageMode:CopilotResponsesSystemMessageMode;
	final requiredAutoTruncation:Bool;
	final supportsFlexProcessing:Bool;
	final supportsPriorityProcessing:Bool;
}

typedef CopilotResponsesProviderOptions = {
	final user:Undefinable<String>;
	final reasoningEffort:Undefinable<String>;
	final reasoningSummary:Undefinable<String>;
	final textVerbosity:Undefinable<String>;
	final store:Undefinable<Bool>;
	final strictJsonSchema:Undefinable<Bool>;
	final include:Undefinable<Array<String>>;
	final instructions:Undefinable<String>;
	final logprobs:Undefinable<EitherType<Bool, Float>>;
	final maxToolCalls:Undefinable<Float>;
	final metadata:Undefinable<AiJsonValue>;
	final parallelToolCalls:Undefinable<Bool>;
	final previousResponseId:Undefinable<String>;
	final promptCacheKey:Undefinable<String>;
	final safetyIdentifier:Undefinable<String>;
	final serviceTier:Undefinable<String>;
}

typedef CopilotResponsesRequestOptions = {
	final modelId:String;
	final prompt:Array<CopilotPromptMessage>;
	var maxOutputTokens:Undefinable<Float>;
	var temperature:Undefinable<Float>;
	var topP:Undefinable<Float>;
	var topK:Undefinable<Float>;
	var stopSequences:Undefinable<Array<String>>;
	var seed:Undefinable<Float>;
	var frequencyPenalty:Undefinable<Float>;
	var presencePenalty:Undefinable<Float>;
	var responseFormat:Null<CopilotResponsesResponseFormat>;
	var providerOptions:CopilotResponsesProviderOptions;
	var tools:Array<CopilotResponsesTool>;
	var toolChoice:Null<CopilotResponsesToolChoice>;
}

typedef CopilotResponsesResponseFormat = {
	final type:AiLanguageModelResponseFormatType;
	final schema:Undefinable<Unknown>;
	final name:Undefinable<String>;
	final description:Undefinable<String>;
}

enum CopilotResponsesTool {
	Function(tool:CopilotResponsesFunctionTool);
	Provider(tool:CopilotResponsesProviderTool);
}

typedef CopilotResponsesFunctionTool = {
	final name:String;
	final description:Undefinable<String>;
	final inputSchema:Unknown;
}

typedef CopilotResponsesProviderTool = {
	final id:String;
	final name:String;
	final args:Unknown;
}

enum CopilotResponsesToolChoice {
	Auto;
	None;
	Required;
	Tool(toolName:String);
}

typedef CopilotResponsesInputContentPart = {
	final type:String;
	@:optional final text:String;
	@:optional final image_url:String;
	@:optional final file_url:String;
	@:optional final file_id:String;
	@:optional final filename:String;
	@:optional final file_data:String;
	@:optional final detail:String;
}

typedef CopilotResponsesSummaryPart = {
	final type:String;
	final text:String;
}

typedef CopilotResponsesInputItem = {
	@:optional final role:String;
	@:optional final content:EitherType<String, Array<CopilotResponsesInputContentPart>>;
	@:optional final type:String;
	@:optional final id:String;
	@:optional final call_id:String;
	@:optional final name:String;
	@:optional final arguments:String;
	@:optional final output:String;
	@:optional final approval_request_id:String;
	@:optional final approve:Bool;
	@:optional final encrypted_content:Undefinable<String>;
	@:optional final summary:Array<CopilotResponsesSummaryPart>;
}

typedef CopilotResponsesTextFormat = {
	final type:String;
	@:optional final strict:Undefinable<Bool>;
	@:optional final name:Undefinable<String>;
	@:optional final description:Undefinable<String>;
	@:optional final schema:Undefinable<Unknown>;
}

typedef CopilotResponsesTextOptions = {
	final format:Undefinable<CopilotResponsesTextFormat>;
	final verbosity:Undefinable<String>;
}

typedef CopilotResponsesReasoningOptions = {
	final effort:Undefinable<String>;
	final summary:Undefinable<String>;
}

typedef CopilotResponsesOpenAITool = {
	final type:String;
	@:optional final name:String;
	@:optional final description:Undefinable<String>;
	@:optional final parameters:Unknown;
	@:optional final strict:Undefinable<Bool>;
}

typedef CopilotResponsesToolChoiceObject = {
	final type:String;
	@:optional final name:String;
}

typedef CopilotResponsesToolChoiceValue = EitherType<String, CopilotResponsesToolChoiceObject>;

typedef CopilotResponsesArgs = {
	final model:String;
	final input:Array<CopilotResponsesInputItem>;
	final temperature:Undefinable<Float>;
	final top_p:Undefinable<Float>;
	final max_output_tokens:Undefinable<Float>;
	final text:Undefinable<CopilotResponsesTextOptions>;
	final max_tool_calls:Undefinable<Float>;
	final metadata:Undefinable<AiJsonValue>;
	final parallel_tool_calls:Undefinable<Bool>;
	final previous_response_id:Undefinable<String>;
	final store:Undefinable<Bool>;
	final user:Undefinable<String>;
	final instructions:Undefinable<String>;
	final service_tier:Undefinable<String>;
	final include:Undefinable<Array<String>>;
	final prompt_cache_key:Undefinable<String>;
	final safety_identifier:Undefinable<String>;
	final top_logprobs:Undefinable<Float>;
	final reasoning:Undefinable<CopilotResponsesReasoningOptions>;
	final truncation:Undefinable<String>;
	final tools:Undefinable<Array<CopilotResponsesOpenAITool>>;
	final tool_choice:Undefinable<CopilotResponsesToolChoiceValue>;
}

typedef CopilotResponsesStreamArgs = {
	> CopilotResponsesArgs,
	final stream:Bool;
}

typedef CopilotPreparedResponsesRequest = {
	final args:CopilotResponsesArgs;
	final warnings:Array<CopilotChatWarning>;
	final webSearchToolName:Undefinable<String>;
}

typedef CopilotPreparedResponsesStreamRequest = {
	final args:CopilotResponsesStreamArgs;
	final warnings:Array<CopilotChatWarning>;
	final webSearchToolName:Undefinable<String>;
}

class CopilotResponsesRequest {
	public static inline final TOP_LOGPROBS_MAX = 20;

	public static function options(modelId:String, prompt:Array<CopilotPromptMessage>):CopilotResponsesRequestOptions {
		return {
			modelId: modelId,
			prompt: prompt,
			maxOutputTokens: Undefinable.absent(),
			temperature: Undefinable.absent(),
			topP: Undefinable.absent(),
			topK: Undefinable.absent(),
			stopSequences: Undefinable.absent(),
			seed: Undefinable.absent(),
			frequencyPenalty: Undefinable.absent(),
			presencePenalty: Undefinable.absent(),
			responseFormat: null,
			providerOptions: providerOptions(),
			tools: [],
			toolChoice: null,
		};
	}

	public static function providerOptions(?source:AiProviderOptions, providerName:String = "copilot"):CopilotResponsesProviderOptions {
		var out = emptyProviderOptions();

		function apply(value:Null<AiOpenAICompatibleProviderOptions>):Void {
			if (value == null)
				return;
			out = mergeOptions(out, value);
		}

		if (source != null) {
			final options:AiProviderOptionsMap = source;
			apply(options.get("copilot"));
			apply(options.get(providerName));
		}
		return out;
	}

	public static function responseFormat(format:Null<AiLanguageModelResponseFormat>):Null<CopilotResponsesResponseFormat> {
		if (format == null || format.type == AiLanguageModelResponseFormatType.Text)
			return null;
		if (format.type == AiLanguageModelResponseFormatType.Json) {
			return {
				type: AiLanguageModelResponseFormatType.Json,
				schema: unknownOrAbsent(format.schema),
				name: stringOrAbsent(format.name),
				description: stringOrAbsent(format.description),
			};
		}
		throw "Unsupported AI SDK response format";
	}

	public static function tools(source:Null<Array<AiLanguageModelTool>>):Array<CopilotResponsesTool> {
		final out:Array<CopilotResponsesTool> = [];
		if (source == null)
			return out;
		for (tool in source) {
			if (tool.type == AiLanguageModelToolType.Function) {
				out.push(CopilotResponsesTool.Function({
					name: tool.name,
					description: stringOrAbsent(tool.description),
					inputSchema: requireUnknown(tool.inputSchema, 'function tool ${tool.name} inputSchema'),
				}));
			} else if (tool.type == AiLanguageModelToolType.Provider) {
				out.push(CopilotResponsesTool.Provider({
					id: requireString(tool.id, "provider tool id"),
					name: tool.name,
					args: requireUnknown(tool.args, 'provider tool ${tool.name} args'),
				}));
			} else {
				throw "Unsupported AI SDK tool type";
			}
		}
		return out;
	}

	public static function toolChoice(source:Null<AiLanguageModelToolChoice>):Null<CopilotResponsesToolChoice> {
		if (source == null)
			return null;
		if (source.type == AiLanguageModelToolChoiceType.Auto)
			return CopilotResponsesToolChoice.Auto;
		if (source.type == AiLanguageModelToolChoiceType.None)
			return CopilotResponsesToolChoice.None;
		if (source.type == AiLanguageModelToolChoiceType.Required)
			return CopilotResponsesToolChoice.Required;
		if (source.type == AiLanguageModelToolChoiceType.Tool)
			return CopilotResponsesToolChoice.Tool(requireString(source.toolName, "tool choice toolName"));
		throw "Unsupported AI SDK tool choice";
	}

	public static function prepare(options:CopilotResponsesRequestOptions):CopilotPreparedResponsesRequest {
		final warnings:Array<CopilotChatWarning> = [];
		final modelConfig = modelConfig(options.modelId);
		warnIfPresent(warnings, options.topK, "topK");
		warnIfPresent(warnings, options.seed, "seed");
		warnIfPresent(warnings, options.presencePenalty, "presencePenalty");
		warnIfPresent(warnings, options.frequencyPenalty, "frequencyPenalty");
		if (options.stopSequences.orNull() != null)
			warnings.push(unsupported("stopSequences"));

		final store = boolOrDefault(options.providerOptions.store, true);
		final inputResult = input(options.prompt, modelConfig.systemMessageMode, store);
		appendWarnings(warnings, inputResult.warnings);
		final strictJsonSchema = boolOrDefault(options.providerOptions.strictJsonSchema, false);
		final include = autoIncludes(options.providerOptions, options.tools);
		final topLogprobs = topLogprobs(options.providerOptions.logprobs);
		final text = textOptions(options.responseFormat, strictJsonSchema, options.providerOptions.textVerbosity);
		final reasoning = reasoningOptions(modelConfig, options.providerOptions, warnings);
		final serviceTier = serviceTier(modelConfig, options.providerOptions.serviceTier, warnings);
		final toolResult = prepareTools(options.tools, options.toolChoice, strictJsonSchema);
		appendWarnings(warnings, toolResult.toolWarnings);

		var temperature = options.temperature;
		var topP = options.topP;
		if (modelConfig.isReasoningModel) {
			if (temperature.orNull() != null) {
				temperature = Undefinable.absent();
				warnings.push({
					type: CopilotChatWarningType.Unsupported,
					feature: "temperature",
					details: "temperature is not supported for reasoning models",
				});
			}
			if (topP.orNull() != null) {
				topP = Undefinable.absent();
				warnings.push({
					type: CopilotChatWarningType.Unsupported,
					feature: "topP",
					details: "topP is not supported for reasoning models",
				});
			}
		}

		return {
			args: {
				model: options.modelId,
				input: inputResult.input,
				temperature: temperature,
				top_p: topP,
				max_output_tokens: options.maxOutputTokens,
				text: text,
				max_tool_calls: options.providerOptions.maxToolCalls,
				metadata: options.providerOptions.metadata,
				parallel_tool_calls: options.providerOptions.parallelToolCalls,
				previous_response_id: options.providerOptions.previousResponseId,
				store: options.providerOptions.store,
				user: options.providerOptions.user,
				instructions: options.providerOptions.instructions,
				service_tier: serviceTier,
				include: include,
				prompt_cache_key: options.providerOptions.promptCacheKey,
				safety_identifier: options.providerOptions.safetyIdentifier,
				top_logprobs: topLogprobs,
				reasoning: reasoning,
				truncation: modelConfig.requiredAutoTruncation ? "auto" : Undefinable.absent(),
				tools: toolResult.tools,
				tool_choice: toolResult.toolChoice,
			},
			warnings: warnings,
			webSearchToolName: toolResult.webSearchToolName,
		};
	}

	public static function prepareStream(options:CopilotResponsesRequestOptions):CopilotPreparedResponsesStreamRequest {
		final prepared = prepare(options);
		return {
			args: {
				model: prepared.args.model,
				input: prepared.args.input,
				temperature: prepared.args.temperature,
				top_p: prepared.args.top_p,
				max_output_tokens: prepared.args.max_output_tokens,
				text: prepared.args.text,
				max_tool_calls: prepared.args.max_tool_calls,
				metadata: prepared.args.metadata,
				parallel_tool_calls: prepared.args.parallel_tool_calls,
				previous_response_id: prepared.args.previous_response_id,
				store: prepared.args.store,
				user: prepared.args.user,
				instructions: prepared.args.instructions,
				service_tier: prepared.args.service_tier,
				include: prepared.args.include,
				prompt_cache_key: prepared.args.prompt_cache_key,
				safety_identifier: prepared.args.safety_identifier,
				top_logprobs: prepared.args.top_logprobs,
				reasoning: prepared.args.reasoning,
				truncation: prepared.args.truncation,
				tools: prepared.args.tools,
				tool_choice: prepared.args.tool_choice,
				stream: true,
			},
			warnings: prepared.warnings,
			webSearchToolName: prepared.webSearchToolName,
		};
	}

	public static function modelConfig(modelId:String):CopilotResponsesModelConfig {
		final supportsFlex = modelId.startsWith("o3")
			|| modelId.startsWith("o4-mini")
			|| (modelId.startsWith("gpt-5") && !modelId.startsWith("gpt-5-chat"));
		final supportsPriority = modelId.startsWith("gpt-4")
			|| modelId.startsWith("gpt-5-mini")
			|| (modelId.startsWith("gpt-5") && !modelId.startsWith("gpt-5-nano") && !modelId.startsWith("gpt-5-chat"))
			|| modelId.startsWith("o3")
			|| modelId.startsWith("o4-mini");
		final defaults = {
			requiredAutoTruncation: false,
			systemMessageMode: CopilotResponsesSystemMessageMode.System,
			supportsFlexProcessing: supportsFlex,
			supportsPriorityProcessing: supportsPriority,
		};
		if (modelId.startsWith("gpt-5-chat")) {
			return {
				isReasoningModel: false,
				requiredAutoTruncation: defaults.requiredAutoTruncation,
				systemMessageMode: defaults.systemMessageMode,
				supportsFlexProcessing: defaults.supportsFlexProcessing,
				supportsPriorityProcessing: defaults.supportsPriorityProcessing,
			};
		}
		if (modelId.startsWith("o")
			|| modelId.startsWith("gpt-5")
			|| modelId.startsWith("codex-")
			|| modelId.startsWith("computer-use")) {
			return {
				isReasoningModel: true,
				requiredAutoTruncation: defaults.requiredAutoTruncation,
				systemMessageMode: modelId.startsWith("o1-mini")
				|| modelId.startsWith("o1-preview") ? CopilotResponsesSystemMessageMode.Remove : CopilotResponsesSystemMessageMode.Developer,
				supportsFlexProcessing: defaults.supportsFlexProcessing,
				supportsPriorityProcessing: defaults.supportsPriorityProcessing,
			};
		}
		return {
			isReasoningModel: false,
			requiredAutoTruncation: defaults.requiredAutoTruncation,
			systemMessageMode: defaults.systemMessageMode,
			supportsFlexProcessing: defaults.supportsFlexProcessing,
			supportsPriorityProcessing: defaults.supportsPriorityProcessing,
		};
	}

	static function input(prompt:Array<CopilotPromptMessage>, systemMode:String,
			store:Bool):{input:Array<CopilotResponsesInputItem>, warnings:Array<CopilotChatWarning>} {
		final out:Array<CopilotResponsesInputItem> = [];
		final warnings:Array<CopilotChatWarning> = [];
		final processedApprovals = new Map<String, Bool>();
		for (message in prompt) {
			switch message {
				case System(content, _):
					switch systemMode {
						case System:
							out.push({role: "system", content: content});
						case Developer:
							out.push({role: "developer", content: content});
						case Remove:
							warnings.push({type: CopilotChatWarningType.Unsupported, feature: "system messages"});
					}
				case User(content, _):
					final parts:Array<CopilotResponsesInputContentPart> = [];
					for (part in content)
						parts.push(userPart(part));
					out.push({role: "user", content: parts});
				case Assistant(content, _):
					for (part in content)
						assistantPart(out, warnings, part, store);
				case Tool(content, _):
					for (part in content)
						toolPart(out, processedApprovals, part);
			}
		}
		return {input: out, warnings: warnings};
	}

	static function userPart(part:CopilotPromptPart):CopilotResponsesInputContentPart {
		return switch part {
			case Text(text, _):
				{type: "input_text", text: text};
			case File(data, mediaType, _):
				if (mediaType.startsWith("image/")) imagePart(data,
					mediaType); else if (mediaType == "application/pdf") pdfPart(data); else
					throw new CopilotUnsupportedFunctionalityError('file part media type ${mediaType}');
			case _:
				throw new CopilotUnsupportedFunctionalityError("non-user prompt part in user message");
		}
	}

	static function imagePart(data:CopilotFileData, mediaType:String):CopilotResponsesInputContentPart {
		return switch data {
			case RemoteUrl(value):
				{type: "input_image", image_url: value.href};
			case Base64(value):
				{type: "input_image", image_url: 'data:${normalizedImageMediaType(mediaType)};base64,${value}'};
			case Bytes(value):
				{
					type: "input_image",
					image_url: 'data:${normalizedImageMediaType(mediaType)};base64,${opencodehx.externs.node.Buffer.from(value).toString("base64")}'
				};
		}
	}

	static function pdfPart(data:CopilotFileData):CopilotResponsesInputContentPart {
		return switch data {
			case RemoteUrl(value):
				{type: "input_file", file_url: value.href};
			case Base64(value):
				{type: "input_file", filename: "part.pdf", file_data: 'data:application/pdf;base64,${value}'};
			case Bytes(value):
				{
					type: "input_file",
					filename: "part.pdf",
					file_data: 'data:application/pdf;base64,${opencodehx.externs.node.Buffer.from(value).toString("base64")}'
				};
		}
	}

	static function assistantPart(out:Array<CopilotResponsesInputItem>, warnings:Array<CopilotChatWarning>, part:CopilotPromptPart, store:Bool):Void {
		switch part {
			case Text(text, _):
				out.push({role: "assistant", content: [{type: "output_text", text: text}]});
			case ToolCall(toolCallId, toolName, value, _):
				out.push({
					type: "function_call",
					call_id: toolCallId,
					name: toolName,
					arguments: stringifyUnknown(value)
				});
			case ToolResult(toolCallId, _, _, _):
				if (store)
					out.push({type: "item_reference", id: toolCallId});
				else
					warnings.push({type: CopilotChatWarningType.Unsupported, feature: "stored provider tool result with store=false"});
			case Reasoning(text, providerOptions):
				final itemId = reasoningItemId(providerOptions);
				if (itemId == null) {
					warnings.push({type: CopilotChatWarningType.Unsupported, feature: "non-OpenAI reasoning part"});
				} else if (store) {
					out.push({type: "item_reference", id: itemId});
				} else {
					out.push({
						type: "reasoning",
						id: itemId,
						encrypted_content: reasoningEncryptedContent(providerOptions),
						summary: text == "" ? [] : [{type: "summary_text", text: text}],
					});
				}
			case _:
		}
	}

	static function toolPart(out:Array<CopilotResponsesInputItem>, processedApprovals:Map<String, Bool>, part:CopilotPromptPart):Void {
		switch part {
			case ToolApprovalResponse(approvalId, approved, _, _):
				if (processedApprovals.exists(approvalId))
					return;
				processedApprovals.set(approvalId, true);
				out.push({type: "item_reference", id: approvalId});
				out.push({type: "mcp_approval_response", approval_request_id: approvalId, approve: approved});
			case ToolResult(toolCallId, _, output, _):
				out.push({type: "function_call_output", call_id: toolCallId, output: outputContent(output)});
			case _:
		}
	}

	static function textOptions(format:Null<CopilotResponsesResponseFormat>, strictJsonSchema:Bool,
			verbosity:Undefinable<String>):Undefinable<CopilotResponsesTextOptions> {
		final presentVerbosity = verbosity.orNull();
		final hasVerbosity = presentVerbosity != null;
		if (format == null && !hasVerbosity)
			return Undefinable.absent();
		if (format == null) {
			return {
				format: Undefinable.absent(),
				verbosity: verbosity,
			};
		}
		final schema = format.schema.orNull();
		final formatName = format.name.orNull();
		final textFormat:CopilotResponsesTextFormat = schema == null ? {
			type: "json_object",
		} : {
			type: "json_schema",
			strict: strictJsonSchema,
			name: formatName == null ? "response" : formatName,
			description: format.description,
			schema: schema,
			};
		return {
			format: textFormat,
			verbosity: verbosity,
		};
	}

	static function prepareTools(tools:Array<CopilotResponsesTool>, choice:Null<CopilotResponsesToolChoice>, strictJsonSchema:Bool):{
		tools:Undefinable<Array<CopilotResponsesOpenAITool>>,
		toolChoice:Undefinable<CopilotResponsesToolChoiceValue>,
		toolWarnings:Array<CopilotChatWarning>,
		webSearchToolName:Undefinable<String>,
	} {
		final warnings:Array<CopilotChatWarning> = [];
		if (tools == null || tools.length == 0) {
			return {
				tools: Undefinable.absent(),
				toolChoice: Undefinable.absent(),
				toolWarnings: warnings,
				webSearchToolName: Undefinable.absent()
			};
		}

		var webSearchName:Null<String> = null;
		final out:Array<CopilotResponsesOpenAITool> = [];
		for (tool in tools) {
			switch tool {
				case Function(fn):
					out.push({
						type: "function",
						name: fn.name,
						description: fn.description,
						parameters: fn.inputSchema,
						strict: strictJsonSchema,
					});
				case Provider(providerTool):
					switch providerTool.id {
						case "openai.web_search" | "openai.web_search_preview":
							webSearchName = providerTool.name;
							out.push({type: providerTool.id == "openai.web_search" ? "web_search" : "web_search_preview"});
						case "openai.file_search":
							out.push({type: "file_search"});
						case "openai.code_interpreter":
							out.push({type: "code_interpreter"});
						case "openai.image_generation":
							out.push({type: "image_generation"});
						case "openai.local_shell":
							out.push({type: "local_shell"});
						case id:
							warnings.push({type: CopilotChatWarningType.Unsupported, feature: 'provider tool ${id}'});
					}
			}
		}
		return {
			tools: out,
			toolChoice: preparedChoice(choice),
			toolWarnings: warnings,
			webSearchToolName: stringOrAbsent(webSearchName),
		};
	}

	static function preparedChoice(toolChoice:Null<CopilotResponsesToolChoice>):Undefinable<CopilotResponsesToolChoiceValue> {
		return switch toolChoice {
			case null:
				Undefinable.absent();
			case Auto:
				"auto";
			case None:
				"none";
			case Required:
				"required";
			case Tool(toolName):
				if (toolName == "code_interpreter" || toolName == "file_search" || toolName == "image_generation" || toolName == "web_search_preview"
					|| toolName == "web_search") {
						type: toolName
					}; else {type: "function", name: toolName};
		}
	}

	static function reasoningOptions(modelConfig:CopilotResponsesModelConfig, providerOptions:CopilotResponsesProviderOptions,
			warnings:Array<CopilotChatWarning>):Undefinable<CopilotResponsesReasoningOptions> {
		final effort = providerOptions.reasoningEffort.orNull();
		final summary = providerOptions.reasoningSummary.orNull();
		if (!modelConfig.isReasoningModel) {
			if (effort != null)
				warnings.push({
					type: CopilotChatWarningType.Unsupported,
					feature: "reasoningEffort",
					details: "reasoningEffort is not supported for non-reasoning models"
				});
			if (summary != null)
				warnings.push({
					type: CopilotChatWarningType.Unsupported,
					feature: "reasoningSummary",
					details: "reasoningSummary is not supported for non-reasoning models"
				});
			return Undefinable.absent();
		}
		if (effort == null && summary == null)
			return Undefinable.absent();
		return {
			effort: providerOptions.reasoningEffort,
			summary: providerOptions.reasoningSummary,
		};
	}

	static function serviceTier(modelConfig:CopilotResponsesModelConfig, value:Undefinable<String>, warnings:Array<CopilotChatWarning>):Undefinable<String> {
		final present = value.orNull();
		if (present == "flex" && !modelConfig.supportsFlexProcessing) {
			warnings.push({
				type: CopilotChatWarningType.Unsupported,
				feature: "serviceTier",
				details: "flex processing is only available for o3, o4-mini, and gpt-5 models"
			});
			return Undefinable.absent();
		}
		if (present == "priority" && !modelConfig.supportsPriorityProcessing) {
			warnings.push({
				type: CopilotChatWarningType.Unsupported,
				feature: "serviceTier",
				details: "priority processing is only available for supported models and requires Enterprise access",
			});
			return Undefinable.absent();
		}
		return value;
	}

	static function autoIncludes(providerOptions:CopilotResponsesProviderOptions, tools:Array<CopilotResponsesTool>):Undefinable<Array<String>> {
		final include = providerOptions.include.orNull();
		final out = include == null ? [] : include.copy();
		final requestedTopLogprobs = topLogprobs(providerOptions.logprobs).orNull();
		if (requestedTopLogprobs != null && out.indexOf("message.output_text.logprobs") < 0)
			out.push("message.output_text.logprobs");
		for (tool in tools) {
			switch tool {
				case Provider(providerTool):
					if ((providerTool.id == "openai.web_search" || providerTool.id == "openai.web_search_preview")
						&& out.indexOf("web_search_call.action.sources") < 0)
						out.push("web_search_call.action.sources");
					if (providerTool.id == "openai.code_interpreter" && out.indexOf("code_interpreter_call.outputs") < 0)
						out.push("code_interpreter_call.outputs");
				case Function(_):
			}
		}
		return out.length == 0 ? Undefinable.absent() : out;
	}

	static function topLogprobs(source:Undefinable<EitherType<Bool, Float>>):Undefinable<Float> {
		final value = source.orNull();
		if (value == null)
			return Undefinable.absent();
		if (Std.isOfType(value, Bool)) {
			final enabled:Bool = value;
			return enabled ? TOP_LOGPROBS_MAX : Undefinable.absent();
		}
		final number:Float = value;
		return number;
	}

	static function emptyProviderOptions():CopilotResponsesProviderOptions {
		return {
			user: Undefinable.absent(),
			reasoningEffort: Undefinable.absent(),
			reasoningSummary: Undefinable.absent(),
			textVerbosity: Undefinable.absent(),
			store: Undefinable.absent(),
			strictJsonSchema: Undefinable.absent(),
			include: Undefinable.absent(),
			instructions: Undefinable.absent(),
			logprobs: Undefinable.absent(),
			maxToolCalls: Undefinable.absent(),
			metadata: Undefinable.absent(),
			parallelToolCalls: Undefinable.absent(),
			previousResponseId: Undefinable.absent(),
			promptCacheKey: Undefinable.absent(),
			safetyIdentifier: Undefinable.absent(),
			serviceTier: Undefinable.absent(),
		};
	}

	static function mergeOptions(current:CopilotResponsesProviderOptions, next:AiOpenAICompatibleProviderOptions):CopilotResponsesProviderOptions {
		return {
			user: next.user == null ? current.user : next.user,
			reasoningEffort: next.reasoningEffort == null ? current.reasoningEffort : next.reasoningEffort,
			reasoningSummary: next.reasoningSummary == null ? current.reasoningSummary : next.reasoningSummary,
			textVerbosity: next.textVerbosity == null ? current.textVerbosity : next.textVerbosity,
			store: next.store == null ? current.store : next.store,
			strictJsonSchema: next.strictJsonSchema == null ? current.strictJsonSchema : next.strictJsonSchema,
			include: next.include == null ? current.include : next.include,
			instructions: next.instructions == null ? current.instructions : next.instructions,
			logprobs: next.logprobs == null ? current.logprobs : next.logprobs,
			maxToolCalls: next.maxToolCalls == null ? current.maxToolCalls : next.maxToolCalls,
			metadata: next.metadata == null ? current.metadata : next.metadata,
			parallelToolCalls: next.parallelToolCalls == null ? current.parallelToolCalls : next.parallelToolCalls,
			previousResponseId: next.previousResponseId == null ? current.previousResponseId : next.previousResponseId,
			promptCacheKey: next.promptCacheKey == null ? current.promptCacheKey : next.promptCacheKey,
			safetyIdentifier: next.safetyIdentifier == null ? current.safetyIdentifier : next.safetyIdentifier,
			serviceTier: next.serviceTier == null ? current.serviceTier : next.serviceTier,
		};
	}

	static function outputContent(output:CopilotToolOutput):String {
		return switch output {
			case Text(value) | ErrorText(value):
				value;
			case ExecutionDenied(reason):
				reason == null ? "Tool execution denied." : reason;
			case Content(value) | JsonValue(value) | ErrorJson(value):
				stringifyUnknown(value);
		}
	}

	static function reasoningItemId(providerOptions:Null<opencodehx.provider.copilot.CopilotChatMessages.CopilotProviderOptions>):Null<String> {
		final metadata = providerOptions == null ? null : providerOptions.copilot;
		return metadata == null ? null : metadata.reasoningOpaque;
	}

	static function reasoningEncryptedContent(providerOptions:Null<opencodehx.provider.copilot.CopilotChatMessages.CopilotProviderOptions>):Undefinable<String> {
		final metadata = providerOptions == null ? null : providerOptions.copilot;
		return metadata == null ? Undefinable.absent() : stringOrAbsent(metadata.reasoningOpaque);
	}

	static function normalizedImageMediaType(mediaType:String):String {
		return mediaType == "image/*" ? "image/jpeg" : mediaType;
	}

	static function stringifyUnknown(value:Unknown):String {
		// AI SDK tool inputs/results are arbitrary JSON-compatible runtime
		// values. `Unknown` prevents property access; JSON serialization is the
		// exact boundary operation upstream performs before sending Responses.
		return haxe.Json.stringify(cast value);
	}

	static function warnIfPresent<T>(warnings:Array<CopilotChatWarning>, value:Undefinable<T>, feature:String):Void {
		if (value.orNull() != null)
			warnings.push(unsupported(feature));
	}

	static function unsupported(feature:String):CopilotChatWarning {
		return {type: CopilotChatWarningType.Unsupported, feature: feature};
	}

	static function appendWarnings(target:Array<CopilotChatWarning>, source:Array<CopilotChatWarning>):Void {
		for (warning in source)
			target.push(warning);
	}

	static function boolOrDefault(value:Undefinable<Bool>, fallback:Bool):Bool {
		final present = value.orNull();
		return present == null ? fallback : present;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function unknownOrAbsent(value:Null<Unknown>):Undefinable<Unknown> {
		return value == null ? Undefinable.absent() : value;
	}

	static function requireString(value:Null<String>, label:String):String {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}

	static function requireUnknown(value:Null<Unknown>, label:String):Unknown {
		if (value == null)
			throw 'Missing AI SDK ${label}';
		return value;
	}
}
