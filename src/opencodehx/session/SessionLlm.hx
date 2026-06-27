package opencodehx.session;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import opencodehx.externs.ai.AiSdk.AiJsonSchemaObject;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiModelMessages;
import opencodehx.externs.ai.AiSdk.AiSdk;
import opencodehx.externs.ai.AiSdk.AiTool;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderMessage;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTransform;
import opencodehx.util.ErrorTools;
import opencodehx.util.Wildcard;
import js.lib.Error as JsError;

typedef LlmRequestHeaderInput = {
	final model:ProviderModel;
	final sessionID:String;
	final userID:String;
	final projectID:String;
	final client:String;
	final installationVersion:String;
	@:optional final parentSessionID:String;
	@:optional final headers:ProviderHeaders;
}

typedef LlmSystemInput = {
	final provider:Array<String>;
	final input:Array<String>;
	@:optional final agentPrompt:String;
	@:optional final userSystem:String;
}

typedef LlmToolCallRepairInput = {
	@:optional var toolCallId:String;
	final toolName:String;
	@:optional var input:String;
}

typedef LlmRequestOptionsInput = {
	final model:ProviderModel;
	final sessionID:String;
	final small:Bool;
	final isOpenaiOauth:Bool;
	final system:Array<String>;
	@:optional final providerOptions:ProviderOptions;
	@:optional final agentOptions:ProviderOptions;
	@:optional final variant:String;
}

typedef LlmRequestParamsInput = {
	final model:ProviderModel;
	final options:ProviderOptions;
	@:optional final agentTemperature:Float;
	@:optional final agentTopP:Float;
}

typedef LlmRequestParams = {
	final temperature:Undefinable<Float>;
	final topP:Undefinable<Float>;
	final topK:Undefinable<Float>;
	final maxOutputTokens:Float;
	final options:ProviderOptions;
}

typedef LlmStreamTextOptionsInput = {
	final model:ProviderModel;
	final params:LlmRequestParams;
	final tools:DynamicAccess<AiTool>;
	final headers:ProviderHeaders;
	@:optional final retries:Int;
	@:optional final toolChoice:String;
}

typedef LlmStreamTextOptions = {
	final temperature:Undefinable<Float>;
	final topP:Undefinable<Float>;
	final topK:Undefinable<Float>;
	final providerOptions:ProviderOptions;
	final activeTools:Array<String>;
	@:optional var toolChoice:String;
	final maxOutputTokens:Float;
	final headers:ProviderHeaders;
	final maxRetries:Int;
}

typedef LlmWorkflowApprovalTool = {
	final name:String;
	final args:String;
}

typedef LlmWorkflowApprovalUpdate = {
	final approved:Array<String>;
	final preapproved:Array<String>;
}

typedef LlmWorkflowModelState = {
	final sessionID:String;
	final systemPrompt:String;
	final sessionPreapprovedTools:Array<String>;
}

typedef LlmWorkflowToolExecutorResult = {
	var result:String;
	@:optional var metadata:Unknown;
	@:optional var title:String;
	@:optional var error:String;
}

typedef LlmTelemetryInput = {
	final sessionID:String;
	@:optional final openTelemetry:Bool;
	@:optional final username:String;
	@:optional final tracer:Unknown;
}

typedef LlmTelemetryMetadata = {
	final userId:String;
	final sessionId:String;
}

typedef LlmTelemetryOptions = {
	final isEnabled:Undefinable<Bool>;
	final functionId:String;
	final tracer:Undefinable<Unknown>;
	final metadata:LlmTelemetryMetadata;
}

/**
 * Small pure helpers for upstream session/llm behavior that can be proven
 * without booting the full Effect LLM service.
 */
class SessionLlm {
	public static inline final NOOP_TOOL_ID = "_noop";
	public static inline final INVALID_TOOL_ID = "invalid";

	public static function hasToolCalls(messages:Array<AiLanguageModelPromptMessage>):Bool {
		for (message in messages) {
			if (!Std.isOfType(message.content, Array))
				continue;
			final parts:Array<opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPart> = message.content;
			for (part in parts) {
				if (part.type == AiLanguageModelPromptPartType.ToolCall || part.type == AiLanguageModelPromptPartType.ToolResult)
					return true;
			}
		}
		return false;
	}

