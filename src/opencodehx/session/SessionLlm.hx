package opencodehx.session;

import haxe.DynamicAccess;
import opencodehx.externs.ai.AiSdk.AiJsonSchemaObject;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiSdk;
import opencodehx.externs.ai.AiSdk.AiTool;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderHeaders;

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

/**
 * Small pure helpers for upstream session/llm behavior that can be proven
 * without booting the full Effect LLM service.
 */
class SessionLlm {
	public static inline final NOOP_TOOL_ID = "_noop";

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
