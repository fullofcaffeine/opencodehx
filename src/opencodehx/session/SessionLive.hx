package opencodehx.session;

import genes.js.Async.await;
import js.html.AbortSignal;
import js.lib.Promise;
import opencodehx.account.AccountStore;
import opencodehx.auth.AuthStore;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.config.ConfigLoader;
import opencodehx.config.ConfigWriter;
import opencodehx.host.node.GlobalPaths;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.SessionProcessor.SessionFileInput;
import opencodehx.session.SessionProcessor.SessionProcessorResult;
import opencodehx.storage.SessionStore;

typedef SessionLiveAgentSelection = {
	final name:Null<String>;
	final info:Null<AgentInfo>;
	final error:Null<String>;
}

typedef SessionLiveResolveInput = {
	final directory:String;
	@:optional final config:ConfigInfo;
	@:optional final modelText:String;
	@:optional final agentText:String;
	@:optional final variantText:String;
}

typedef SessionLivePlan = {
	final config:ConfigInfo;
	final provider:ProviderInfo;
	final model:ProviderModel;
	final language:opencodehx.externs.ai.AiSdk.AiLanguageModel;
	final agentName:Null<String>;
	final agent:Null<AgentInfo>;
	final variant:Null<String>;
}

typedef SessionLiveResolveResult = {
	final plan:Null<SessionLivePlan>;
	final error:Null<String>;
}

typedef SessionLiveRunInput = {
	final prompt:String;
	final directory:String;
	@:optional final projectID:String;
	@:optional final store:SessionStore;
	@:optional final sessionID:String;
	@:optional final turnID:String;
	@:optional final turnTime:Float;
	@:optional final parentSessionID:String;
	@:optional final config:ConfigInfo;
	@:optional final modelText:String;
	@:optional final agentText:String;
	@:optional final variantText:String;
	@:optional final skipPermissions:Bool;
	@:optional final files:Array<SessionFileInput>;
	@:optional final history:Array<WithParts>;
	@:optional final abortSignal:AbortSignal;
}

typedef SessionLiveRunResult = {
	final result:Null<SessionProcessorResult>;
	final error:Null<String>;
}

/**
	Shared live AI SDK session assembly for CLI and server entry points.

	This module owns the config/default-agent/model selection path, provider
	registry lookup, permission runtime construction, and live system prompt
	assembly. Keeping those decisions here prevents the server from growing a
	second copy of the CLI's live-provider logic.
**/
@:async
function liveLoadConfig(directory:String):Promise<ConfigInfo> {
	final env = opencodehx.host.node.NodeProcess.env();
	final local = liveLocalConfig(directory);
	final auth = AuthStore.load(env);
	final remote = @:await ConfigLoader.loadRemoteWellKnown(AuthStore.wellKnown(auth), {
		env: env,
		includeDefaultUsername: false,
	});
	final account = ConfigLoader.loadRemoteAccountConfigs(@:await AccountStore.loadRemoteConfigs(env), {
		env: env,
		includeDefaultUsername: false,
	});
	return remote.merge(local).merge(account);
}

function liveLocalConfig(directory:String):ConfigInfo {
	final env = opencodehx.host.node.NodeProcess.env();
	final config = ConfigInfo.empty("cli");
	config.merge(ConfigWriter.loadGlobal(GlobalPaths.config(env), {env: env}));
	config.merge(ConfigLoader.loadProject(directory, {
		defaultUsername: config.username == null ? "cli" : config.username,
		worktree: directory,
		env: env,
		includeDefaultUsername: false,
	}));
	return config;
}

@:async
function liveResolve(input:SessionLiveResolveInput):Promise<SessionLiveResolveResult> {
	final env = opencodehx.host.node.NodeProcess.env();
	final config:ConfigInfo = switch input.config {
		case null:
			@:await liveLoadConfig(input.directory);
		case value:
			value;
	}
	final selectedAgent = liveAgentSelection(config, input.agentText == null ? "" : input.agentText);
	if (selectedAgent.error != null)
		return {plan: null, error: selectedAgent.error};
	final resolvedModel = liveModelText(input.modelText == null ? "" : input.modelText, config, selectedAgent.info);
	if (resolvedModel == null || resolvedModel == "")
		return {plan: null, error: null};
	final registry = new ProviderRegistry({
		config: config,
		env: env,
		auth: AuthStore.load(env),
	});
	final parsed = ProviderRegistry.parseModel(resolvedModel);
	final provider = registry.getProvider(parsed.providerID);
	if (provider == null)
		return {plan: null, error: 'Provider not available for live AI SDK run: ${parsed.providerID.toString()}'};
	final model = registry.getModel(parsed.providerID, parsed.modelID);
	final variant = liveVariantText(input.variantText == null ? "" : input.variantText, selectedAgent.info);
	return {
		plan: {
			config: config,
			provider: provider,
			model: model,
			language: registry.getLanguage(model),
			agentName: selectedAgent.name,
			agent: selectedAgent.info,
			variant: variant == "" ? null : variant,
		},
		error: null,
	};
}