	public static function compatibilityTools(model:ProviderModel, tools:DynamicAccess<AiTool>,
			messages:Array<AiLanguageModelPromptMessage>):DynamicAccess<AiTool> {
		if (tools != null && hasActiveTools(tools))
			return tools;
		if (!hasToolCalls(messages) || !requiresNoopTool(model))
			return tools == null ? new DynamicAccess<AiTool>() : tools;
		final out = new DynamicAccess<AiTool>();
		out.set(NOOP_TOOL_ID, noopTool());
		return out;
	}

	public static function resolveTools(tools:DynamicAccess<AiTool>, agentRules:Array<PermissionRule>, promptRules:Array<PermissionRule>,
			?userTools:DynamicAccess<Bool>):DynamicAccess<AiTool> {
		final result = new DynamicAccess<AiTool>();
		final names = tools.keys();
		final disabled = PermissionRules.disabled(names, PermissionRules.merge([agentRules, promptRules]));
		for (name in names) {
			if (disabled.indexOf(name) != -1)
				continue;
			if (userTools != null && userTools.get(name) == false)
				continue;
			final tool = tools.get(name);
			if (tool != null)
				result.set(name, tool);
		}
		return result;
	}

	public static function requestHeaders(input:LlmRequestHeaderInput):ProviderHeaders {
		final out = new DynamicAccess<String>();
		if (input.model.providerID.toString().indexOf("opencode") == 0) {
			out.set("x-opencode-project", input.projectID);
			out.set("x-opencode-session", input.sessionID);
			out.set("x-opencode-request", input.userID);
			out.set("x-opencode-client", input.client);
		} else {
			out.set("x-session-affinity", input.sessionID);
			if (input.parentSessionID != null)
				out.set("x-parent-session-id", input.parentSessionID);
			out.set("User-Agent", 'opencode/${input.installationVersion}');
		}
		copyHeaders(input.model.headers, out);
		if (input.headers != null)
			copyHeaders(input.headers, out);
		return out;
	}

	public static function composeSystem(input:LlmSystemInput):Array<String> {
		final parts:Array<String> = [];
		final agentPrompt = textOrEmpty(input.agentPrompt);
		if (agentPrompt != "") {
			parts.push(agentPrompt);
		} else {
			pushTexts(parts, input.provider);
		}
		pushTexts(parts, input.input);
		final userSystem = textOrEmpty(input.userSystem);
		if (userSystem != "")
			parts.push(userSystem);
		return [parts.join("\n")];
	}

	public static function finalizeSystemTransform(header:String, system:Array<String>):Array<String> {
		if (system.length <= 2 || system[0] != header)
			return system;
		final out = [header];
		out.push(system.slice(1).join("\n"));
		return out;
	}

	public static function requestMessages(system:Array<String>, messages:Array<AiLanguageModelPromptMessage>, isOpenaiOauth:Bool,
			isWorkflow:Bool):Array<AiLanguageModelPromptMessage> {
		if (isOpenaiOauth || isWorkflow)
			return messages;
		final out:Array<AiLanguageModelPromptMessage> = [];
		for (item in system) {
			out.push({
				role: AiLanguageModelPromptRole.System,
				content: item,
			});
		}
		for (message in messages)
			out.push(message);
		return out;
	}

	public static function requestModelMessages(system:Array<String>, userPrompt:String, isOpenaiOauth:Bool, isWorkflow:Bool):AiModelMessages {
		return AiModelMessages.systemUser(isOpenaiOauth || isWorkflow ? [] : system, userPrompt);
	}

	public static function activeToolNames(tools:DynamicAccess<AiTool>):Array<String> {
		final out:Array<String> = [];
		for (name in tools.keys()) {
			if (name != INVALID_TOOL_ID)
				out.push(name);
		}
		return out;
	}

	public static function workflowPreapprovedTools(tools:DynamicAccess<AiTool>, agentRules:Array<PermissionRule>,
			promptRules:Array<PermissionRule>):Array<String> {
		final out:Array<String> = [];
		final ruleset = PermissionRules.merge([agentRules, promptRules]);
		for (name in tools.keys()) {
			if (lastToolAction(name, ruleset) != "ask")
				out.push(name);
		}
		return out;
	}

