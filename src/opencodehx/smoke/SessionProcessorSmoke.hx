package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptMessage;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPart;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptPartType;
import opencodehx.externs.ai.AiSdk.AiLanguageModelPromptRole;
import opencodehx.externs.ai.AiSdk.AiLanguageModelTool;
import opencodehx.externs.ai.AiSdk.AiTool;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionAskRecord;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.provider.AiSdkProvider;
import opencodehx.provider.AiSdkProvider.AiSdkMockModel;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderMessage;
import opencodehx.provider.ProviderTypes.ProviderMessageContent;
import opencodehx.provider.ProviderTypes.ProviderMessageRole;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.SessionID;
import opencodehx.session.SessionLlm;
import opencodehx.session.SessionProcessor;
import opencodehx.session.SessionRetry.SessionProviderError;
import opencodehx.storage.SqliteSessionStore;
import js.lib.Promise;

typedef ExpectedToolPromptTurn = {
	final callID:String;
	final toolName:String;
	final outputFragment:String;
}

class SessionProcessorSmoke {
	public static function run():Void {
		llmHasToolCalls();
		llmResolveTools();
		llmRepairToolCall();
		llmRequestOptions();
		llmRequestParams();
		llmStreamTextOptions();
		llmWorkflowApproval();
		llmWorkflowToolExecutor();
		llmTransformStreamPrompt();
		llmTelemetryOptions();
		llmStreamFailureError();
		llmCompatibilityTools();
		llmRequestHeaders();
		llmSystemMessages();
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-session-processor-"));
		final dbPath = NodePath.join(root, "opencodehx.db");
		final store = new SqliteSessionStore(dbPath);
		try {
			Fs.mkdirSync(NodePath.join(root, "src"), {recursive: true});
			Fs.writeFileSync(NodePath.join(root, "src/input.txt"), "session processor fixture\n");
			final prompts:Array<PermissionAskRecord> = [];
			final permission = new PermissionRuntime({
				sessionID: SessionProcessor.SESSION_ID,
				messageID: SessionProcessor.ASSISTANT_ID,
				callID: "call_read_one",
				ruleset: [{permission: "read", pattern: "*", action: "ask"}],
				prompt: request -> {
					prompts.push(request);
					return {reply: "once"};
				}
			});
			final result = SessionProcessor.run({
				prompt: "Read the fixture file.",
				directory: root,
				store: store,
				permission: permission,
				toolCall: {
					id: "call_read_one",
					tool: "read",
					input: {filePath: "src/input.txt"},
				},
			});

			eq(result.messages.length, 2, "processor message count");
			eq(result.events.length, 5, "processor event count");
			eq(result.events[3].type, "tool-call-start", "tool start event");
			eq(prompts.length, 1, "permission prompt count");
			eq(prompts[0].permission, "read", "permission name");
			eq(prompts[0].tool.messageID, SessionProcessor.ASSISTANT_ID, "permission message id");
			assertAssistant(result.messages[1].info);
			assertAssistantParts(result.messages[1].parts, "sync tool", "call_read_one", "Hello from the fake provider.");
			assertToolOutcome(result.tool);

			final page = store.pageMessages(SessionID.make(SessionProcessor.SESSION_ID), 10);
			eq(page.items.length, 2, "stored message count");
			eq(page.items[1].parts.length, 4, "stored assistant parts");
			final recovered = SessionProcessor.recover(store, SessionProcessor.SESSION_ID, 10);
			eq(recovered.session.directory, root, "recovered session directory");
			eq(recovered.messages.length, 2, "recovered message count");
			retryOverflowAndRecovery(store, root);
			abortFlow(root);
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup must catch arbitrary Haxe/JS failures so the temp
			// database is removed before rethrowing the original assertion error.
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function llmHasToolCalls():Void {
		eq(SessionLlm.hasToolCalls([]), false, "llm hasToolCalls empty");
		eq(SessionLlm.hasToolCalls([
			{
				role: AiLanguageModelPromptRole.User,
				content: [{type: AiLanguageModelPromptPartType.Text, text: "Hello"}],
			},
			{
				role: AiLanguageModelPromptRole.Assistant,
				content: [{type: AiLanguageModelPromptPartType.Text, text: "Hi there"}],
			},
		]), false, "llm hasToolCalls text parts");
		eq(SessionLlm.hasToolCalls([
			{
				role: AiLanguageModelPromptRole.Assistant,
				content: [
					{
						type: AiLanguageModelPromptPartType.ToolCall,
						toolCallId: "call-123",
						toolName: "bash",
						input: Unknown.fromBoundary({command: "pwd"}),
					}
				],
			},
		]), true, "llm hasToolCalls tool-call");
		eq(SessionLlm.hasToolCalls([
			{
				role: AiLanguageModelPromptRole.Tool,
				content: [
					{
						type: AiLanguageModelPromptPartType.ToolResult,
						toolCallId: "call-123",
						toolName: "bash",
						output: {type: "text", value: "done"},
					}
				],
			},
		]), true, "llm hasToolCalls tool-result");
		eq(SessionLlm.hasToolCalls([
			{
				role: AiLanguageModelPromptRole.User,
				content: "Hello world",
			},
			{
				role: AiLanguageModelPromptRole.Assistant,
				content: "Hi there",
			},
		]), false, "llm hasToolCalls string content");
		eq(SessionLlm.hasToolCalls([
			{
				role: AiLanguageModelPromptRole.Assistant,
				content: [
					{type: AiLanguageModelPromptPartType.Text, text: "Let me run that command"},
					{
						type: AiLanguageModelPromptPartType.ToolCall,
						toolCallId: "call-456",
						toolName: "read",
						input: Unknown.fromBoundary({filePath: "README.md"}),
					}
				],
			},
		]), true, "llm hasToolCalls mixed content");
	}

	static function llmResolveTools():Void {
		final tools = new DynamicAccess<AiTool>();
		tools.set("question", AiSdkProvider.readTool());
		tools.set("read", AiSdkProvider.readTool());
		final userTools = new DynamicAccess<Bool>();
		userTools.set("question", true);
		userTools.set("read", false);
		final agentDenyQuestion:Array<PermissionRule> = [{permission: "question", pattern: "*", action: "deny"}];
		final promptAllowQuestion:Array<PermissionRule> = [{permission: "question", pattern: "*", action: "allow"}];
		final resolved = SessionLlm.resolveTools(tools, agentDenyQuestion, promptAllowQuestion, userTools);
		eq(hasAiTool(resolved, "question"), true, "llm resolve prompt allow keeps tool");
		eq(hasAiTool(resolved, "read"), false, "llm resolve user false hides tool");

		final denied = SessionLlm.resolveTools(tools, agentDenyQuestion, [], userTools);
		eq(hasAiTool(denied, "question"), false, "llm resolve agent deny removes tool");

		final promptDenyQuestion:Array<PermissionRule> = [{permission: "question", pattern: "*", action: "deny"}];
		final agentAllowQuestion:Array<PermissionRule> = [{permission: "question", pattern: "*", action: "allow"}];
		final promptDenied = SessionLlm.resolveTools(tools, agentAllowQuestion, promptDenyQuestion, userTools);
		eq(hasAiTool(promptDenied, "question"), false, "llm resolve prompt deny overrides agent allow");

		tools.set(SessionLlm.INVALID_TOOL_ID, AiSdkProvider.readTool());
		final activeNames = SessionLlm.activeToolNames(tools);
		eq(hasString(activeNames, "question"), true, "llm active tools keeps normal tool");
		eq(hasString(activeNames, "read"), true, "llm active tools keeps read");
		eq(hasString(activeNames, SessionLlm.INVALID_TOOL_ID), false, "llm active tools skips invalid");

		final workflowTools = new DynamicAccess<AiTool>();
		workflowTools.set("read", AiSdkProvider.readTool());
		workflowTools.set("question", AiSdkProvider.readTool());
		workflowTools.set("bash", AiSdkProvider.readTool());
		final workflowAgent:Array<PermissionRule> = [
			{permission: "*", pattern: "*", action: "ask"},
			{permission: "read", pattern: "*", action: "allow"}
		];
		final workflowPrompt:Array<PermissionRule> = [{permission: "question", pattern: "*", action: "deny"}];
		final preapproved = SessionLlm.workflowPreapprovedTools(workflowTools, workflowAgent, workflowPrompt);
		eq(hasString(preapproved, "read"), true, "llm workflow preapproved allow");
		eq(hasString(preapproved, "question"), true, "llm workflow preapproved deny still preapproved");
		eq(hasString(preapproved, "bash"), false, "llm workflow preapproved ask excluded");

		final promptAsk:Array<PermissionRule> = [{permission: "read", pattern: "*", action: "ask"}];
		final promptAskResult = SessionLlm.workflowPreapprovedTools(workflowTools, workflowAgent, promptAsk);
		eq(hasString(promptAskResult, "read"), false, "llm workflow preapproved prompt ask wins");
		eq(SessionLlm.workflowPreapprovedTools(workflowTools, [], []).length, 3, "llm workflow preapproved no rules includes all");

		final state = SessionLlm.workflowModelState("ses_workflow", ["system header", "plugin tail"], workflowTools, workflowAgent, workflowPrompt);
		eq(state.sessionID, "ses_workflow", "llm workflow state session id");
		eq(state.systemPrompt, "system header\nplugin tail", "llm workflow state system prompt");
		eq(state.sessionPreapprovedTools.join(","), "read,question", "llm workflow state preapproved tools");
	}

	static function llmRepairToolCall():Void {
		final tools = new DynamicAccess<AiTool>();
		tools.set("read", AiSdkProvider.readTool());

		final repaired = SessionLlm.repairToolCall({
			toolCallId: "call_upper",
			toolName: "READ",
			input: '{"filePath":"README.md"}',
		}, tools, "Tool READ not found");
		eq(repaired.toolCallId, "call_upper", "llm repair preserves call id");
		eq(repaired.toolName, "read", "llm repair lower-case known tool");
		eq(repaired.input, '{"filePath":"README.md"}', "llm repair preserves input");

		final invalid = SessionLlm.repairToolCall({
			toolCallId: "call_unknown",
			toolName: "missingTool",
			input: "{}",
		}, tools, "Missing tool");
		eq(invalid.toolCallId, "call_unknown", "llm repair invalid preserves call id");
		eq(invalid.toolName, SessionLlm.INVALID_TOOL_ID, "llm repair invalid tool name");
		eq(invalid.input, '{"tool":"missingTool","error":"Missing tool"}', "llm repair invalid input");

		final lowerKnown = SessionLlm.repairToolCall({
			toolName: "read",
			input: "{}",
		}, tools, "Already lower-case failure");
		eq(lowerKnown.toolName, SessionLlm.INVALID_TOOL_ID, "llm repair lower-case failed call stays invalid");
		eq(lowerKnown.input, '{"tool":"read","error":"Already lower-case failure"}', "llm repair lower-case invalid input");
	}

	static function llmRequestOptions():Void {
		final modelOptions = optionMap();
		modelOptions.set("store", true);
		modelOptions.set("nested", record2("fromBase", "model", "keepModel", true));
		final variants = new DynamicAccess<ProviderOptions>();
		variants.set("high", record2("reasoningEffort", "high", "nested", record2("fromVariant", true, "keepModel", false)));
		final model = modelWithOptionsVariants("openai", "gpt-5.2", "@ai-sdk/openai", modelOptions, variants);
		final agentOptions = record2("textVerbosity", "high", "nested", record2("fromAgent", "yes", "fromBase", "agent"));
		final options = SessionLlm.requestOptions({
			model: model,
			sessionID: "ses_options",
			small: false,
			isOpenaiOauth: true,
			system: ["system header", "plugin tail"],
			providerOptions: record1("setCacheKey", true),
			agentOptions: agentOptions,
			variant: "high",
		});
		eq(options.get("promptCacheKey"), "ses_options", "llm options provider base");
		eq(options.get("store"), true, "llm options model overrides base");
		eq(options.get("reasoningEffort"), "high", "llm options variant overrides generated");
		eq(options.get("textVerbosity"), "high", "llm options agent applied");
		eq(options.get("instructions"), "system header\nplugin tail", "llm options oauth instructions");
		final nested:Dynamic = options.get("nested");
		eq(Reflect.field(nested, "fromBase"), "agent", "llm options nested agent overrides model");
		eq(Reflect.field(nested, "fromAgent"), "yes", "llm options nested agent key");
		eq(Reflect.field(nested, "fromVariant"), true, "llm options nested variant key");
		eq(Reflect.field(nested, "keepModel"), false, "llm options nested variant overrides model");

		final small = SessionLlm.requestOptions({
			model: model,
			sessionID: "ses_small",
			small: true,
			isOpenaiOauth: false,
			system: ["ignored"],
			agentOptions: record1("agentSmall", true),
			variant: "high",
		});
		eq(small.get("reasoningEffort"), "low", "llm options small base effort");
		eq(small.get("agentSmall"), true, "llm options small agent option");
		eq(small.get("instructions"), null, "llm options non-oauth omits instructions");
		final smallNested:Dynamic = small.get("nested");
		eq(Reflect.field(smallNested, "fromVariant"), null, "llm options small skips variant");

		final missingVariant = SessionLlm.requestOptions({
			model: model,
			sessionID: "ses_missing_variant",
			small: false,
			isOpenaiOauth: false,
			system: [],
			variant: "missing",
		});
		eq(missingVariant.get("reasoningEffort"), "medium", "llm options missing variant keeps base");
	}

	static function llmRequestParams():Void {
		final options = record1("requestOption", true);
		final overrideModel = modelWithOptionsVariants("openai", "gpt-5.2", "@ai-sdk/openai", optionMap(), new DynamicAccess<ProviderOptions>());
		final overrideParams = SessionLlm.requestParams({
			model: overrideModel,
			options: options,
			agentTemperature: 0.2,
			agentTopP: 0.8,
		});
		eq(overrideParams.temperature.orNull(), 0.2, "llm params agent temperature override");
		eq(overrideParams.topP.orNull(), 0.8, "llm params agent topP override");
		eq(overrideParams.topK.orNull(), null, "llm params absent topK");
		eq(overrideParams.maxOutputTokens, 10000.0, "llm params max output");
		eq(overrideParams.options.get("requestOption"), true, "llm params preserves options");

		final fallbackModel = modelWithOptionsVariants("qwen", "qwen3-coder", "@ai-sdk/openai-compatible", optionMap(), new DynamicAccess<ProviderOptions>());
		final fallbackParams = SessionLlm.requestParams({
			model: fallbackModel,
			options: optionMap(),
		});
		eq(fallbackParams.temperature.orNull(), 0.55, "llm params provider temperature fallback");
		eq(fallbackParams.topP.orNull(), 1.0, "llm params provider topP fallback");

		final disabledTemp = modelWithTemperatureCapability("google", "gemini-3-pro", "@ai-sdk/google", false);
		final disabledParams = SessionLlm.requestParams({
			model: disabledTemp,
			options: optionMap(),
		});
		eq(disabledParams.temperature.orNull(), null, "llm params temperature capability disabled");
		eq(disabledParams.topP.orNull(), 0.95, "llm params topP still applies");
		eq(disabledParams.topK.orNull(), 64.0, "llm params topK fallback");
	}

	static function llmStreamTextOptions():Void {
		final tools = new DynamicAccess<AiTool>();
		tools.set("read", AiSdkProvider.readTool());
		tools.set(SessionLlm.INVALID_TOOL_ID, AiSdkProvider.readTool());
		final headers = new DynamicAccess<String>();
		headers.set("x-session-affinity", "ses_stream_options");
		final model = modelWithOptionsVariants("vercel", "claude-sonnet-4", "@ai-sdk/gateway", optionMap(), new DynamicAccess<ProviderOptions>());
		final params = SessionLlm.requestParams({
			model: model,
			options: record1("reasoningEffort", "high"),
		});
		final options = SessionLlm.streamTextOptions({
			model: model,
			params: params,
			tools: tools,
			headers: headers,
			retries: 2,
			toolChoice: "required",
		});
		eq(options.temperature.orNull(), params.temperature.orNull(), "llm stream options temperature");
		eq(options.providerOptions.exists("gateway"), true, "llm stream options provider routing");
		eq(options.activeTools.join(","), "read", "llm stream options active tools");
		eq(options.toolChoice, "required", "llm stream options tool choice");
		eq(options.maxRetries, 2, "llm stream options explicit retries");
		eq(options.headers.get("x-session-affinity"), "ses_stream_options", "llm stream options headers");

		final defaults = SessionLlm.streamTextOptions({
			model: model,
			params: params,
			tools: tools,
			headers: headers,
		});
		eq(defaults.maxRetries, 0, "llm stream options retry default");
		eq(Reflect.field(defaults, "toolChoice"), null, "llm stream options absent tool choice");
	}

	static function llmWorkflowApproval():Void {
		final tools = [
			{name: "read", args: '{"title":"README.md"}'},
			{name: "bash", args: '{"name":"npm test"}'},
			{name: "read", args: '{"title":"README.md"}'},
			{name: "grep", args: "{not json}"},
			{name: "write", args: '{"title":null,"name":"output.txt"}'},
			{name: "edit", args: '{"title":true}'},
			{name: "noop", args: '{"title":0,"name":"ignored"}'},
		];
		final names = SessionLlm.workflowApprovalNames(tools);
		eq(names.join(","), "read,bash,grep,write,edit,noop", "llm workflow approval unique names");

		final patterns = SessionLlm.workflowApprovalPatterns(tools);
		eq(patterns.join("|"), "read: README.md|bash: npm test|grep|write: output.txt|edit: true|noop", "llm workflow approval patterns");

		eq(SessionLlm.workflowAlreadyApproved([{name: "read", args: "{}"}, {name: "read", args: "{}"}], ["read"]), true,
			"llm workflow already approved duplicate");
		eq(SessionLlm.workflowAlreadyApproved([{name: "read", args: "{}"}, {name: "bash", args: "{}"}], ["read"]), false, "llm workflow missing approval");

		final remembered = SessionLlm.rememberWorkflowApproval(["read"], ["read"], [{name: "read", args: "{}"}, {name: "bash", args: "{}"}]);
		eq(remembered.approved.join(","), "read,bash", "llm workflow approval set update");
		eq(remembered.preapproved.join(","), "read,read,bash", "llm workflow preapproved appends upstream names");
	}

	static function llmWorkflowToolExecutor():Void {
		final unknown = SessionLlm.workflowUnknownToolResult("missing");
		eq(unknown.result, "", "llm workflow tool unknown empty result");
		eq(unknown.error, "Unknown tool: missing", "llm workflow tool unknown error");

		final stringResult = SessionLlm.workflowToolExecutionResult(Unknown.fromBoundary("plain output"));
		eq(stringResult.result, "plain output", "llm workflow tool string result");
		eq(Reflect.field(stringResult, "title"), null, "llm workflow tool string no title");

		final objectResult = SessionLlm.workflowToolExecutionResult(Unknown.fromBoundary({
			output: "file contents",
			title: "Read README",
			metadata: {lines: 3},
		}));
		eq(objectResult.result, "file contents", "llm workflow tool object output");
		eq(objectResult.title, "Read README", "llm workflow tool object title");
		eq(Reflect.field(objectResult.metadata, "lines"), 3, "llm workflow tool object metadata");

		final fallback = SessionLlm.workflowToolExecutionResult(Unknown.fromBoundary({title: "Only title"}));
		eq(fallback.result, '{"title":"Only title"}', "llm workflow tool object json fallback");

		final failed = SessionLlm.workflowToolExecutionError(Unknown.fromBoundary(new js.lib.Error("boom")));
		eq(failed.result, "", "llm workflow tool error empty result");
		eq(failed.error, "boom", "llm workflow tool error message");
	}

	static function llmTransformStreamPrompt():Void {
		final prompt = [
			providerMessage(ProviderMessageRole.System, providerTextContent("")),
			providerMessage(ProviderMessageRole.User, providerTextContent("hello")),
		];
		final model = modelWithOptionsVariants("anthropic", "claude-sonnet-4", "@ai-sdk/anthropic", optionMap(), new DynamicAccess<ProviderOptions>());
		final nonStream = SessionLlm.transformStreamPrompt("generate", prompt, model, optionMap());
		eq(nonStream.length, 2, "llm transform non-stream keeps count");
		eq(nonStream[0].content, "", "llm transform non-stream keeps empty system");

		final stream = SessionLlm.transformStreamPrompt("stream", prompt, model, optionMap());
		eq(stream.length, 1, "llm transform stream filters empty anthropic content");
		eq(stream[0].role, ProviderMessageRole.User, "llm transform stream keeps user message");
	}

	static function llmTelemetryOptions():Void {
		final disabled = SessionLlm.telemetryOptions({
			sessionID: "ses_telemetry_default",
		});
		eq(disabled.isEnabled.orNull(), null, "llm telemetry absent enabled");
		eq(disabled.functionId, "session.llm", "llm telemetry function id");
		eq(disabled.metadata.userId, "unknown", "llm telemetry username fallback");
		eq(disabled.metadata.sessionId, "ses_telemetry_default", "llm telemetry session metadata");
		eq(disabled.tracer.orNull() == null, true, "llm telemetry absent tracer");

		final enabled = SessionLlm.telemetryOptions({
			sessionID: "ses_telemetry_enabled",
			openTelemetry: true,
			username: "fixture-user",
			tracer: Unknown.fromBoundary({kind: "tracer"}),
		});
		eq(enabled.isEnabled.orNull(), true, "llm telemetry enabled");
		eq(enabled.metadata.userId, "fixture-user", "llm telemetry username");
		eq(enabled.tracer.orNull() == null, false, "llm telemetry tracer passthrough");
	}

	static function llmStreamFailureError():Void {
		final native = new js.lib.Error("native failure");
		final same = SessionLlm.streamFailureError(Unknown.fromBoundary(native));
		eq(same == native, true, "llm stream failure keeps native error");
		eq(same.message, "native failure", "llm stream failure native message");

		final text = SessionLlm.streamFailureError(Unknown.fromBoundary("string failure"));
		eq(text.message, "string failure", "llm stream failure string message");

		final number = SessionLlm.streamFailureError(Unknown.fromBoundary(42));
		eq(number.message, "42", "llm stream failure number message");
	}

	static function llmCompatibilityTools():Void {
		final empty = new DynamicAccess<AiTool>();
		final withHistoryToolCall:Array<AiLanguageModelPromptMessage> = [
			{
				role: AiLanguageModelPromptRole.Assistant,
				content: [
					{
						type: AiLanguageModelPromptPartType.ToolCall,
						toolCallId: "call-history",
						toolName: "read",
						input: Unknown.fromBoundary({filePath: "README.md"}),
					}
				],
			}
		];

		final litellm = modelForCompatibility("litellm-gateway", "chat-model");
		final litellmTools = SessionLlm.compatibilityTools(litellm, empty, withHistoryToolCall);
		eq(hasAiTool(litellmTools, SessionLlm.NOOP_TOOL_ID), true, "llm compatibility litellm noop");
		eq(hasAiTool(empty, SessionLlm.NOOP_TOOL_ID), false, "llm compatibility keeps source unmodified");

		final apiLiteLlm = modelForCompatibility("custom-provider", "company-litellm-model");
		eq(hasAiTool(SessionLlm.compatibilityTools(apiLiteLlm, empty, withHistoryToolCall), SessionLlm.NOOP_TOOL_ID), true, "llm compatibility api id noop");

		final optionLiteLlm = modelForCompatibility("custom-provider", "chat-model", true);
		eq(hasAiTool(SessionLlm.compatibilityTools(optionLiteLlm, empty, withHistoryToolCall), SessionLlm.NOOP_TOOL_ID), true, "llm compatibility option noop");

		final copilot = modelForCompatibility("github-copilot", "gpt-5.2");
		eq(hasAiTool(SessionLlm.compatibilityTools(copilot, empty, withHistoryToolCall), SessionLlm.NOOP_TOOL_ID), true, "llm compatibility copilot noop");

		final normal = modelForCompatibility("openai", "gpt-5.2");
		eq(hasAiTool(SessionLlm.compatibilityTools(normal, empty, withHistoryToolCall), SessionLlm.NOOP_TOOL_ID), false,
			"llm compatibility normal provider no noop");

		final withoutHistoryTool:Array<AiLanguageModelPromptMessage> = [{role: AiLanguageModelPromptRole.User, content: "Hello"}];
		eq(hasAiTool(SessionLlm.compatibilityTools(litellm, empty, withoutHistoryTool), SessionLlm.NOOP_TOOL_ID), false,
			"llm compatibility no history tool no noop");

		final active = AiSdkProvider.toolSet("read", AiSdkProvider.readTool());
		final activeResult = SessionLlm.compatibilityTools(litellm, active, withHistoryToolCall);
		eq(hasAiTool(activeResult, "read"), true, "llm compatibility preserves active tool");
		eq(hasAiTool(activeResult, SessionLlm.NOOP_TOOL_ID), false, "llm compatibility active tools skip noop");
	}

	static function llmRequestHeaders():Void {
		final source = new FakeProvider().model;
		final modelHeaders = new DynamicAccess<String>();
		modelHeaders.set("x-model-header", "model");
		modelHeaders.set("x-session-affinity", "model-affinity");
		modelHeaders.set("User-Agent", "model-agent");
		final providerModel = modelWithHeaders("openai", source.api.id, modelHeaders);
		final pluginHeaders = new DynamicAccess<String>();
		pluginHeaders.set("x-plugin-header", "plugin");
		pluginHeaders.set("User-Agent", "plugin-agent");
		final headers = SessionLlm.requestHeaders({
			model: providerModel,
			sessionID: "ses_headers",
			parentSessionID: "ses_parent",
			userID: "msg_user",
			projectID: "proj_123",
			client: "cli",
			installationVersion: "9.8.7",
			headers: pluginHeaders,
		});
		eq(headers.get("x-session-affinity"), "model-affinity", "llm headers model overrides affinity");
		eq(headers.get("x-parent-session-id"), "ses_parent", "llm headers parent session");
		eq(headers.get("User-Agent"), "plugin-agent", "llm headers plugin overrides model");
		eq(headers.get("x-model-header"), "model", "llm headers keeps model header");
		eq(headers.get("x-plugin-header"), "plugin", "llm headers keeps plugin header");

		final plainHeaders = SessionLlm.requestHeaders({
			model: modelWithHeaders("openai", source.api.id, new DynamicAccess<String>()),
			sessionID: "ses_plain",
			userID: "msg_plain",
			projectID: "proj_plain",
			client: "desktop",
			installationVersion: "1.2.3",
		});
		eq(plainHeaders.get("x-session-affinity"), "ses_plain", "llm headers default affinity");
		eq(plainHeaders.get("x-parent-session-id"), null, "llm headers omits missing parent");
		eq(plainHeaders.get("User-Agent"), "opencode/1.2.3", "llm headers default user agent");

		final opencodeHeaders = new DynamicAccess<String>();
		opencodeHeaders.set("x-opencode-client", "plugin-client");
		final opencode = SessionLlm.requestHeaders({
			model: modelWithHeaders("opencode", source.api.id, new DynamicAccess<String>()),
			sessionID: "ses_opencode",
			userID: "msg_opencode",
			projectID: "proj_opencode",
			client: "cli",
			installationVersion: "1.2.3",
			headers: opencodeHeaders,
		});
		eq(opencode.get("x-opencode-project"), "proj_opencode", "llm headers opencode project");
		eq(opencode.get("x-opencode-session"), "ses_opencode", "llm headers opencode session");
		eq(opencode.get("x-opencode-request"), "msg_opencode", "llm headers opencode request");
		eq(opencode.get("x-opencode-client"), "plugin-client", "llm headers plugin overrides opencode client");
		eq(opencode.get("x-session-affinity"), null, "llm headers opencode omits affinity");
		eq(opencode.get("User-Agent"), null, "llm headers opencode omits user agent");
	}

	static function llmSystemMessages():Void {
		final fallback = SessionLlm.composeSystem({
			provider: ["provider one", "", "provider two"],
			input: ["call scoped"],
			userSystem: "user scoped",
		});
		eq(fallback.length, 1, "llm system fallback count");
		eq(fallback[0], "provider one\nprovider two\ncall scoped\nuser scoped", "llm system fallback content");

		final agent = SessionLlm.composeSystem({
			agentPrompt: "agent prompt",
			provider: ["provider ignored"],
			input: ["call scoped"],
			userSystem: "",
		});
		eq(agent[0], "agent prompt\ncall scoped", "llm system agent replaces provider");

		final empty = SessionLlm.composeSystem({
			provider: [],
			input: [],
		});
		eq(empty.length, 1, "llm system empty count");
		eq(empty[0], "", "llm system empty joins to blank");

		final unchanged = ["header", "plugin one", "plugin two"];
		final rejoined = SessionLlm.finalizeSystemTransform("header", unchanged);
		eq(rejoined.length, 2, "llm system transform rejoin count");
		eq(rejoined[0], "header", "llm system transform header");
		eq(rejoined[1], "plugin one\nplugin two", "llm system transform rest");

		final changedHeader = SessionLlm.finalizeSystemTransform("header", ["replacement", "plugin one", "plugin two"]);
		eq(changedHeader.length, 3, "llm system transform changed header untouched");
		eq(changedHeader[0], "replacement", "llm system transform changed header first");

		final messages:Array<AiLanguageModelPromptMessage> = [{role: AiLanguageModelPromptRole.User, content: "Hello"}];
		final withSystem = SessionLlm.requestMessages(["system one", "system two"], messages, false, false);
		eq(withSystem.length, 3, "llm request messages prepends system count");
		eq(withSystem[0].role, AiLanguageModelPromptRole.System, "llm request messages first role");
		eq(withSystem[0].content, "system one", "llm request messages first content");
		eq(withSystem[1].content, "system two", "llm request messages second content");
		eq(withSystem[2].role, AiLanguageModelPromptRole.User, "llm request messages user role");

		final oauth = SessionLlm.requestMessages(["system"], messages, true, false);
		eq(oauth.length, 1, "llm request messages oauth skip count");
		eq(oauth[0].content, "Hello", "llm request messages oauth original");

		final workflow = SessionLlm.requestMessages(["system"], messages, false, true);
		eq(workflow.length, 1, "llm request messages workflow skip count");
		eq(workflow[0].content, "Hello", "llm request messages workflow original");
	}

	static function hasAiTool(tools:DynamicAccess<AiTool>, name:String):Bool {
		for (key in tools.keys()) {
			if (key == name)
				return true;
		}
		return false;
	}

	static function hasString(items:Array<String>, expected:String):Bool {
		for (item in items) {
			if (item == expected)
				return true;
		}
		return false;
	}

	static function modelForCompatibility(providerID:String, apiID:String, ?litellmProxy:Bool):ProviderModel {
		final source = new FakeProvider().model;
		final options = new DynamicAccess<Dynamic>();
		if (litellmProxy != null)
			options.set("litellmProxy", litellmProxy);
		return {
			id: source.id,
			providerID: ProviderID.make(providerID),
			name: source.name,
			capabilities: source.capabilities,
			api: {
				id: apiID,
				url: source.api.url,
				npm: source.api.npm,
			},
			cost: source.cost,
			limit: source.limit,
			status: source.status,
			options: options,
			headers: source.headers,
			release_date: source.release_date,
			variants: source.variants,
		};
	}

	static function modelWithHeaders(providerID:String, apiID:String, headers:DynamicAccess<String>):ProviderModel {
		final source = new FakeProvider().model;
		return {
			id: source.id,
			providerID: ProviderID.make(providerID),
			name: source.name,
			capabilities: source.capabilities,
			api: {
				id: apiID,
				url: source.api.url,
				npm: source.api.npm,
			},
			cost: source.cost,
			limit: source.limit,
			status: source.status,
			options: source.options,
			headers: headers,
			release_date: source.release_date,
			variants: source.variants,
		};
	}

	static function modelWithOptionsVariants(providerID:String, apiID:String, npm:String, options:ProviderOptions,
			variants:DynamicAccess<ProviderOptions>):ProviderModel {
		final source = new FakeProvider().model;
		return {
			id: apiID,
			providerID: ProviderID.make(providerID),
			name: source.name,
			capabilities: source.capabilities,
			api: {
				id: apiID,
				url: source.api.url,
				npm: npm,
			},
			cost: source.cost,
			limit: source.limit,
			status: source.status,
			options: options,
			headers: source.headers,
			release_date: source.release_date,
			variants: variants,
		};
	}

	static function modelWithTemperatureCapability(providerID:String, apiID:String, npm:String, temperature:Bool):ProviderModel {
		final source = new FakeProvider().model;
		return {
			id: apiID,
			providerID: ProviderID.make(providerID),
			name: source.name,
			capabilities: {
				toolcall: source.capabilities.toolcall,
				attachment: source.capabilities.attachment,
				reasoning: source.capabilities.reasoning,
				temperature: temperature,
				interleaved: source.capabilities.interleaved,
				input: source.capabilities.input,
				output: source.capabilities.output,
			},
			api: {
				id: apiID,
				url: source.api.url,
				npm: npm,
			},
			cost: source.cost,
			limit: source.limit,
			status: source.status,
			options: optionMap(),
			headers: source.headers,
			release_date: source.release_date,
			variants: new DynamicAccess<ProviderOptions>(),
		};
	}

	static function optionMap():ProviderOptions {
		return new DynamicAccess<Dynamic>();
	}

	static function record1<T>(key:String, value:T):ProviderOptions {
		final out = optionMap();
		out.set(key, value);
		return out;
	}

	static function record2<A, B>(keyA:String, valueA:A, keyB:String, valueB:B):ProviderOptions {
		final out = optionMap();
		out.set(keyA, valueA);
		out.set(keyB, valueB);
		return out;
	}

	static function providerMessage(role:ProviderMessageRole, content:ProviderMessageContent):ProviderMessage {
		return {role: role, content: content};
	}

	static function providerTextContent(text:String):ProviderMessageContent {
		return text;
	}

	@:async
	public static function runAsync():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-session-processor-async-"));
		try {
			Fs.mkdirSync(NodePath.join(root, "src"), {recursive: true});
			Fs.writeFileSync(NodePath.join(root, "src/input.txt"), "ai sdk tool fixture\n");
			final fixture = new FakeProvider();
			final result = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_one",
				prompt: "Say hello through the SDK runtime.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: AiSdkMockModel.text(["Hello ", "from the AI SDK session."]),
			});
			eq(result.provider.id, "openai", "ai sdk session provider");
			eq(result.request.system[0], "You are an AI SDK provider runtime.", "ai sdk session system");
			eq(result.events.length, 4, "ai sdk session event count");
			eq(result.events[0].type, "start", "ai sdk session start event");
			eq(result.events[1].text, "Hello ", "ai sdk session first delta");
			switch result.messages[1].info {
				case AssistantInfo(assistant):
					eq(assistant.modelID, "gpt-5.2", "ai sdk session assistant model");
					eq(assistant.tokens.total, 7.0, "ai sdk session total tokens");
				case _:
					throw "session processor async: expected assistant info";
			}
			switch result.messages[1].parts[0] {
				case TextPart(text):
					eq(text.text, "Hello from the AI SDK session.", "ai sdk session text");
				case _:
					throw "session processor async: expected assistant text";
			}
			final errorResult = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_error",
				prompt: "Fail through the SDK runtime.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: AiSdkMockModel.error("fixture provider error"),
			});
			eq(errorResult.events[1].type, "error", "ai sdk error event type");
			eq(errorResult.events[1].message, "fixture provider error", "ai sdk error event message");
			eq(errorResult.events[2].type, "finish", "ai sdk error finish event");
			eq(errorResult.events[2].reason, "error", "ai sdk error finish reason");

			final abortResult = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_abort",
				prompt: "Abort through the SDK runtime.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: AiSdkMockModel.abortable(),
				abortStreamImmediately: true,
			});
			eq(abortResult.aborted == true, true, "ai sdk abort result flag");
			eq(hasSessionEvent(abortResult.events, "abort", AiSdkProvider.ABORT_REASON), true, "ai sdk abort event");
			switch abortResult.messages[1].info {
				case AssistantInfo(assistant):
					eq(Reflect.field(assistant.error, "name"), "AbortedError", "ai sdk abort assistant error");
				case _:
					throw "session processor async: expected abort assistant info";
			}
			switch abortResult.messages[1].parts[0] {
				case TextPart(text):
					eq(text.text, "Request aborted.", "ai sdk abort assistant text");
				case _:
					throw "session processor async: expected abort text";
			}
			final runtime = AiSdkMockModel.inspectableToolThenText("The file says: ai sdk tool fixture.", "read", "{\"filePath\":\"src/input.txt\"}");
			final toolResult = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_tool",
				prompt: "Read the AI SDK fixture.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: runtime.language,
			});
			eq(hasLanguageTool(runtime.mock.doStreamCalls[0].tools, "read"), true, "ai sdk session advertises read tool");
			eq(hasLanguageTool(runtime.mock.doStreamCalls[1].tools, "read"), true, "ai sdk continuation advertises read tool");
			assertSdkPrompt(runtime.mock.doStreamCalls[0].prompt, "Read the AI SDK fixture.", "ai sdk first call prompt");
			assertSdkToolResultPrompt(runtime.mock.doStreamCalls[1].prompt, "Read the AI SDK fixture.", "tool_1", "read", "ai sdk tool fixture",
				"ai sdk continuation prompt");
			eq(runtime.mock.doStreamCalls.length, 2, "ai sdk continuation call count");
			eq(toolResult.events[1].type, "tool-call", "ai sdk tool model event");
			eq(toolResult.events[3].type, "tool-call-start", "ai sdk tool execute start");
			eq(toolResult.events[4].status, "completed", "ai sdk tool execute finish");
			eq(toolResult.events[5].text, "The file says: ai sdk tool fixture.", "ai sdk continuation text event");
			assertToolOutcome(toolResult.tool);
			assertAssistantParts(toolResult.messages[1].parts, "ai sdk tool", "tool_1", "The file says: ai sdk tool fixture.");
			final multiRuntime = AiSdkMockModel.inspectableTwoToolsThenText("Both reads completed.", "read", "{\"filePath\":\"src/input.txt\"}", "read",
				"{\"filePath\":\"src/input.txt\"}");
			final multiToolResult = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_multi_tool",
				prompt: "Read the AI SDK fixture twice.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: multiRuntime.language,
			});
			eq(multiRuntime.mock.doStreamCalls.length, 3, "ai sdk multi-tool continuation call count");
			eq(hasLanguageTool(multiRuntime.mock.doStreamCalls[0].tools, "read"), true, "ai sdk multi-tool first call advertises read");
			eq(hasLanguageTool(multiRuntime.mock.doStreamCalls[1].tools, "read"), true, "ai sdk multi-tool second call advertises read");
			eq(hasLanguageTool(multiRuntime.mock.doStreamCalls[2].tools, "read"), true, "ai sdk multi-tool final call advertises read");
			assertSdkToolResultPrompt(multiRuntime.mock.doStreamCalls[1].prompt, "Read the AI SDK fixture twice.", "tool_1", "read", "ai sdk tool fixture",
				"ai sdk multi-tool first continuation prompt");
			assertSdkToolHistoryPrompt(multiRuntime.mock.doStreamCalls[2].prompt, "Read the AI SDK fixture twice.", [
				{
					callID: "tool_1",
					toolName: "read",
					outputFragment: "ai sdk tool fixture",
				},
				{
					callID: "tool_2",
					toolName: "read",
					outputFragment: "ai sdk tool fixture",
				}
			], "ai sdk multi-tool final prompt");
			eq(multiToolResult.events[5].callID, "tool_2", "ai sdk multi-tool second model call id");
			eq(multiToolResult.events[7].type, "tool-call-start", "ai sdk multi-tool execute second start");
			eq(multiToolResult.events[8].status, "completed", "ai sdk multi-tool execute second finish");
			eq(multiToolResult.events[9].text, "Both reads completed.", "ai sdk multi-tool final text event");
			assertToolOutcome(multiToolResult.tool);
			assertAssistantTwoToolParts(multiToolResult.messages[1].parts, "Both reads completed.");
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup must catch arbitrary Haxe/JS failures so the temp
			// directory is removed before rethrowing the original assertion error.
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function retryOverflowAndRecovery(store:SqliteSessionStore, root:String):Void {
		final headers:haxe.DynamicAccess<String> = {};
		headers.set("retry-after-ms", "0");
		final provider = new FakeProvider("Recovered after retry.");
		final tokens:TokenUsage = {
			input: 180000,
			output: 5000,
			reasoning: 0,
			cache: {read: 6000, write: 0},
		};
		final result = SessionProcessor.run({
			sessionID: "ses_retry_overflow",
			prompt: "Trigger retry and compaction.",
			directory: root,
			store: store,
			provider: provider,
			providerError: SessionProviderError.Api({
				message: "Provider is Overloaded",
				isRetryable: true,
				responseHeaders: headers,
			}),
			retryAttempt: 2,
			compaction: {
				config: ConfigInfo.empty("fixture"),
				model: provider.model,
				tokens: tokens,
			},
		});

		if (result.retry == null)
			throw "session processor: expected retry status";
		eq(result.retry.message, "Provider is overloaded", "retry message");
		eq(result.retry.nextDelay, 0.0, "retry delay from header");
		if (result.compaction == null)
			throw "session processor: expected compaction result";
		eq(result.compaction.overflow, true, "compaction overflow");
		eq(result.compaction.count, 191000.0, "compaction token count");
		assertCompactionPart(result.messages[0].parts, "runtime compaction part");
		assertRetryPart(result.messages[1].parts, "runtime retry part");

		final recovered = SessionProcessor.recover(store, "ses_retry_overflow", 10);
		eq(recovered.session.id.toString(), "ses_retry_overflow", "recovered retry session id");
		eq(recovered.messages.length, 2, "recovered retry messages");
		assertCompactionPart(recovered.messages[0].parts, "recovered compaction part");
		assertRetryPart(recovered.messages[1].parts, "recovered retry part");
	}

	static function abortFlow(root:String):Void {
		final result = SessionProcessor.run({
			sessionID: "ses_abort",
			prompt: "Abort me.",
			directory: root,
			aborted: true,
		});
		eq(result.aborted == true, true, "abort result flag");
		eq(result.events[1].type, "abort", "abort event");
		switch result.messages[1].info {
			case AssistantInfo(assistant):
				eq(Reflect.field(assistant.error, "name"), "AbortedError", "assistant abort error");
			case _:
				throw "session processor: expected aborted assistant";
		}
		switch result.messages[1].parts[0] {
			case TextPart(text):
				eq(text.text, "Request aborted.", "abort assistant text");
			case _:
				throw "session processor: expected abort text";
		}
	}

	static function assertAssistant(info:Info):Void {
		switch info {
			case AssistantInfo(assistant):
				eq(assistant.parentID.toString(), SessionProcessor.USER_ID, "assistant parent");
				eq(assistant.finish, "stop", "assistant finish");
			case _:
				throw "session processor: expected assistant info";
		}
	}

	static function assertAssistantParts(parts:Array<Part>, label:String, expectedCallID:String, expectedText:String):Void {
		eq(parts.length, 4, label + " assistant part count");
		switch parts[0] {
			case StepStartPart(_):
			case _:
				throw label + ": expected step-start part";
		}
		switch parts[1] {
			case ToolPart(tool):
				eq(tool.callID, expectedCallID, label + " tool call id");
				eq(tool.tool, "read", label + " tool name");
				assertCompleted(tool.state);
			case _:
				throw label + ": expected tool part";
		}
		switch parts[2] {
			case TextPart(text):
				eq(text.text, expectedText, label + " assistant text");
			case _:
				throw label + ": expected text part";
		}
		switch parts[3] {
			case StepFinishPart(finish):
				eq(finish.reason, "stop", label + " step finish reason");
			case _:
				throw label + ": expected step-finish part";
		}
	}

	static function assertAssistantTwoToolParts(parts:Array<Part>, expectedText:String):Void {
		eq(parts.length, 5, "multi-tool assistant part count");
		switch parts[0] {
			case StepStartPart(_):
			case _:
				throw "multi-tool: expected step-start part";
		}
		switch parts[1] {
			case ToolPart(tool):
				eq(tool.callID, "tool_1", "multi-tool first call id");
				assertCompleted(tool.state);
			case _:
				throw "multi-tool: expected first tool part";
		}
		switch parts[2] {
			case ToolPart(tool):
				eq(tool.callID, "tool_2", "multi-tool second call id");
				assertCompleted(tool.state);
			case _:
				throw "multi-tool: expected second tool part";
		}
		switch parts[3] {
			case TextPart(text):
				eq(text.text, expectedText, "multi-tool assistant text");
			case _:
				throw "multi-tool: expected text part";
		}
		switch parts[4] {
			case StepFinishPart(finish):
				eq(finish.reason, "stop", "multi-tool step finish reason");
			case _:
				throw "multi-tool: expected step-finish part";
		}
	}

	static function assertCompleted(state:ToolState):Void {
		switch state {
			case ToolCompleted(completed):
				eq(completed.output.indexOf("fixture") != -1, true, "tool output");
				eq(completed.title, "src/input.txt", "tool title");
			case _:
				throw "session processor: expected completed tool";
		}
	}

	static function assertToolOutcome(outcome:Null<opencodehx.session.SessionProcessor.SessionToolOutcome>):Void {
		if (outcome == null)
			throw "session processor: expected tool outcome";
		eq(outcome.success, true, "tool outcome success");
		eq(outcome.call.tool, "read", "tool outcome name");
	}

	static function hasLanguageTool(tools:Null<Array<AiLanguageModelTool>>, name:String):Bool {
		if (tools == null)
			return false;
		for (tool in tools) {
			if (tool.name == name)
				return true;
		}
		return false;
	}

	static function hasSessionEvent(events:Array<opencodehx.session.SessionProcessor.SessionEvent>, type:String, message:String):Bool {
		for (event in events) {
			if (event.type == type && event.message == message)
				return true;
		}
		return false;
	}

	static function assertSdkPrompt(prompt:Array<AiLanguageModelPromptMessage>, userText:String, label:String):Void {
		eq(prompt.length, 2, label + " count");
		eq(prompt[0].role, AiLanguageModelPromptRole.System, label + " system role");
		eq(promptContentText(prompt[0]), "You are an AI SDK provider runtime.", label + " system text");
		eq(prompt[1].role, AiLanguageModelPromptRole.User, label + " user role");
		eq(promptContentText(prompt[1]), userText, label + " user text");
	}

	static function assertSdkToolResultPrompt(prompt:Array<AiLanguageModelPromptMessage>, userText:String, callID:String, toolName:String,
			outputFragment:String, label:String):Void {
		assertSdkToolHistoryPrompt(prompt, userText, [{callID: callID, toolName: toolName, outputFragment: outputFragment}], label);
	}

	static function assertSdkToolHistoryPrompt(prompt:Array<AiLanguageModelPromptMessage>, userText:String, expected:Array<ExpectedToolPromptTurn>,
			label:String):Void {
		eq(prompt.length, 2 + expected.length * 2, label + " count");
		eq(prompt[0].role, AiLanguageModelPromptRole.System, label + " system role");
		eq(promptContentText(prompt[0]), "You are an AI SDK provider runtime.", label + " system text");
		eq(prompt[1].role, AiLanguageModelPromptRole.User, label + " user role");
		eq(promptContentText(prompt[1]), userText, label + " user text");
		for (index in 0...expected.length) {
			final turn = expected[index];
			final assistantIndex = 2 + index * 2;
			final toolIndex = assistantIndex + 1;
			eq(prompt[assistantIndex].role, AiLanguageModelPromptRole.Assistant, label + " assistant role " + index);
			final toolCall = promptContentParts(prompt[assistantIndex], label + " assistant content " + index)[0];
			eq(toolCall.type, AiLanguageModelPromptPartType.ToolCall, label + " tool-call type " + index);
			eq(toolCall.toolCallId, turn.callID, label + " tool-call id " + index);
			eq(toolCall.toolName, turn.toolName, label + " tool-call name " + index);
			eq(prompt[toolIndex].role, AiLanguageModelPromptRole.Tool, label + " tool role " + index);
			final toolResult = promptContentParts(prompt[toolIndex], label + " tool content " + index)[0];
			eq(toolResult.type, AiLanguageModelPromptPartType.ToolResult, label + " tool-result type " + index);
			eq(toolResult.toolCallId, turn.callID, label + " tool-result id " + index);
			eq(toolResult.toolName, turn.toolName, label + " tool-result name " + index);
			if (toolResult.output == null)
				throw label + ": expected tool-result output " + index;
			eq(toolResult.output.type, "text", label + " tool-result output type " + index);
			if (Std.string(toolResult.output.value).indexOf(turn.outputFragment) == -1)
				throw label + ': missing output ${turn.outputFragment}';
		}
	}

	static function promptContentText(message:AiLanguageModelPromptMessage):String {
		if (Std.isOfType(message.content, String))
			return cast message.content;
		final parts:Array<AiLanguageModelPromptPart> = message.content;
		if (parts.length == 1 && parts[0].type == AiLanguageModelPromptPartType.Text)
			return parts[0].text;
		throw "session processor: expected text prompt content";
	}

	static function promptContentParts(message:AiLanguageModelPromptMessage, label:String):Array<AiLanguageModelPromptPart> {
		if (!Std.isOfType(message.content, Array))
			throw label + ": expected prompt content parts";
		final parts:Array<AiLanguageModelPromptPart> = message.content;
		if (parts.length != 1)
			throw label + ": expected single prompt part";
		return parts;
	}

	static function assertCompactionPart(parts:Array<Part>, label:String):Void {
		for (part in parts) {
			switch part {
				case CompactionPart(compaction):
					eq(compaction.auto, true, label + " auto");
					eq(compaction.overflow, true, label + " overflow");
					return;
				case _:
			}
		}
		throw label + ": expected compaction part";
	}

	static function assertRetryPart(parts:Array<Part>, label:String):Void {
		for (part in parts) {
			switch part {
				case RetryPart(retry):
					eq(retry.attempt, 2.0, label + " attempt");
					eq(Reflect.field(retry.error, "name"), "APIError", label + " error");
					return;
				case _:
			}
		}
		throw label + ": expected retry part";
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