@:async
function liveRun(input:SessionLiveRunInput):Promise<SessionLiveRunResult> {
	final resolved = @:await liveResolve({
		directory: input.directory,
		config: input.config,
		modelText: input.modelText,
		agentText: input.agentText,
		variantText: input.variantText,
	});
	if (resolved.error != null || resolved.plan == null)
		return {result: null, error: resolved.error == null ? "Live AI SDK runs require --model provider/model or config model for now." : resolved.error};
	final plan:SessionLivePlan = switch resolved.plan {
		case null:
			return {result: null, error: "Live AI SDK runs require --model provider/model or config model for now."};
		case value:
			value;
	}
	final processed = @:await liveRunPlan(plan, input);
	return {result: processed, error: null};
}

@:async
function liveRunPlan(plan:SessionLivePlan, input:SessionLiveRunInput):Promise<SessionProcessorResult> {
	final processed = @:await SessionProcessor.runAiSdk({
		prompt: input.prompt,
		directory: input.directory,
		sessionID: input.sessionID,
		turnID: input.turnID,
		turnTime: input.turnTime,
		parentSessionID: input.parentSessionID,
		projectID: input.projectID,
		store: input.store,
		provider: plan.provider,
		model: plan.model,
		language: plan.language,
		files: input.files,
		history: input.history,
		permission: permissionRuntime(plan.config, input.skipPermissions == true, input.sessionID, plan.agent),
		agent: plan.agentName,
		system: @:await SessionSystemPrompt.buildAsync({
			directory: input.directory,
			model: plan.model,
			agent: plan.agent,
			config: plan.config,
		}),
		agentOptions: agentOptions(plan.agent),
		agentTemperature: plan.agent == null ? null : plan.agent.temperature,
		agentTopP: plan.agent == null ? null : plan.agent.top_p,
		disabledTools: disabledTools(plan.agent),
		variant: plan.variant,
		abortSignal: input.abortSignal,
	});
	return processed;
}

function liveAgentSelection(config:ConfigInfo, requestedAgent:String):SessionLiveAgentSelection {
	var name = requestedAgent;
	if (name == "" && config.defaultAgent != null)
		name = config.defaultAgent;
	if (name == "")
		return {name: null, info: null, error: null};
	final agents = config.agent;
	if (agents == null)
		return {name: name, info: null, error: 'Agent not available for live AI SDK run: ${name}'};
	final agent = agents.get(name);
	if (agent == null)
		return {name: name, info: null, error: 'Agent not available for live AI SDK run: ${name}'};
	if (agent.disable == true)
		return {name: name, info: null, error: 'Agent is disabled for live AI SDK run: ${name}'};
	return {name: name, info: agent, error: null};
}

function liveModelText(requestedModel:String, config:ConfigInfo, agent:Null<AgentInfo>):Null<String> {
	if (requestedModel != "")
		return requestedModel;
	if (agent != null && agent.model != null && agent.model != "")
		return agent.model;
	return config.model;
}

function liveVariantText(requestedVariant:String, agent:Null<AgentInfo>):String {
	if (requestedVariant != "")
		return requestedVariant;
	if (agent != null && agent.variant != null)
		return agent.variant;
	return "";
}

function agentOptions(agent:Null<AgentInfo>):Null<ProviderOptions> {
	if (agent == null || agent.options == null)
		return null;
	return agent.options;
}

function disabledTools(agent:Null<AgentInfo>):Null<Array<String>> {
	if (agent == null || agent.tools == null)
		return null;
	final disabled:Array<String> = [];
	for (tool in agent.tools.keys()) {
		if (agent.tools.get(tool) == false)
			pushUnique(disabled, normalizedToolID(tool));
	}
	return disabled.length == 0 ? null : disabled;
}

function permissionRuntime(config:ConfigInfo, skipPermissions:Bool, sessionID:Null<String>, agent:Null<AgentInfo>):Null<PermissionRuntime> {
	final rulesets:Array<Array<PermissionRule>> = [];
	if (agent != null)
		rulesets.push(PermissionRules.fromConfig(agent.permission));
	rulesets.push(PermissionRules.fromConfig(config.permission));
	// PermissionRules uses last-match semantics, so config-level rules are
	// appended after agent defaults and can still enforce global denies.
	final rules = PermissionRules.merge(rulesets);
	if (rules.length == 0 && !skipPermissions)
		return null;
	return new PermissionRuntime({
		ruleset: rules,
		sessionID: sessionID == null ? "" : sessionID,
		prompt: skipPermissions ? (_->{reply: "once"}) : null,
	});
}

function normalizedToolID(tool:String):String {
	return tool == "patch" ? "apply_patch" : tool;
}

function pushUnique(values:Array<String>, value:String):Void {
	if (values.indexOf(value) == -1)
		values.push(value);
}