	public static function workflowModelState(sessionID:String, system:Array<String>, tools:DynamicAccess<AiTool>, agentRules:Array<PermissionRule>,
			promptRules:Array<PermissionRule>):LlmWorkflowModelState {
		return {
			sessionID: sessionID,
			systemPrompt: system.join("\n"),
			sessionPreapprovedTools: workflowPreapprovedTools(tools, agentRules, promptRules),
		};
	}

	public static function workflowApprovalNames(tools:Array<LlmWorkflowApprovalTool>):Array<String> {
		final out:Array<String> = [];
		for (tool in tools)
			pushUnique(out, tool.name);
		return out;
	}

	public static function workflowAlreadyApproved(tools:Array<LlmWorkflowApprovalTool>, approved:Array<String>):Bool {
		final names = workflowApprovalNames(tools);
		for (name in names) {
			if (!hasString(approved, name))
				return false;
		}
		return true;
	}

	public static function workflowApprovalPatterns(tools:Array<LlmWorkflowApprovalTool>):Array<String> {
		final out:Array<String> = [];
		for (tool in tools)
			pushUnique(out, workflowApprovalPattern(tool));
		return out;
	}

	public static function rememberWorkflowApproval(preapproved:Array<String>, approved:Array<String>,
			tools:Array<LlmWorkflowApprovalTool>):LlmWorkflowApprovalUpdate {
		final names = workflowApprovalNames(tools);
		final nextApproved = approved.copy();
		for (name in names)
			pushUnique(nextApproved, name);
		final nextPreapproved = preapproved.copy();
		for (name in names)
			nextPreapproved.push(name);
		return {
			approved: nextApproved,
			preapproved: nextPreapproved,
		};
	}

	public static function workflowUnknownToolResult(toolName:String):LlmWorkflowToolExecutorResult {
		return {
			result: "",
			error: 'Unknown tool: ${toolName}',
		};
	}

	public static function workflowToolExecutionResult(raw:Unknown):LlmWorkflowToolExecutorResult {
		final text = UnknownNarrow.string(raw);
		if (text != null)
			return {result: text};
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return {result: stringifyUnknown(raw)};
		final output = workflowResultOutput(record.get("output"));
		final out:LlmWorkflowToolExecutorResult = {
			result: output == null ? stringifyUnknown(raw) : output,
		};
		final metadata = record.get("metadata");
		if (!UnknownNarrow.isNull(metadata) && !UnknownNarrow.isUndefined(metadata))
			out.metadata = metadata;
		final title = UnknownNarrow.string(record.get("title"));
		if (title != null)
			out.title = title;
		return out;
	}

	public static function workflowToolExecutionError(error:Unknown):LlmWorkflowToolExecutorResult {
		return {
			result: "",
			error: ErrorTools.message(error),
		};
	}

	public static function repairToolCall(toolCall:LlmToolCallRepairInput, tools:DynamicAccess<AiTool>, errorMessage:String):LlmToolCallRepairInput {
		final lower = toolCall.toolName.toLowerCase();
		if (lower != toolCall.toolName && tools.exists(lower))
			return copyToolCall(toolCall, lower, toolCall.input);
		return copyToolCall(toolCall, INVALID_TOOL_ID, Json.stringify({
			tool: toolCall.toolName,
			error: errorMessage,
		}));
	}

	public static function requestOptions(input:LlmRequestOptionsInput):ProviderOptions {
		final base = input.small ? ProviderTransform.smallOptions(input.model) : ProviderTransform.options({
			model: input.model,
			sessionID: input.sessionID,
			providerOptions: input.providerOptions,
		});
		final out = cloneOptions(base);
		mergeOptionsInto(out, input.model.options);
		mergeOptionsInto(out, input.agentOptions);
		if (!input.small && input.variant != null) {
			final variant = input.model.variants.get(input.variant);
			mergeOptionsInto(out, variant);
		}
		if (input.isOpenaiOauth)
			out.set("instructions", input.system.join("\n"));
		return out;
	}

	public static function requestParams(input:LlmRequestParamsInput):LlmRequestParams {
		var temperature:Null<Float> = null;
		if (input.model.capabilities.temperature)
			temperature = firstNumber(input.agentTemperature, ProviderTransform.temperature(input.model));
		final topK = ProviderTransform.topK(input.model);
		return {
			temperature: numberOrAbsent(temperature),
			topP: numberOrAbsent(firstNumber(input.agentTopP, ProviderTransform.topP(input.model))),
			topK: topK == null ? Undefinable.absent() : topK * 1.0,
			maxOutputTokens: ProviderTransform.maxOutputTokens(input.model),
			options: input.options,
		};
	}

