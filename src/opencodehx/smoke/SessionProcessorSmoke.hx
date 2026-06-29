package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo;
import opencodehx.externs.ai.AiSdk.AiLanguageModelCallOptions;
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
import opencodehx.session.MessageTypes.ToolStateMetadata;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;
import opencodehx.session.SessionLlm;
import opencodehx.session.SessionProcessor;
import opencodehx.session.SessionRetry.SessionProviderError;
import opencodehx.session.SessionInstruction;
import opencodehx.session.SessionSystemPrompt;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResultMetadata;
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
		sessionSystemPrompt();
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
			toolAttachmentPropagation(root);
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

	static function sessionSystemPrompt():Void {
		final tmp = SmokeTmpDir.create();
		final root = tmp.path;
		final skillDir = NodePath.join(NodePath.join(NodePath.join(root, ".opencode"), "skill"), "review");
		Fs.mkdirSync(skillDir, {recursive: true});
		Fs.writeFileSync(NodePath.join(skillDir, "SKILL.md"), '---
name: review
description: Review workflow.
---

# Review
');
		Fs.writeFileSync(NodePath.join(root, "AGENTS.md"), "# Project Instructions\nUse project rules.");
		Fs.writeFileSync(NodePath.join(root, "local-instructions.md"), "# Local Instructions\nUse local config rules.");
		final config = ConfigInfo.empty("session-system-smoke");
		config.instructions = ["local-instructions.md"];
		final variants = new FakeProvider().model.variants;
		final model = modelWithOptionsVariants("openai", "gpt-5.2", "@ai-sdk/openai", optionMap(), variants);
		final instructionPaths = SessionInstruction.systemPaths({
			directory: root,
			worktree: root,
			config: config,
		});
		eq(instructionPaths.length, 2, "session instruction path count");
		eq(instructionPaths[0], NodePath.join(root, "AGENTS.md"), "session instruction project path");
		eq(instructionPaths[1], NodePath.join(root, "local-instructions.md"), "session instruction config path");
		final prompt = SessionSystemPrompt.build({
			directory: root,
			model: model,
			agent: {name: "reviewer", prompt: "Agent reviewer prompt."},
			config: config,
		});
		eq(prompt.length, 1, "session system prompt count");
		contains(prompt[0], "Agent reviewer prompt.", "session system agent prompt");
		contains(prompt[0], "Working directory: " + root, "session system working directory");
		contains(prompt[0], "Workspace root folder:", "session system worktree");
		contains(prompt[0], "<available_skills>", "session system skills block");
		contains(prompt[0], "<name>review</name>", "session system skill name");
		contains(prompt[0], "Instructions from: " + NodePath.join(root, "AGENTS.md"), "session system project instructions source");
		contains(prompt[0], "Use project rules.", "session system project instructions content");
		contains(prompt[0], "Instructions from: " + NodePath.join(root, "local-instructions.md"), "session system config instructions source");
		contains(prompt[0], "Use local config rules.", "session system config instructions content");

		final providerFallback = SessionSystemPrompt.build({
			directory: root,
			model: model,
			config: ConfigInfo.empty("session-system-smoke"),
		});
		contains(providerFallback[0], "You are OpenCode, You and the user share the same workspace", "session system provider prompt");
		tmp.dispose();
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
			variants: source.variants,
		};
	}

	static function modelWithInputCapabilities(providerID:String, apiID:String, npm:String, image:Bool, pdf:Bool):ProviderModel {
		final source = new FakeProvider().model;
		return {
			id: apiID,
			providerID: ProviderID.make(providerID),
			name: source.name,
			capabilities: {
				toolcall: source.capabilities.toolcall,
				attachment: image || pdf,
				reasoning: source.capabilities.reasoning,
				temperature: source.capabilities.temperature,
				interleaved: source.capabilities.interleaved,
				input: {
					text: source.capabilities.input.text,
					image: image,
					audio: source.capabilities.input.audio,
					video: source.capabilities.input.video,
					pdf: pdf,
				},
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

	static function contains(value:String, expected:String, label:String):Void {
		if (value.indexOf(expected) == -1)
			throw '$label: missing ${expected} in ${value}';
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
		@:await sessionSystemPromptAsync();
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-session-processor-async-"));
		var asyncStore:Null<SqliteSessionStore> = null;
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

			final store = new SqliteSessionStore(NodePath.join(root, "ai-sdk-session.db"));
			asyncStore = store;
			final persisted = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_persisted",
				prompt: "Persist this AI SDK turn.",
				directory: root,
				store: store,
				provider: fixture.info,
				model: fixture.model,
				language: AiSdkMockModel.text(["Persisted ", "through AI SDK."]),
			});
			eq(persisted.messages.length, 2, "ai sdk persisted message count");
			final recoveredAiSdk = SessionProcessor.recover(store, "ses_ai_sdk_persisted", 10);
			eq(recoveredAiSdk.session.directory, root, "ai sdk recovered session directory");
			eq(recoveredAiSdk.messages.length, 2, "ai sdk recovered message count");
			switch recoveredAiSdk.messages[1].parts[0] {
				case TextPart(text):
					eq(text.text, "Persisted through AI SDK.", "ai sdk recovered assistant text");
				case _:
					throw "session processor async: expected recovered assistant text";
			}
			final historyRuntime = AiSdkMockModel.inspectableText(["History aware."]);
			final historyRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_history",
				prompt: "Continue with recovered context.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: historyRuntime.language,
				history: recoveredAiSdk.messages,
			});
			eq(historyRun.messages.length, 2, "ai sdk history message count");
			assertSdkTextHistoryPrompt(historyRuntime.mock.doStreamCalls[0].prompt, [
				"Persist this AI SDK turn.",
				"Persisted through AI SDK.",
				"Continue with recovered context."
			], "ai sdk recovered text history prompt");

			final persistedToolRuntime = AiSdkMockModel.inspectableToolThenText("Recovered file says: ai sdk tool fixture.", "read",
				"{\"filePath\":\"src/input.txt\"}");
			final persistedTool = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_tool_persisted",
				prompt: "Persist this AI SDK tool turn.",
				directory: root,
				store: store,
				provider: fixture.info,
				model: fixture.model,
				language: persistedToolRuntime.language,
				files: [
					{
						mime: "image/png",
						filename: "history.png",
						url: "data:image/png;base64,aW1hZ2U=",
					}
				],
			});
			eq(persistedTool.messages.length, 2, "ai sdk persisted tool message count");
			assertToolOutcome(persistedTool.tool);
			final recoveredAiSdkTool = SessionProcessor.recover(store, "ses_ai_sdk_tool_persisted", 10);
			eq(recoveredAiSdkTool.messages.length, 2, "ai sdk recovered tool message count");
			assertAssistantParts(recoveredAiSdkTool.messages[1].parts, "ai sdk recovered tool", "tool_1", "Recovered file says: ai sdk tool fixture.");
			final recoveredUser = recoveredAiSdkTool.messages[0];
			final recoveredUserID = switch recoveredUser.info {
				case UserInfo(user):
					user.id;
				case _:
					throw "session processor async: expected recovered user message";
			}
			recoveredUser.parts.push(CompactionPart({
				id: PartID.make("prt_history_compaction"),
				sessionID: SessionID.make("ses_ai_sdk_tool_persisted"),
				messageID: recoveredUserID,
				type: "compaction",
				auto: true,
			}));
			recoveredUser.parts.push(SubtaskPart({
				id: PartID.make("prt_history_subtask"),
				sessionID: SessionID.make("ses_ai_sdk_tool_persisted"),
				messageID: recoveredUserID,
				type: "subtask",
				prompt: "Review a delegated tool.",
				description: "Delegated review",
				agent: "reviewer",
			}));
			final recoveredAssistant = recoveredAiSdkTool.messages[1];
			final recoveredAssistantID = switch recoveredAssistant.info {
				case AssistantInfo(assistant):
					assistant.id;
				case _:
					throw "session processor async: expected recovered assistant message";
			}
			recoveredAssistant.parts.push(ToolPart({
				id: PartID.make("prt_history_media_tool"),
				sessionID: SessionID.make("ses_ai_sdk_tool_persisted"),
				messageID: recoveredAssistantID,
				type: "tool",
				callID: "call_media_history",
				tool: "read",
				state: ToolCompleted({
					status: "completed",
					input: ToolCallInput.fromBoundary({filePath: "history-image.png"}),
					output: "Recovered image output",
					title: "Read",
					metadata: ToolStateMetadata.empty(),
					time: {start: 8, end: 9},
					attachments: [
						{
							id: PartID.make("prt_history_media_attachment"),
							sessionID: SessionID.make("ses_ai_sdk_tool_persisted"),
							messageID: recoveredAssistantID,
							type: "file",
							mime: "image/png",
							filename: "tool-history.png",
							url: "data:image/png;base64,dG9vbC1pbWFnZQ==",
						}
					],
				}),
			}));
			recoveredAssistant.parts.push(ToolPart({
				id: PartID.make("prt_history_interrupted_tool"),
				sessionID: SessionID.make("ses_ai_sdk_tool_persisted"),
				messageID: recoveredAssistantID,
				type: "tool",
				callID: "call_interrupted_history",
				tool: "bash",
				state: ToolErrored({
					status: "error",
					input: ToolCallInput.fromBoundary({command: "long running command"}),
					error: "Tool execution aborted",
					metadata: ToolStateMetadata.checked({interrupted: true, output: "partial interrupted output"}),
					time: {start: 10, end: 11},
				}),
			}));
			recoveredAssistant.parts.push(ToolPart({
				id: PartID.make("prt_history_error_tool"),
				sessionID: SessionID.make("ses_ai_sdk_tool_persisted"),
				messageID: recoveredAssistantID,
				type: "tool",
				callID: "call_error_history",
				tool: "read",
				state: ToolErrored({
					status: "error",
					input: ToolCallInput.fromBoundary({filePath: "missing.txt"}),
					error: "File not found",
					time: {start: 12, end: 13},
				}),
			}));
			final richHistoryRuntime = AiSdkMockModel.inspectableText(["Rich history aware."]);
			final richHistoryRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_rich_history",
				prompt: "Continue with recovered tool and file context.",
				directory: root,
				provider: fixture.info,
				model: modelWithInputCapabilities("openai", "gpt-5.2", "@ai-sdk/openai", true, false),
				language: richHistoryRuntime.language,
				history: recoveredAiSdkTool.messages,
			});
			eq(richHistoryRun.messages.length, 2, "ai sdk rich history message count");
			assertSdkRichHistoryPrompt(richHistoryRuntime.mock.doStreamCalls[0].prompt, "ai sdk rich recovered history prompt");

			final unsupportedMediaRuntime = AiSdkMockModel.inspectableText(["Unsupported media history aware."]);
			final unsupportedMediaRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_rich_history_unsupported_media",
				prompt: "Continue after injected media.",
				directory: root,
				provider: fixture.info,
				model: modelWithInputCapabilities("openai", "gpt-oss", "@ai-sdk/openai-compatible", true, false),
				language: unsupportedMediaRuntime.language,
				history: recoveredAiSdkTool.messages,
			});
			eq(unsupportedMediaRun.messages.length, 2, "ai sdk unsupported-media history message count");
			assertSdkUnsupportedMediaHistoryPrompt(unsupportedMediaRuntime.mock.doStreamCalls[0].prompt, "ai sdk unsupported-media recovered history prompt");

			final transformModel = modelWithOptionsVariants("anthropic", "claude-sonnet-4", "@ai-sdk/anthropic", optionMap(),
				new FakeProvider().model.variants);
			final transformRuntime = AiSdkMockModel.inspectableText(["Provider transform reached stream."]);
			final transformRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_provider_message_transform",
				prompt: "Use provider message transform.",
				directory: root,
				provider: fixture.info,
				model: transformModel,
				language: transformRuntime.language,
				system: [""],
			});
			eq(transformRun.messages.length, 2, "ai sdk provider transform message count");
			final transformedPrompt:Array<AiLanguageModelPromptMessage> = transformRuntime.mock.doStreamCalls[0].prompt;
			eq(transformedPrompt.length, 1, "ai sdk provider transform filters empty system");
			eq(transformedPrompt[0].role, AiLanguageModelPromptRole.User, "ai sdk provider transform keeps user");
			eq(promptContentText(transformedPrompt[0]), "Use provider message transform.", "ai sdk provider transform user text");

			Fs.mkdirSync(NodePath.join(root, "feature/nested"), {recursive: true});
			final featureInstructions = NodePath.join(root, "feature/AGENTS.md");
			Fs.writeFileSync(featureInstructions, "# Feature Instructions\nUse feature rules.\n");
			Fs.writeFileSync(NodePath.join(root, "feature/nested/first.txt"), "first feature\n");
			Fs.writeFileSync(NodePath.join(root, "feature/nested/second.txt"), "second feature\n");
			final loadedRuntime = AiSdkMockModel.inspectableToolThenText("Loaded feature instructions.", "read", "{\"filePath\":\"feature/nested/first.txt\"}");
			final loadedPersisted = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_loaded_instruction",
				prompt: "Read the first feature file.",
				directory: root,
				store: store,
				provider: fixture.info,
				model: fixture.model,
				language: loadedRuntime.language,
			});
			assertToolOutcome(loadedPersisted.tool);
			final loadedResult = requireToolResult(loadedPersisted.tool, "ai sdk loaded instruction");
			eq(loadedResult.output.indexOf("<system-reminder>") != -1, true, "ai sdk loaded instruction initial reminder");
			final recoveredLoaded = SessionProcessor.recover(store, "ses_ai_sdk_loaded_instruction", 10);
			final loadedPaths = SessionInstruction.loadedFromHistory(recoveredLoaded.messages);
			eq(loadedPaths.indexOf(featureInstructions) != -1, true, "ai sdk recovered loaded instruction path");
			final loadedHistoryRuntime = AiSdkMockModel.inspectableToolThenText("Skipped repeated instructions.", "read",
				"{\"filePath\":\"feature/nested/second.txt\"}");
			final loadedHistoryRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_loaded_instruction_history",
				prompt: "Read the second feature file.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: loadedHistoryRuntime.language,
				history: recoveredLoaded.messages,
			});
			assertToolOutcome(loadedHistoryRun.tool);
			final loadedHistoryResult = requireToolResult(loadedHistoryRun.tool, "ai sdk loaded-history instruction");
			eq(loadedHistoryResult.output.indexOf("<system-reminder>") == -1, true, "ai sdk loaded-history skips repeated reminder");
			eq(haxe.Json.stringify(loadedHistoryResult.metadata).indexOf('"loaded":[]') != -1, true, "ai sdk loaded-history metadata");

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
			eq(errorResult.retry == null, true, "ai sdk non-retryable error has no retry");
			switch errorResult.messages[1].info {
				case AssistantInfo(assistant):
					eq(assistant.finish, "error", "ai sdk error assistant finish");
				case _:
					throw "session processor async: expected error assistant info";
			}

			final retryResult = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_retryable_error",
				prompt: "Hit a retryable provider error.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: AiSdkMockModel.error("Rate limit exceeded"),
			});
			if (retryResult.retry == null)
				throw "session processor async: expected ai sdk retry status";
			eq(retryResult.retry.message, "Rate limit exceeded", "ai sdk retry message");
			eq(retryResult.retry.nextDelay, 2000.0, "ai sdk retry delay");
			eq(retryResult.events[3].type, "retry", "ai sdk retry event type");
			eq(retryResult.events[3].attempt, 1, "ai sdk retry event attempt");
			eq(retryResult.events[3].message, "Rate limit exceeded", "ai sdk retry event message");
			assertRetryPart(retryResult.messages[1].parts, "ai sdk retry part", 1.0, "Error");

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

			final liveOptions = optionMap();
			liveOptions.set("setCacheKey", true);
			final liveModel = modelWithOptionsVariants("google", "gemini-2.5-pro", "@ai-sdk/google", liveOptions, new FakeProvider().model.variants);
			liveModel.variants.set("high", record2("reasoningEffort", "high", "variantFlag", true));
			liveModel.headers.set("x-model-header", "live-model");
			liveModel.headers.set("x-request-header", "live-request");
			final optionRuntime = AiSdkMockModel.inspectableToolThenText("Request options reached continuation.", "read", "{\"filePath\":\"src/input.txt\"}");
			final optionRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_options",
				projectID: "proj_ai_sdk_options",
				prompt: "Read with request options.",
				directory: root,
				provider: fixture.info,
				model: liveModel,
				language: optionRuntime.language,
				providerOptions: record1("setCacheKey", true),
				agentOptions: record1("textVerbosity", "medium"),
				agentTemperature: 0.42,
				agentTopP: 0.77,
				variant: "high",
			});
			eq(optionRun.provider.modelID, "gemini-2.5-pro", "ai sdk option run model");
			eq(optionRuntime.mock.doStreamCalls.length, 2, "ai sdk option continuation call count");
			assertLiveAiSdkRequestOptions(optionRuntime.mock.doStreamCalls[0], "initial");
			assertLiveAiSdkRequestOptions(optionRuntime.mock.doStreamCalls[1], "continuation");

			final agentModel = modelWithOptionsVariants("google", "gemini-2.5-flash", "@ai-sdk/google", optionMap(), new FakeProvider().model.variants);
			agentModel.variants.set("high", record1("agentVariant", "high"));
			final agentRuntime = AiSdkMockModel.inspectableToolThenText("Agent config reached continuation.", "read", "{\"filePath\":\"src/input.txt\"}");
			final agentRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_agent_config",
				projectID: "proj_ai_sdk_agent_config",
				prompt: "Read with selected agent config.",
				directory: root,
				provider: fixture.info,
				model: agentModel,
				language: agentRuntime.language,
				agent: "reviewer",
				system: ["Agent prompt from config."],
				agentOptions: record1("textVerbosity", "agent-config"),
				agentTemperature: 0.31,
				agentTopP: 0.62,
				disabledTools: ["write"],
				variant: "high",
			});
			assertUserAgent(agentRun.messages[0].info, "reviewer", "ai sdk agent config user agent");
			eq(agentRun.request.system[0], "Agent prompt from config.", "ai sdk agent config request system");
			eq(agentRun.request.tools.indexOf("write"), -1, "ai sdk agent config request hides write");
			eq(agentRuntime.mock.doStreamCalls.length, 2, "ai sdk agent config continuation count");
			assertAgentConfigAiSdkCall(agentRuntime.mock.doStreamCalls[0], "initial");
			assertAgentConfigAiSdkCall(agentRuntime.mock.doStreamCalls[1], "continuation");

			final disabledToolRuntime = AiSdkMockModel.inspectableToolThenText("Disabled tool should not continue.", "read",
				"{\"filePath\":\"src/input.txt\"}");
			final disabledToolRun = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_agent_disabled_tool",
				prompt: "Try a disabled read.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: disabledToolRuntime.language,
				disabledTools: ["read"],
			});
			eq(disabledToolRuntime.mock.doStreamCalls.length, 1, "ai sdk disabled tool call count");
			eq(hasLanguageTool(disabledToolRuntime.mock.doStreamCalls[0].tools, "read"), false, "ai sdk disabled tool not advertised");
			assertDisabledToolOutcome(disabledToolRun.tool, "read");

			final disabledRuntime = AiSdkMockModel.inspectableToolThenText("This continuation should not run.", "read", "{\"filePath\":\"src/input.txt\"}");
			final disabledContinuation = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_tool_no_continue",
				prompt: "Read the AI SDK fixture without follow-up.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: disabledRuntime.language,
				continueAfterToolResult: false,
			});
			eq(disabledRuntime.mock.doStreamCalls.length, 1, "ai sdk disabled continuation call count");
			eq(disabledContinuation.events[1].type, "tool-call", "ai sdk disabled continuation model call");
			eq(disabledContinuation.events[4].status, "completed", "ai sdk disabled continuation tool finish");
			assertToolOutcome(disabledContinuation.tool);
			assertAssistantParts(disabledContinuation.messages[1].parts, "ai sdk disabled continuation", "tool_1", "");

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

			final limitedRuntime = AiSdkMockModel.inspectableTwoToolsThenText("The capped answer should not run.", "read", "{\"filePath\":\"src/input.txt\"}",
				"read", "{\"filePath\":\"src/input.txt\"}");
			final limitedContinuation = @:await SessionProcessor.runAiSdk({
				sessionID: "ses_ai_sdk_tool_limit",
				prompt: "Read the AI SDK fixture twice with one continuation.",
				directory: root,
				provider: fixture.info,
				model: fixture.model,
				language: limitedRuntime.language,
				maxToolContinuations: 1,
			});
			eq(limitedRuntime.mock.doStreamCalls.length, 2, "ai sdk max continuation call count");
			assertSdkToolResultPrompt(limitedRuntime.mock.doStreamCalls[1].prompt, "Read the AI SDK fixture twice with one continuation.", "tool_1", "read",
				"ai sdk tool fixture", "ai sdk max continuation prompt");
			eq(limitedContinuation.events[5].callID, "tool_2", "ai sdk max continuation second model call id");
			eq(limitedContinuation.events[8].status, "completed", "ai sdk max continuation second finish");
			assertToolOutcome(limitedContinuation.tool);
			assertAssistantTwoToolParts(limitedContinuation.messages[1].parts, "");
			switch asyncStore {
				case null:
				case store:
					store.close();
					asyncStore = null;
			}
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup must catch arbitrary Haxe/JS failures so the temp
			// directory is removed before rethrowing the original assertion error.
			switch asyncStore {
				case null:
				case store:
					store.close();
			}
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	static function sessionSystemPromptAsync():Promise<Void> {
		final tmp = SmokeTmpDir.create();
		final originalFetch = SmokeFetchStub.installCliLiveSuccess();
		try {
			final root = tmp.path;
			Fs.writeFileSync(NodePath.join(root, "AGENTS.md"), "# Project Instructions\nUse async project rules.");
			final config = ConfigInfo.empty("session-system-async-smoke");
			config.instructions = [
				"https://local.test/remote-instructions.md",
				"https://local.test/missing-instructions.md"
			];
			final model = new FakeProvider().model;
			final prompt = @:await SessionSystemPrompt.buildAsync({
				directory: root,
				model: model,
				config: config,
			});
			eq(prompt.length, 1, "session system async prompt count");
			contains(prompt[0], "Use async project rules.", "session system async local instructions");
			contains(prompt[0], "Instructions from: https://local.test/remote-instructions.md", "session system async remote source");
			contains(prompt[0], "Use remote instruction rules.", "session system async remote content");
			eq(prompt[0].indexOf("missing-instructions") == -1, true, "session system async failed remote omitted");
		} catch (error:haxe.Exception) {
			// Smoke cleanup must catch arbitrary Haxe/JS assertion failures so
			// the monkey-patched fetch and temp directory are restored.
			SmokeFetchStub.restore(originalFetch);
			tmp.dispose();
			throw error;
		}
		SmokeFetchStub.restore(originalFetch);
		tmp.dispose();
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
		assertRetryPart(result.messages[1].parts, "runtime retry part", 2.0, "APIError");

		final recovered = SessionProcessor.recover(store, "ses_retry_overflow", 10);
		eq(recovered.session.id.toString(), "ses_retry_overflow", "recovered retry session id");
		eq(recovered.messages.length, 2, "recovered retry messages");
		assertCompactionPart(recovered.messages[0].parts, "recovered compaction part");
		assertRetryPart(recovered.messages[1].parts, "recovered retry part", 2.0, "APIError");
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

	static function assertUserAgent(info:Info, expected:String, label:String):Void {
		switch info {
			case UserInfo(user):
				eq(user.agent, expected, label);
			case _:
				throw label + ": expected user info";
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

	static function toolAttachmentPropagation(root:String):Void {
		final result = SessionProcessor.run({
			prompt: "Fetch an image.",
			directory: root,
			registry: new ToolRegistry([attachmentTool()]),
			toolCall: {
				id: "call_image_one",
				tool: "image",
				input: {},
			},
		});
		switch result.messages[1].parts[1] {
			case ToolPart(tool):
				eq(tool.callID, "call_image_one", "attachment tool call id");
				switch tool.state {
					case ToolCompleted(completed):
						final attachments = completed.attachments;
						if (attachments == null)
							throw "session processor attachment propagation expected attachments";
						eq(attachments.length, 1, "session processor attachment count");
						eq(attachments[0].type, "file", "session processor attachment type");
						eq(attachments[0].mime, "image/png", "session processor attachment mime");
						eq(attachments[0].url, "data:image/png;base64,iVBORw0KGgo=", "session processor attachment url");
						eq(attachments[0].id.toString(), "prt_tool_attachment_0_call_image_one", "session processor attachment id");
					case _:
						throw "session processor attachment propagation expected completed tool";
				}
			case _:
				throw "session processor attachment propagation expected tool part";
		}
	}

	static function attachmentTool():ToolDef {
		return {
			id: "image",
			description: "Return an image attachment.",
			schema: {parameters: []},
			execute: (_, _) -> {
				title: "Image",
				output: "Image fetched successfully",
				metadata: ToolResultMetadata.empty(),
				attachments: [
					{
						type: "file",
						mime: "image/png",
						url: "data:image/png;base64,iVBORw0KGgo=",
					}
				],
			},
		};
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

	static function requireToolResult(outcome:Null<opencodehx.session.SessionProcessor.SessionToolOutcome>, label:String):opencodehx.tool.ToolTypes.ToolResult {
		if (outcome == null || outcome.result == null)
			throw '${label}: expected tool result';
		return outcome.result;
	}

	static function assertLiveAiSdkRequestOptions(call:AiLanguageModelCallOptions, label:String):Void {
		eq(call.maxOutputTokens, 10000.0, 'ai sdk ${label} max output tokens');
		eq(call.temperature, 0.42, 'ai sdk ${label} temperature');
		eq(call.topP, 0.77, 'ai sdk ${label} topP');
		eq(call.topK, 64.0, 'ai sdk ${label} topK');
		eq(callHeader(call, "x-session-affinity", label), "ses_ai_sdk_options", 'ai sdk ${label} affinity header');
		eq(callHeader(call, "x-model-header", label), "live-model", 'ai sdk ${label} model header');
		eq(callHeader(call, "x-request-header", label), "live-request", 'ai sdk ${label} request header');
		final google = sdkProviderOptions(call.providerOptions, "google", label);
		eq(UnknownNarrow.string(google.get("promptCacheKey")), "ses_ai_sdk_options", 'ai sdk ${label} prompt cache key');
		eq(UnknownNarrow.string(google.get("reasoningEffort")), "high", 'ai sdk ${label} variant option');
		eq(UnknownNarrow.bool(google.get("variantFlag")), true, 'ai sdk ${label} variant flag');
		eq(UnknownNarrow.string(google.get("textVerbosity")), "medium", 'ai sdk ${label} agent option');
	}

	static function assertAgentConfigAiSdkCall(call:AiLanguageModelCallOptions, label:String):Void {
		eq(call.maxOutputTokens, 10000.0, 'ai sdk agent ${label} max output tokens');
		eq(call.temperature, 0.31, 'ai sdk agent ${label} temperature');
		eq(call.topP, 0.62, 'ai sdk agent ${label} topP');
		eq(hasLanguageTool(call.tools, "read"), true, 'ai sdk agent ${label} advertises read');
		eq(hasLanguageTool(call.tools, "write"), false, 'ai sdk agent ${label} hides write');
		eq(promptContentText(call.prompt[0]), "Agent prompt from config.", 'ai sdk agent ${label} system prompt');
		final google = sdkProviderOptions(call.providerOptions, "google", 'agent ${label}');
		eq(UnknownNarrow.string(google.get("agentVariant")), "high", 'ai sdk agent ${label} variant option');
		eq(UnknownNarrow.string(google.get("textVerbosity")), "agent-config", 'ai sdk agent ${label} provider option');
	}

	static function assertDisabledToolOutcome(outcome:Null<opencodehx.session.SessionProcessor.SessionToolOutcome>, expectedTool:String):Void {
		if (outcome == null)
			throw "session processor: expected disabled tool outcome";
		eq(outcome.success, false, "disabled tool outcome success");
		eq(outcome.call.tool, expectedTool, "disabled tool outcome name");
		eq(outcome.error, 'Tool is disabled: ${expectedTool}', "disabled tool outcome error");
	}

	static function callHeader(call:AiLanguageModelCallOptions, key:String, label:String):Null<String> {
		final headers = call.headers;
		if (headers == null)
			throw 'ai sdk ${label} headers: expected headers';
		final value = headers.get(key);
		return value == null ? null : value.orNull();
	}

	static function sdkProviderOptions(options:Null<opencodehx.externs.ai.AiSdk.AiProviderOptions>, key:String, label:String):UnknownRecord {
		final root = UnknownNarrow.record(Unknown.fromBoundary(options));
		if (root == null)
			throw 'ai sdk ${label} provider options: expected root record';
		final provider = UnknownNarrow.record(root.get(key));
		if (provider == null)
			throw 'ai sdk ${label} provider options: expected ${key} record';
		return provider;
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

	static function assertSdkTextHistoryPrompt(prompt:Array<AiLanguageModelPromptMessage>, expectedTexts:Array<String>, label:String):Void {
		eq(prompt.length, expectedTexts.length + 1, label + " count");
		eq(prompt[0].role, AiLanguageModelPromptRole.System, label + " system role");
		eq(promptContentText(prompt[0]), "You are an AI SDK provider runtime.", label + " system text");
		for (index in 0...expectedTexts.length) {
			final message = prompt[index + 1];
			final expectedRole = index % 2 == 0 ? AiLanguageModelPromptRole.User : AiLanguageModelPromptRole.Assistant;
			eq(message.role, expectedRole, label + " role " + index);
			eq(promptContentText(message), expectedTexts[index], label + " text " + index);
		}
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

	static function promptContentPartsAny(message:AiLanguageModelPromptMessage, label:String):Array<AiLanguageModelPromptPart> {
		if (!Std.isOfType(message.content, Array))
			throw label + ": expected prompt content parts";
		return message.content;
	}

	static function assertSdkRichHistoryPrompt(prompt:Array<AiLanguageModelPromptMessage>, label:String):Void {
		eq(prompt.length, 5, label + " count");
		eq(prompt[0].role, AiLanguageModelPromptRole.System, label + " system role");
		eq(prompt[1].role, AiLanguageModelPromptRole.User, label + " recovered user role");
		final userParts = promptContentPartsAny(prompt[1], label + " recovered user content");
		eq(hasPromptTextPart(userParts, "Persist this AI SDK tool turn."), true, label + " recovered user text");
		final file = firstPromptPart(userParts, AiLanguageModelPromptPartType.File, label + " recovered user file");
		eq(file.mediaType, "image/png", label + " file media type");
		eq(file.filename, "history.png", label + " file name");
		eq(Std.string(file.data), "aW1hZ2U=", label + " file data");
		eq(hasPromptTextPart(userParts, "What did we do so far?"), true, label + " compaction prompt");
		eq(hasPromptTextPart(userParts, "The following tool was executed by the user"), true, label + " subtask prompt");

		eq(prompt[2].role, AiLanguageModelPromptRole.Assistant, label + " recovered assistant role");
		final assistantParts = promptContentPartsAny(prompt[2], label + " recovered assistant content");
		eq(hasPromptTextPart(assistantParts, "Recovered file says: ai sdk tool fixture."), true, label + " recovered assistant text");
		final toolCall = firstPromptPart(assistantParts, AiLanguageModelPromptPartType.ToolCall, label + " recovered tool call");
		eq(toolCall.toolCallId, "tool_1", label + " tool-call id");
		eq(toolCall.toolName, "read", label + " tool-call name");
		eq(hasPromptToolCall(assistantParts, "call_media_history", "read"), true, label + " media tool call");
		eq(hasPromptToolCall(assistantParts, "call_interrupted_history", "bash"), true, label + " interrupted tool call");
		eq(hasPromptToolCall(assistantParts, "call_error_history", "read"), true, label + " error tool call");

		eq(prompt[3].role, AiLanguageModelPromptRole.Tool, label + " recovered tool role");
		final toolResults = promptContentPartsAny(prompt[3], label + " recovered tool content");
		final toolResult = toolResults[0];
		eq(toolResult.type, AiLanguageModelPromptPartType.ToolResult, label + " tool-result type");
		eq(toolResult.toolCallId, "tool_1", label + " tool-result id");
		if (toolResult.output == null)
			throw label + ": expected tool-result output";
		eq(toolResult.output.type, "text", label + " tool-result output type");
		if (Std.string(toolResult.output.value).indexOf("ai sdk tool fixture") == -1)
			throw label + ": missing recovered tool output";
		final media = promptToolResult(toolResults, "call_media_history", label + " media result");
		assertContentToolResult(media.output, "Recovered image output", "image/png", "dG9vbC1pbWFnZQ==", label + " media result");
		final interrupted = promptToolResult(toolResults, "call_interrupted_history", label + " interrupted result");
		eq(interrupted.output.type, "text", label + " interrupted result output type");
		eq(Std.string(interrupted.output.value), "partial interrupted output", label + " interrupted result output");
		final errored = promptToolResult(toolResults, "call_error_history", label + " error result");
		eq(errored.output.type, "error-text", label + " normal error result output type");
		eq(Std.string(errored.output.value), "File not found", label + " normal error result output");

		eq(prompt[4].role, AiLanguageModelPromptRole.User, label + " current user role");
		eq(promptContentText(prompt[4]), "Continue with recovered tool and file context.", label + " current user text");
	}

	static function assertSdkUnsupportedMediaHistoryPrompt(prompt:Array<AiLanguageModelPromptMessage>, label:String):Void {
		eq(prompt.length, 6, label + " count");
		eq(prompt[0].role, AiLanguageModelPromptRole.System, label + " system role");
		eq(prompt[1].role, AiLanguageModelPromptRole.User, label + " recovered user role");
		eq(prompt[2].role, AiLanguageModelPromptRole.Assistant, label + " recovered assistant role");
		final assistantParts = promptContentPartsAny(prompt[2], label + " recovered assistant content");
		eq(hasPromptToolCall(assistantParts, "call_media_history", "read"), true, label + " media tool call");

		eq(prompt[3].role, AiLanguageModelPromptRole.Tool, label + " recovered tool role");
		final toolResults = promptContentPartsAny(prompt[3], label + " recovered tool content");
		final media = promptToolResult(toolResults, "call_media_history", label + " unsupported media result");
		eq(media.output.type, "text", label + " unsupported media result output type");
		eq(Std.string(media.output.value), "Recovered image output", label + " unsupported media result text");

		eq(prompt[4].role, AiLanguageModelPromptRole.User, label + " injected media user role");
		final mediaUserParts = promptContentPartsAny(prompt[4], label + " injected media content");
		eq(hasPromptTextPart(mediaUserParts, "Attached image(s) from tool result:"), true, label + " injected prompt text");
		final file = firstPromptPart(mediaUserParts, AiLanguageModelPromptPartType.File, label + " injected media file");
		eq(file.mediaType, "image/png", label + " injected media type");
		eq(Std.string(file.data), "dG9vbC1pbWFnZQ==", label + " injected media data");

		eq(prompt[5].role, AiLanguageModelPromptRole.User, label + " current user role");
		eq(promptContentText(prompt[5]), "Continue after injected media.", label + " current user text");
	}

	static function hasPromptToolCall(parts:Array<AiLanguageModelPromptPart>, callID:String, toolName:String):Bool {
		for (part in parts) {
			if (part.type == AiLanguageModelPromptPartType.ToolCall && part.toolCallId == callID && part.toolName == toolName)
				return true;
		}
		return false;
	}

	static function promptToolResult(parts:Array<AiLanguageModelPromptPart>, callID:String, label:String):AiLanguageModelPromptPart {
		for (part in parts) {
			if (part.type == AiLanguageModelPromptPartType.ToolResult && part.toolCallId == callID) {
				if (part.output == null)
					throw label + ": expected output";
				return part;
			}
		}
		throw label + ": expected tool result";
	}

	static function assertContentToolResult(output:opencodehx.externs.ai.AiSdk.AiLanguageModelToolResultOutput, text:String, mediaType:String, data:String,
			label:String):Void {
		eq(output.type, "content", label + " output type");
		final value = UnknownNarrow.array(Unknown.fromBoundary(output.value));
		if (value == null)
			throw label + ": expected content array";
		eq(value.length, 2, label + " content length");
		final textPart = requireRecordAt(value, 0, label + " text part");
		eq(UnknownNarrow.string(textPart.get("type")), "text", label + " text part type");
		eq(UnknownNarrow.string(textPart.get("text")), text, label + " text part text");
		final mediaPart = requireRecordAt(value, 1, label + " media part");
		eq(UnknownNarrow.string(mediaPart.get("type")), "image-data", label + " media part type");
		eq(UnknownNarrow.string(mediaPart.get("mediaType")), mediaType, label + " media type");
		eq(UnknownNarrow.string(mediaPart.get("data")), data, label + " media data");
	}

	static function requireRecordAt(array:UnknownArray, index:Int, label:String):UnknownRecord {
		final record = UnknownNarrow.record(array.get(index));
		if (record == null)
			throw label + ": expected record";
		return record;
	}

	static function firstPromptPart(parts:Array<AiLanguageModelPromptPart>, type:AiLanguageModelPromptPartType, label:String):AiLanguageModelPromptPart {
		for (part in parts) {
			if (part.type == type)
				return part;
		}
		throw label + ": missing prompt part";
	}

	static function hasPromptTextPart(parts:Array<AiLanguageModelPromptPart>, text:String):Bool {
		for (part in parts) {
			if (part.type == AiLanguageModelPromptPartType.Text && part.text == text)
				return true;
		}
		return false;
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

	static function assertRetryPart(parts:Array<Part>, label:String, expectedAttempt:Float, expectedName:String):Void {
		for (part in parts) {
			switch part {
				case RetryPart(retry):
					eq(retry.attempt, expectedAttempt, label + " attempt");
					eq(jsonStringField(Unknown.fromBoundary(retry.error), "name", label + " error"), expectedName, label + " error");
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

	static function jsonStringField(value:Unknown, field:String, label:String):String {
		final record = UnknownNarrow.record(value);
		if (record == null)
			throw label + ": expected object";
		final text = UnknownNarrow.string(record.get(field));
		if (text == null)
			throw label + ": expected string field";
		return text;
	}
}