	public static function transformStreamPrompt(type:String, prompt:Array<ProviderMessage>, model:ProviderModel,
			options:ProviderOptions):Array<ProviderMessage> {
		return type == "stream" ? ProviderTransform.message(prompt, model, options) : prompt;
	}

	public static function streamTextOptions(input:LlmStreamTextOptionsInput):LlmStreamTextOptions {
		final out:LlmStreamTextOptions = {
			temperature: input.params.temperature,
			topP: input.params.topP,
			topK: input.params.topK,
			providerOptions: ProviderTransform.providerOptions(input.model, input.params.options),
			activeTools: activeToolNames(input.tools),
			maxOutputTokens: input.params.maxOutputTokens,
			headers: input.headers,
			maxRetries: input.retries == null ? 0 : input.retries,
		};
		if (input.toolChoice != null)
			out.toolChoice = input.toolChoice;
		return out;
	}

	public static function telemetryOptions(input:LlmTelemetryInput):LlmTelemetryOptions {
		return {
			isEnabled: boolOrAbsent(input.openTelemetry),
			functionId: "session.llm",
			tracer: input.tracer == null ? Undefinable.absent() : input.tracer,
			metadata: {
				userId: textOr(input.username, "unknown"),
				sessionId: input.sessionID,
			},
		};
	}

	public static function streamFailureError(error:Unknown):JsError {
		if (Std.isOfType(error, JsError))
			// Haxe cannot carry the Std.isOfType proof into the return type, but
			// the generated JavaScript is the upstream `error instanceof Error`
			// branch and immediately returns the narrowed native Error.
			return cast error;
		return new JsError(Std.string(error));
	}

	public static function requiresNoopTool(model:ProviderModel):Bool {
		final providerID = model.providerID.toString().toLowerCase();
		final apiID = model.api.id.toLowerCase();
		final litellmOption:Null<Bool> = Reflect.field(model.options, "litellmProxy");
		return litellmOption == true
			|| providerID.indexOf("litellm") != -1
			|| apiID.indexOf("litellm") != -1
			|| providerID.indexOf("github-copilot") != -1;
	}

	static function hasActiveTools(tools:DynamicAccess<AiTool>):Bool {
		for (_ in tools.keys())
			return true;
		return false;
	}

	static function lastToolAction(name:String, ruleset:Array<PermissionRule>):Null<String> {
		var found:Null<String> = null;
		for (rule in ruleset) {
			if (Wildcard.match(name, rule.permission))
				found = rule.action;
		}
		return found;
	}

	static function workflowApprovalPattern(tool:LlmWorkflowApprovalTool):String {
		final title = workflowApprovalTitle(tool.args);
		return title == "" ? tool.name : '${tool.name}: ${title}';
	}

	static function workflowApprovalTitle(args:String):String {
		try {
			// Workflow tool args arrive as JSON strings from the provider. This is
			// the boundary where upstream reads optional title/name fields through
			// JavaScript nullish-coalescing and truthiness.
			final parsed = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(args)));
			if (parsed == null)
				return "";
			final title = workflowTitleValue(parsed.get("title"));
			if (title != null)
				return title;
			final name = workflowTitleValue(parsed.get("name"));
			return name == null ? "" : name;
		} catch (_:Dynamic) {
			return "";
		}
	}

	static function workflowTitleValue(value:Unknown):Null<String> {
		if (UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value))
			return null;
		final text = UnknownNarrow.string(value);
		if (text != null)
			return text;
		final bool = UnknownNarrow.bool(value);
		if (bool != null)
			return bool == true ? "true" : "";
		final number = UnknownNarrow.number(value);
		if (number != null)
			return number == 0 ? "" : Std.string(number);
		return "";
	}

	static function workflowResultOutput(value:Unknown):Null<String> {
		if (UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value))
			return null;
		final text = UnknownNarrow.string(value);
		if (text != null)
			return text;
		final bool = UnknownNarrow.bool(value);
		if (bool != null)
			return bool == true ? "true" : "false";
		final number = UnknownNarrow.number(value);
		if (number != null)
			return Std.string(number);
		return stringifyUnknown(value);
	}

	static function stringifyUnknown(value:Unknown):String {
		try {
			// Mirrors upstream's JSON.stringify fallback for workflow tool results.
			final encoded:Null<String> = Json.stringify(value);
			return encoded == null ? "" : encoded;
		} catch (_:Dynamic) {
			return "";
		}
	}

	static function pushUnique(out:Array<String>, value:String):Void {
		if (!hasString(out, value))
			out.push(value);
	}

	static function hasString(items:Array<String>, value:String):Bool {
		for (item in items) {
			if (item == value)
				return true;
		}
		return false;
	}

	static function copyToolCall(source:LlmToolCallRepairInput, toolName:String, input:Null<String>):LlmToolCallRepairInput {
		final out:LlmToolCallRepairInput = {
			toolName: toolName,
		};
		if (source.toolCallId != null)
			out.toolCallId = source.toolCallId;
		if (input != null)
			out.input = input;
		return out;
	}

	static function cloneOptions(options:Null<ProviderOptions>):ProviderOptions {
		final out = optionMap();
		mergeOptionsInto(out, options);
		return out;
	}

	static function mergeOptionsInto(target:ProviderOptions, source:Null<ProviderOptions>):Void {
		if (source == null)
			return;
		for (key in source.keys()) {
			// ProviderOptions is an SDK-owned passthrough record. These Dynamic
			// reads are contained to guarded deep-merge semantics for request
			// assembly and do not escape as app-facing domain data.
			final incoming:Dynamic = source.get(key);
			final current:Dynamic = target.get(key);
			if (isOptionRecord(current) && isOptionRecord(incoming)) {
				target.set(key, mergeOptionRecords(current, incoming));
			} else {
				target.set(key, incoming);
			}
		}
	}

	static function mergeOptionRecords(current:Dynamic, incoming:Dynamic):ProviderOptions {
		final out = optionMap();
		// ProviderOptions is the documented provider-SDK passthrough boundary.
		// Reflection is guarded to plain option records and the merged record is
		// immediately returned as provider options, not app-facing domain data.
		for (field in Reflect.fields(current))
			out.set(field, Reflect.field(current, field));
		for (field in Reflect.fields(incoming)) {
			final next:Dynamic = Reflect.field(incoming, field);
			final previous:Dynamic = out.get(field);
			if (isOptionRecord(previous) && isOptionRecord(next))
				out.set(field, mergeOptionRecords(previous, next));
			else
				out.set(field, next);
		}
		return out;
	}

	static function isOptionRecord(value:Dynamic):Bool {
		if (value == null)
			return false;
		if (Std.isOfType(value, Array) || Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return false;
		return Reflect.isObject(value);
	}

	static function optionMap():ProviderOptions {
		return new DynamicAccess<Dynamic>();
	}

	static function firstNumber(first:Null<Float>, fallback:Null<Float>):Null<Float> {
		return first == null ? fallback : first;
	}

	static function numberOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}

	static function boolOrAbsent(value:Null<Bool>):Undefinable<Bool> {
		return value == null ? Undefinable.absent() : value;
	}

	static function copyHeaders(source:ProviderHeaders, target:ProviderHeaders):Void {
		for (key in source.keys())
			target.set(key, nonNullHeader(source, key));
	}

	static function nonNullHeader(headers:ProviderHeaders, key:String):String {
		final value:Null<String> = headers.get(key);
		return value == null ? "" : value;
	}

	static function pushTexts(out:Array<String>, items:Array<String>):Void {
		for (item in items) {
			if (hasText(item))
				out.push(item);
		}
	}

	static function hasText(value:Null<String>):Bool {
		return value != null && value != "";
	}

	static function textOrEmpty(value:Null<String>):String {
		return value == null ? "" : value;
	}

	static function textOr(value:Null<String>, fallback:String):String {
		return value == null ? fallback : value;
	}

	static function noopTool():AiTool {
		return AiSdk.tool({
			description: "Do not call this tool. It exists only for API compatibility and must never be invoked.",
			inputSchema: AiSdk.jsonSchema(noopSchema()),
			execute: _ -> js.lib.Promise.resolve({
				output: "",
				title: "",
				metadata: {}
			}),
		});
	}

	static function noopSchema():AiJsonSchemaObject {
		final properties = new DynamicAccess<AiJsonSchemaObject>();
		properties.set("reason", {
			type: "string",
			description: "Unused",
		});
		return {
			type: "object",
			properties: properties,
		};
	}
}
