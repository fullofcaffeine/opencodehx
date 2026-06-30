package opencodehx.session;

import genes.js.Async.await;
import genes.ts.JsonValue;
import genes.ts.JsonCodec;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import js.html.AbortSignal;
import js.html.URL;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModelFileData;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsage;
import opencodehx.externs.ai.AiSdk.AiModelFilePart;
import opencodehx.externs.ai.AiSdk.AiModelAssistantMessagePart;
import opencodehx.externs.ai.AiSdk.AiModelMessage;
import opencodehx.externs.ai.AiSdk.AiSharedProviderOptions;
import opencodehx.externs.ai.AiSdk.AiSharedProviderOptionsMap;
import opencodehx.externs.ai.AiSdk.AiJsonObject;
import opencodehx.externs.ai.AiSdk.AiModelTextPart;
import opencodehx.externs.ai.AiSdk.AiModelToolCallPart;
import opencodehx.externs.ai.AiSdk.AiModelToolResultContentPart;
import opencodehx.externs.ai.AiSdk.AiModelToolResultMediaPart;
import opencodehx.externs.ai.AiSdk.AiModelToolMessagePart;
import opencodehx.externs.ai.AiSdk.AiModelToolResultPart;
import opencodehx.externs.ai.AiSdk.AiModelToolResultTurn;
import opencodehx.externs.ai.AiSdk.AiModelUserMessagePart;
import opencodehx.provider.AiSdkProvider;
import opencodehx.provider.AiSdkProvider.AiSdkStreamEvent;
import opencodehx.provider.AiSdkProvider.AiSdkStreamInput;
import opencodehx.provider.AiSdkProvider.AiSdkStreamResult;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.FakeProvider.FakeProviderEvent;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.session.MessageTypes.AssistantMessage;
import opencodehx.session.MessageTypes.FilePartData;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.MessageJson;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TextPartData;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.MessageTypes.ToolStateCompletedData;
import opencodehx.session.MessageTypes.ToolStateMetadata;
import opencodehx.session.MessageTypes.UserMessage;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.SessionCompaction.SessionCompactionCheck;
import opencodehx.session.SessionCompaction.SessionCompactionResult;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.session.SessionInstructionClaims;
import opencodehx.session.SessionRetry.SessionProviderError;
import opencodehx.session.SessionRetry.SessionRetryStatus;
import opencodehx.storage.SessionStore;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolRegistry.ToolFilter;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultAttachment;

typedef SessionToolCall = {
	final id:String;
	final tool:String;
	// Tool inputs are JSON-shaped runtime payloads owned by each tool schema.
	// The registry validates them before tool implementations use the fields.
	final input:ToolCallInput;
}

typedef SessionToolOutcome = {
	final call:SessionToolCall;
	final part:Part;
	final success:Bool;
	@:optional final result:ToolResult;
	@:optional final error:String;
}

typedef SessionEvent = {
	final type:String;
	@:optional final attempt:Int;
	@:optional final nextDelay:Float;
	@:optional final message:String;
	@:optional final text:String;
	@:optional final reason:String;
	@:optional final callID:String;
	@:optional final tool:String;
	@:optional final status:String;
	@:optional final error:String;
	@:optional final auto:Bool;
	@:optional final overflow:Bool;
	@:optional final count:Float;
	@:optional final usable:Float;
}

typedef SessionProviderIdentity = {
	final info:ProviderInfo;
	final model:ProviderModel;
	final system:Array<String>;
}

typedef SessionRetryPolicy = {
	@:optional final maxAttempts:Int;
	@:optional final wait:SessionRetryStatus->Promise<Bool>;
}

typedef SessionAiSdkStreamAttempt = {
	final stream:AiSdkStreamResult;
	final retry:Null<SessionRetryStatus>;
	final providerError:Null<SessionProviderError>;
}

typedef SessionFileInput = {
	final mime:String;
	final url:String;
	final filename:String;
}

typedef SessionProcessorInput = {
	final prompt:String;
	final directory:String;
	@:optional final sessionID:String;
	@:optional final turnID:String;
	@:optional final turnTime:Float;
	@:optional final parentSessionID:String;
	@:optional final projectID:String;
	@:optional final agent:String;
	@:optional final aborted:Bool;
	@:optional final store:SessionStore;
	@:optional final provider:FakeProvider;
	@:optional final providerError:SessionProviderError;
	@:optional final retryAttempt:Int;
	@:optional final compaction:SessionCompactionCheck;
	@:optional final registry:ToolRegistry;
	@:optional final permission:opencodehx.permission.PermissionRuntime;
	@:optional final toolCall:SessionToolCall;
	@:optional final files:Array<SessionFileInput>;
}

typedef SessionAiSdkProcessorInput = {
	final prompt:String;
	final directory:String;
	final provider:ProviderInfo;
	final model:ProviderModel;
	final language:AiLanguageModel;
	@:optional final sessionID:String;
	@:optional final turnID:String;
	@:optional final turnTime:Float;
	@:optional final parentSessionID:String;
	@:optional final projectID:String;
	@:optional final agent:String;
	@:optional final aborted:Bool;
	@:optional final store:SessionStore;
	@:optional final registry:ToolRegistry;
	@:optional final permission:opencodehx.permission.PermissionRuntime;
	@:optional final toolCall:SessionToolCall;
	@:optional final continueAfterToolResult:Bool;
	@:optional final maxToolContinuations:Int;
	@:optional final abortStreamImmediately:Bool;
	@:optional final abortContinuationImmediately:Bool;
	@:optional final abortSignal:AbortSignal;
	@:optional final files:Array<SessionFileInput>;
	@:optional final history:Array<WithParts>;
	@:optional final system:Array<String>;
	@:optional final disabledTools:Array<String>;
	@:optional final providerOptions:ProviderOptions;
	@:optional final agentOptions:ProviderOptions;
	@:optional final agentTemperature:Float;
	@:optional final agentTopP:Float;
	@:optional final headers:ProviderHeaders;
	@:optional final variant:String;
	@:optional final retryAttempt:Int;
	@:optional final retryPolicy:SessionRetryPolicy;
}

typedef SessionProcessorResult = {
	final provider:{
		final id:String;
		final modelID:String;
		final source:String;
	};
	final request:{
		final sessionID:String;
		final prompt:String;
		final system:Array<String>;
		final tools:Array<String>;
	};
	// Provider/status/server events are still an upstream-shaped JSON boundary,
	// but the current known fields stay typed so generated TS does not fall
	// back to `any[]` for normal session event handling.
	final events:Array<SessionEvent>;
	final messages:Array<WithParts>;
	@:optional final retry:SessionRetryStatus;
	@:optional final compaction:SessionCompactionResult;
	@:optional final aborted:Bool;
	@:optional final tool:SessionToolOutcome;
}

typedef SessionRecovery = {
	final session:SessionInfo;
	final messages:Array<WithParts>;
	final more:Bool;
	@:optional final cursor:String;
}

class SessionProcessor {
	public static inline final FIXTURE_DIRECTORY = "/workspace/opencodehx-fixture";
	public static inline final SESSION_ID = "ses_fake_one";
	public static inline final USER_ID = "msg_user_one";
	public static inline final ASSISTANT_ID = "msg_assistant_one";
	public static inline final USER_PART_ID = "prt_user_text";
	public static inline final USER_FILE_PART_ID = "prt_user_file";
	public static inline final ASSISTANT_PART_ID = "prt_assistant_text";
	public static inline final STEP_START_PART_ID = "prt_step_start";
	public static inline final STEP_FINISH_PART_ID = "prt_step_finish";
	public static inline final TOOL_PART_ID = "prt_tool_call";
	public static inline final TOOL_ATTACHMENT_PART_ID = "prt_tool_attachment";
	public static inline final RETRY_PART_ID = "prt_retry";
	public static inline final COMPACTION_PART_ID = "prt_compaction";
	public static inline final CREATED_USER = 1000.0;
	public static inline final CREATED_ASSISTANT = 1001.0;
	public static inline final COMPLETED_ASSISTANT = 1002.0;
	public static inline final DEFAULT_TOOL_CONTINUATIONS = 4;
	static inline final SYNTHETIC_ATTACHMENT_PROMPT = "Attached image(s) from tool result:";
	static inline final TOOL_STARTED = 1001.25;
	static inline final TOOL_ENDED = 1001.75;

	public static function run(input:SessionProcessorInput):SessionProcessorResult {
		final prompt = normalizePrompt(input.prompt);
		final sessionIDText = fallback(input.sessionID, SESSION_ID);
		final projectID = fallback(input.projectID, "proj_fixture");
		final agent = fallback(input.agent, "fixture");
		final fixtureProvider = input.provider == null ? new FakeProvider() : input.provider;
		final provider = providerIdentity(fixtureProvider.info, fixtureProvider.model, ["You are a deterministic fixture provider."]);
		final registry:ToolRegistry = input.registry == null ? new ToolRegistry() : input.registry;
		var retryAttempt = 1;
		final configuredRetryAttempt = input.retryAttempt;
		if (configuredRetryAttempt != null)
			retryAttempt = configuredRetryAttempt;
		final retry = input.providerError == null ? null : SessionRetry.status(input.providerError, retryAttempt);
		final events:Array<SessionEvent> = [];
		if (retry != null) {
			events.push({
				type: "retry",
				attempt: retry.attempt,
				message: retry.message,
				nextDelay: retry.nextDelay,
			});
		}
		final aborted = input.aborted == true;
		if (aborted) {
			events.push({type: "start"});
			events.push({type: "abort", message: "User aborted the request"});
		} else {
			for (event in encodeEvents(fixtureProvider.stream(prompt)))
				events.push(event);
		}
		final assistantText = collectText(events);
		final userMessage = userWithParts(sessionIDText, prompt, agent, provider, input.turnID, input.turnTime, input.files);
		final compaction = input.compaction == null ? null : SessionCompaction.check(input.compaction);
		if (compaction != null && compaction.overflow) {
			userMessage.parts.push(SessionCompaction.part(SessionID.make(sessionIDText),
				MessageID.make(scoped(partBase(USER_ID, input.turnID), sessionIDText)),
				PartID.make(scoped(partBase(COMPACTION_PART_ID, input.turnID), sessionIDText)), true, true));
			events.push({
				type: "compaction",
				auto: true,
				overflow: true,
				count: compaction.count,
				usable: compaction.usable,
			});
		}
		final text = aborted ? "Request aborted." : assistantText;
		final tokens = tokenUsage();
		final instructionClaims = new SessionInstructionClaims();
		final assistantMessage = assistantWithParts(sessionIDText, userMessage.info, text, input.directory, agent, provider, input.toolCall, registry,
			input.permission, events, retry, input.providerError, aborted, tokens, input.turnID, input.turnTime, instructionClaims, []);
		instructionClaims.clear(userID(assistantMessage.message.info).toString());

		if (input.store != null) {
			persist(input.store, projectID, sessionIDText, input.directory, input.parentSessionID, userMessage, assistantMessage.message);
		}

		return {
			provider: {
				id: provider.info.id,
				modelID: provider.model.id,
				source: provider.info.source,
			},
			request: {
				sessionID: sessionIDText,
				prompt: prompt,
				system: provider.system,
				tools: transcriptTools(),
			},
			events: events,
			messages: [userMessage, assistantMessage.message],
			retry: retry,
			compaction: compaction,
			aborted: aborted ? true : null,
			tool: assistantMessage.tool,
		};
	}

	@:async
	public static function runAiSdk(input:SessionAiSdkProcessorInput):Promise<SessionProcessorResult> {
		final prompt = normalizePrompt(input.prompt);
		final sessionIDText = fallback(input.sessionID, SESSION_ID);
		final projectID = fallback(input.projectID, "proj_fixture");
		final agent = fallback(input.agent, "primary");
		final system = input.system == null ? ["You are an AI SDK provider runtime."] : input.system;
		final provider = providerIdentity(input.provider, input.model, system);
		final registry:ToolRegistry = input.registry == null ? new ToolRegistry() : input.registry;
		final toolFilter = sessionToolFilter(input.disabledTools);
		final events:Array<SessionEvent> = [];
		final aborted = input.aborted == true;
		var streamAborted = false;
		var tokens = tokenUsage();
		var modelToolCall:Null<SessionToolCall> = null;
		var toolOutcome:Null<SessionToolOutcome> = null;
		var retry:Null<SessionRetryStatus> = null;
		var providerError:Null<SessionProviderError> = null;
		final messageHistory = modelHistory(input.history, input.model);
		final loadedInstructions = input.history == null ? [] : SessionInstruction.loadedFromHistory(input.history);
		final tools = AiSdkProvider.toolsFromRegistry(registry, toolFilter);
		final streamOptions = aiSdkStreamOptions(input, sessionIDText, projectID, provider.system, registry, toolFilter);
		if (aborted) {
			events.push({type: "start"});
			events.push({type: "abort", message: "User aborted the request"});
		} else {
			events.push({type: "start"});
			final requestMessages = SessionLlm.requestModelMessages(provider.system, prompt, false, false, messageHistory);
			final streamAttempt = @:await streamAiSdkWithRetry(input, {
				model: input.language,
				prompt: prompt,
				messages: requestMessages,
				tools: tools,
				abortImmediately: input.abortStreamImmediately,
				abortSignal: input.abortSignal,
				maxOutputTokens: streamOptions.maxOutputTokens,
				temperature: streamOptions.temperature,
				topP: streamOptions.topP,
				topK: streamOptions.topK,
				headers: streamOptions.headers,
				providerOptions: streamOptions.providerOptions,
				providerModel: input.model,
				transformOptions: streamOptions.options,
				maxRetries: streamOptions.maxRetries,
			}, events);
			streamAborted = streamAttempt.stream.aborted;
			tokens = tokenUsageFromAiSdk(streamAttempt.stream.totalUsage);
			modelToolCall = firstModelToolCall(streamAttempt.stream.events);
			providerError = streamAttempt.providerError;
			retry = streamAttempt.retry;
		}

		final assistantText = collectText(events);
		final userMessage = userWithParts(sessionIDText, prompt, agent, provider, input.turnID, input.turnTime, input.files);
		var wasAborted = aborted || streamAborted;
		final text = wasAborted ? "Request aborted." : assistantText;
		final toolCall = input.toolCall == null ? modelToolCall : input.toolCall;
		final instructionClaims = new SessionInstructionClaims();
		final assistantMessage = assistantWithParts(sessionIDText, userMessage.info, text, input.directory, agent, provider, toolCall, registry,
			input.permission, events, retry, providerError, wasAborted, tokens, input.turnID, input.turnTime, instructionClaims, loadedInstructions,
			toolFilter);
		toolOutcome = assistantMessage.tool;
		var assistantRecord = assistantMessage.message;
		var continuationLimit = DEFAULT_TOOL_CONTINUATIONS;
		final configuredContinuationLimit = input.maxToolContinuations;
		if (configuredContinuationLimit != null)
			continuationLimit = configuredContinuationLimit;
		var continuations = 0;
		final toolHistory:Array<AiModelToolResultTurn> = [];
		while (!streamAborted
			&& !aborted
			&& input.continueAfterToolResult != false
			&& input.toolCall == null
			&& continuations < continuationLimit) {
			final currentOutcome:SessionToolOutcome = switch toolOutcome {
				case null:
					break;
				case outcome:
					outcome;
			}
			if (!currentOutcome.success || currentOutcome.result == null)
				break;
			continuations++;
			toolHistory.push(toolHistoryTurn(currentOutcome));
			final continuationMessages = SessionLlm.requestToolHistoryModelMessages(provider.system, prompt, toolHistory, false, false, messageHistory);
			final continuationAttempt = @:await streamAiSdkWithRetry(input, {
				model: input.language,
				prompt: prompt,
				messages: continuationMessages,
				tools: tools,
				abortImmediately: input.abortContinuationImmediately,
				abortSignal: input.abortSignal,
				maxOutputTokens: streamOptions.maxOutputTokens,
				temperature: streamOptions.temperature,
				topP: streamOptions.topP,
				topK: streamOptions.topK,
				headers: streamOptions.headers,
				providerOptions: streamOptions.providerOptions,
				providerModel: input.model,
				transformOptions: streamOptions.options,
				maxRetries: streamOptions.maxRetries,
			}, events);
			final continuation = continuationAttempt.stream;
			streamAborted = continuation.aborted;
			wasAborted = wasAborted || streamAborted;
			final continuationEvents = encodeAiSdkEvents(continuation.events);
			final continuedText = collectText(continuationEvents);
			final nextToolCall = firstModelToolCall(continuation.events);
			if (continuationAttempt.providerError != null) {
				providerError = continuationAttempt.providerError;
				retry = continuationAttempt.retry;
			}
			if (nextToolCall != null) {
				toolOutcome = appendAssistantTool(assistantRecord, sessionIDText, input.directory, agent, nextToolCall, registry, input.permission, events,
					input.turnID, input.turnTime, instructionClaims, loadedInstructions, toolFilter);
			} else {
				if (continuedText != "")
					replaceAssistantText(assistantRecord, continuedText);
				break;
			}
		}
		if (wasAborted) {
			assistantRecord = abortedAssistantRecord(assistantRecord, events);
			replaceAssistantText(assistantRecord, "Request aborted.");
		}
		instructionClaims.clear(userID(assistantRecord.info).toString());

		if (input.store != null) {
			persist(input.store, projectID, sessionIDText, input.directory, input.parentSessionID, userMessage, assistantRecord);
		}

		return {
			provider: {
				id: provider.info.id,
				modelID: provider.model.id,
				source: provider.info.source,
			},
			request: {
				sessionID: sessionIDText,
				prompt: prompt,
				system: provider.system,
				tools: registry.ids(toolFilter),
			},
			events: events,
			messages: [userMessage, assistantRecord],
			retry: retry,
			compaction: null,
			aborted: wasAborted ? true : null,
			tool: toolOutcome,
		};
	}

	static function retryAttempt(configured:Null<Int>):Int {
		return configured == null ? 1 : configured;
	}

	@:async
	static function streamAiSdkWithRetry(input:SessionAiSdkProcessorInput, streamInput:AiSdkStreamInput,
			events:Array<SessionEvent>):Promise<SessionAiSdkStreamAttempt> {
		var attempt = retryAttempt(input.retryAttempt);
		var calls = 0;
		final maxAttempts = retryMaxAttempts(input.retryPolicy);
		while (true) {
			calls++;
			final stream = @:await AiSdkProvider.stream(streamInput);
			for (event in encodeAiSdkEvents(stream.events))
				events.push(event);
			final providerError = firstAiSdkProviderError(stream.errors);
			final retry = providerError == null ? null : SessionRetry.status(providerError, attempt);
			if (retry == null || stream.aborted)
				return {stream: stream, retry: retry, providerError: providerError};
			events.push(retryEvent(retry));
			if (calls >= maxAttempts)
				return {stream: stream, retry: retry, providerError: providerError};
			final wait = input.retryPolicy == null ? null : input.retryPolicy.wait;
			if (wait != null) {
				final keepGoing = @:await wait(retry);
				if (!keepGoing)
					return {stream: stream, retry: retry, providerError: providerError};
			}
			attempt++;
		}
	}

	static function retryMaxAttempts(policy:Null<SessionRetryPolicy>):Int {
		if (policy == null)
			return 1;
		final maxAttempts:Null<Int> = policy.maxAttempts;
		return maxAttempts == null ? 1 : maxAttempts;
	}

	static function retryEvent(retry:SessionRetryStatus):SessionEvent {
		return {
			type: "retry",
			attempt: retry.attempt,
			message: retry.message,
			nextDelay: retry.nextDelay,
		};
	}

	static function firstAiSdkProviderError(errors:Array<String>):Null<SessionProviderError> {
		if (errors.length == 0)
			return null;
		return SessionProviderError.Message(errors[0]);
	}

	static function aiSdkStreamOptions(input:SessionAiSdkProcessorInput, sessionIDText:String, projectID:String, system:Array<String>, registry:ToolRegistry,
			filter:Null<ToolFilter>):SessionLlm.LlmStreamTextOptions {
		final requestOptions = SessionLlm.requestOptions({
			model: input.model,
			sessionID: sessionIDText,
			small: false,
			isOpenaiOauth: false,
			system: system,
			providerOptions: input.providerOptions,
			agentOptions: input.agentOptions,
			variant: input.variant,
		});
		final params = SessionLlm.requestParams({
			model: input.model,
			options: requestOptions,
			agentTemperature: input.agentTemperature,
			agentTopP: input.agentTopP,
		});
		final headers = SessionLlm.requestHeaders({
			model: input.model,
			sessionID: sessionIDText,
			userID: scoped(partBase(USER_ID, input.turnID), sessionIDText),
			projectID: projectID,
			client: "opencodehx",
			installationVersion: BuildInfo.version,
			parentSessionID: input.parentSessionID,
			headers: input.headers,
		});
		return SessionLlm.streamTextOptions({
			model: input.model,
			params: params,
			tools: AiSdkProvider.toolsFromRegistry(registry, filter),
			headers: headers,
			retries: 0,
		});
	}

	static function sessionToolFilter(disabledTools:Null<Array<String>>):Null<ToolFilter> {
		if (disabledTools == null || disabledTools.length == 0)
			return null;
		return {disabled: disabledTools.copy()};
	}

	public static function recover(store:SessionStore, sessionIDText:String, ?limit:Int):SessionRecovery {
		final sessionID = SessionID.make(sessionIDText);
		final page = store.pageMessages(sessionID, limit == null ? 50 : limit);
		return {
			session: store.getSession(sessionID),
			messages: page.items,
			more: page.more,
			cursor: page.cursor,
		};
	}

	public static function toTranscript(processed:SessionProcessorResult):Dynamic {
		// Transcript output is the JSON oracle surface consumed by harnesses.
		// Message records are typed until this final serialization boundary.
		final encodedMessages:Array<Dynamic> = [];
		for (message in processed.messages) {
			encodedMessages.push(MessageCodec.encodeWithParts(message));
		}
		return {
			provider: processed.provider,
			request: processed.request,
			events: processed.events,
			messages: encodedMessages,
		};
	}

	static function userWithParts(sessionIDText:String, prompt:String, agent:String, provider:SessionProviderIdentity, turnID:Null<String>,
			turnTime:Null<Float>, files:Null<Array<SessionFileInput>>):WithParts {
		final sessionID = SessionID.make(sessionIDText);
		final created = userCreated(turnTime);
		final messageID = MessageID.make(scoped(partBase(USER_ID, turnID), sessionIDText));
		final info:UserMessage = {
			id: messageID,
			sessionID: sessionID,
			role: "user",
			time: {created: created},
			agent: agent,
			model: {providerID: provider.info.id, modelID: provider.model.id},
			format: OutputText,
			tools: MessageJson.checked({
				read: true,
				write: true,
				edit: true,
				apply_patch: true
			}),
		};
		final parts:Array<Part> = [];
		final fileInputs = files == null ? [] : files;
		for (index in 0...fileInputs.length) {
			final file = fileInputs[index];
			final filePart:FilePartData = {
				id: PartID.make(scoped(partBase(USER_FILE_PART_ID + "_" + index, turnID), sessionIDText)),
				sessionID: sessionID,
				messageID: messageID,
				type: "file",
				mime: file.mime,
				filename: file.filename,
				url: file.url,
			};
			parts.push(FilePart(filePart));
		}
		final text:TextPartData = {
			id: PartID.make(scoped(partBase(USER_PART_ID, turnID), sessionIDText)),
			sessionID: sessionID,
			messageID: messageID,
			type: "text",
			text: prompt,
			time: {
				start: created,
				end: created
			},
		};
		parts.push(TextPart(text));
		return {info: UserInfo(info), parts: parts};
	}

	static function modelHistory(history:Null<Array<WithParts>>, model:ProviderModel):Array<AiModelMessage> {
		final out:Array<AiModelMessage> = [];
		if (history == null)
			return out;
		final preserveMediaToolResults = supportsMediaInToolResults(model);
		for (message in history) {
			switch message.info {
				case UserInfo(_):
					pushUserModelMessage(out, message.parts);
				case AssistantInfo(assistant):
					pushAssistantModelMessages(out, message.parts, preserveMediaToolResults, sameProviderModel(assistant, model));
			}
		}
		return out;
	}

	static function sameProviderModel(assistant:AssistantMessage, model:ProviderModel):Bool {
		return assistant.providerID == model.providerID.toString() && assistant.modelID == model.id.toString();
	}

	static function pushUserModelMessage(out:Array<AiModelMessage>, parts:Array<Part>):Void {
		final content:Array<AiModelUserMessagePart> = [];
		for (part in parts) {
			switch part {
				case TextPart(text):
					if (text.ignored != true && StringTools.trim(text.text) != "")
						content.push(modelUserTextPart(text.text));
				case FilePart(file):
					if (isModelFile(file))
						content.push(modelUserFilePart(file));
				case CompactionPart(_):
					content.push(modelUserTextPart("What did we do so far?"));
				case SubtaskPart(_):
					content.push(modelUserTextPart("The following tool was executed by the user"));
				case _:
			}
		}
		if (content.length > 0)
			out.push({role: "user", content: content});
	}

	static function pushAssistantModelMessages(out:Array<AiModelMessage>, parts:Array<Part>, preserveMediaToolResults:Bool, preserveProviderOptions:Bool):Void {
		final content:Array<AiModelAssistantMessagePart> = [];
		final toolResults:Array<AiModelMessage> = [];
		final injectedMedia:Array<FilePartData> = [];
		for (part in parts) {
			switch part {
				case TextPart(text):
					if (text.ignored != true && StringTools.trim(text.text) != "")
						content.push(modelAssistantTextPart(text.text, preserveProviderOptions ? providerOptionsFromMessageMetadata(text.metadata) : null));
				case ToolPart(tool):
					final providerOptions = preserveProviderOptions ? providerOptionsFromToolMetadata(tool.metadata) : null;
					switch tool.state {
						case ToolCompleted(data):
							content.push(toolCallModelPart(tool.callID, tool.tool, data.input, providerOptions));
							toolResults.push(completedToolResultModelMessage(tool.callID, tool.tool, data, preserveMediaToolResults, injectedMedia,
								providerOptions));
						case ToolErrored(data):
							content.push(toolCallModelPart(tool.callID, tool.tool, data.input, providerOptions));
							final interruptedOutput = interruptedToolOutput(data.metadata);
							if (interruptedOutput == null) {
								toolResults.push(toolErrorResultModelMessage(tool.callID, tool.tool, data.error, providerOptions));
							} else {
								toolResults.push(toolTextResultModelMessage(tool.callID, tool.tool, interruptedOutput, providerOptions));
							}
						case ToolPending(data):
							content.push(toolCallModelPart(tool.callID, tool.tool, data.input, providerOptions));
							toolResults.push(toolErrorResultModelMessage(tool.callID, tool.tool, "[Tool execution was interrupted]", providerOptions));
						case ToolRunning(data):
							content.push(toolCallModelPart(tool.callID, tool.tool, data.input, providerOptions));
							toolResults.push(toolErrorResultModelMessage(tool.callID, tool.tool, "[Tool execution was interrupted]", providerOptions));
					}
				case _:
			}
		}
		if (content.length == 0)
			return;
		out.push({role: "assistant", content: content});
		for (message in toolResults)
			out.push(message);
		if (injectedMedia.length > 0)
			out.push(syntheticToolMediaUserMessage(injectedMedia));
	}

	static function isModelFile(file:FilePartData):Bool {
		return file.mime != "text/plain" && file.mime != "application/x-directory";
	}

	static function modelUserFilePart(file:FilePartData):AiModelUserMessagePart {
		final part:AiModelFilePart = if (file.filename == null) {
			{
				type: "file",
				data: modelFileData(file.url),
				mediaType: file.mime,
			};
		} else {
			{
				type: "file",
				data: modelFileData(file.url),
				mediaType: file.mime,
				filename: file.filename,
			};
		}
		return part;
	}

	static function modelUserTextPart(text:String):AiModelUserMessagePart {
		final part:AiModelTextPart = {type: "text", text: text};
		return part;
	}

	static function modelAssistantTextPart(text:String, providerOptions:Null<AiSharedProviderOptions>):AiModelAssistantMessagePart {
		final part:AiModelTextPart = providerOptions == null ? {type: "text", text: text} : {type: "text", text: text, providerOptions: providerOptions};
		return part;
	}

	static function modelFileData(url:String):AiLanguageModelFileData {
		if (StringTools.startsWith(url, "data:")) {
			final comma = url.indexOf(",");
			return comma == -1 ? url : url.substr(comma + 1);
		}
		return new URL(url);
	}

	static function toolCallModelPart(callID:String, toolName:String, input:ToolCallInput,
			providerOptions:Null<AiSharedProviderOptions>):AiModelAssistantMessagePart {
		final part:AiModelToolCallPart = if (providerOptions == null) {
			{
				type: "tool-call",
				toolCallId: callID,
				toolName: toolName,
				input: input.unknown(),
			};
		} else {
			{
				type: "tool-call",
				toolCallId: callID,
				toolName: toolName,
				input: input.unknown(),
				providerOptions: providerOptions,
			};
		}
		return part;
	}

	static function toolTextResultModelMessage(callID:String, toolName:String, outputValue:String,
			?providerOptions:Null<AiSharedProviderOptions>):AiModelMessage {
		final part:AiModelToolResultPart = toolResultPart(callID, toolName, {type: "text", value: outputValue}, providerOptions);
		return toolResultModelMessage(part);
	}

	static function completedToolResultModelMessage(callID:String, toolName:String, data:ToolStateCompletedData, preserveMediaToolResults:Bool,
			injectedMedia:Array<FilePartData>, providerOptions:Null<AiSharedProviderOptions>):AiModelMessage {
		if (data.attachments == null || data.attachments.length == 0)
			return toolTextResultModelMessage(callID, toolName, data.output, providerOptions);
		if (!preserveMediaToolResults) {
			for (attachment in data.attachments) {
				if (isMediaFile(attachment))
					injectedMedia.push(attachment);
			}
			return toolTextResultModelMessage(callID, toolName, data.output, providerOptions);
		}
		final value:Array<AiModelToolResultContentPart> = [modelToolResultTextPart(data.output)];
		for (attachment in data.attachments) {
			if (isMediaFile(attachment))
				value.push(modelToolResultMediaPart(attachment));
		}
		if (value.length == 1)
			return toolTextResultModelMessage(callID, toolName, data.output, providerOptions);
		final part = toolResultPart(callID, toolName, {type: "content", value: value}, providerOptions);
		return toolResultModelMessage(part);
	}

	static function syntheticToolMediaUserMessage(media:Array<FilePartData>):AiModelMessage {
		final content:Array<AiModelUserMessagePart> = [modelUserTextPart(SYNTHETIC_ATTACHMENT_PROMPT)];
		for (file in media)
			content.push(modelToolMediaUserFilePart(file));
		return {role: "user", content: content};
	}

	static function toolErrorResultModelMessage(callID:String, toolName:String, outputValue:String,
			?providerOptions:Null<AiSharedProviderOptions>):AiModelMessage {
		final part = toolResultPart(callID, toolName, {type: "error-text", value: outputValue}, providerOptions);
		return toolResultModelMessage(part);
	}

	static function toolResultPart(callID:String, toolName:String, output:opencodehx.externs.ai.AiSdk.AiModelToolResultOutput,
			providerOptions:Null<AiSharedProviderOptions>):AiModelToolResultPart {
		return providerOptions == null ? {
			type: "tool-result",
			toolCallId: callID,
			toolName: toolName,
			output: output,
		} : {
			type: "tool-result",
			toolCallId: callID,
			toolName: toolName,
			output: output,
			providerOptions: providerOptions,
			};
	}

	static function interruptedToolOutput(metadata:Null<ToolStateMetadata>):Null<String> {
		if (metadata == null)
			return null;
		final json:JsonValue = metadata;
		// Tool state metadata is open JSON. Narrow only the upstream interrupted
		// output fields needed to recover partial tool output, then return String.
		final record = UnknownNarrow.record(Unknown.fromBoundary(json));
		if (record == null || UnknownNarrow.bool(record.get("interrupted")) != true)
			return null;
		return UnknownNarrow.string(record.get("output"));
	}

	static function providerOptionsFromMessageMetadata(metadata:Null<MessageJson>):Null<AiSharedProviderOptions> {
		if (metadata == null)
			return null;
		return providerOptionsFromUnknown(Unknown.fromBoundary(metadata));
	}

	static function providerOptionsFromToolMetadata(metadata:Null<ToolStateMetadata>):Null<AiSharedProviderOptions> {
		if (metadata == null)
			return null;
		return providerOptionsFromUnknown(Unknown.fromBoundary(metadata));
	}

	static function providerOptionsFromUnknown(metadata:Unknown):Null<AiSharedProviderOptions> {
		final record = UnknownNarrow.record(metadata);
		if (record == null)
			return null;
		final out = new AiSharedProviderOptionsMap();
		var copied = false;
		for (key in record.keys()) {
			if (key == "providerExecuted")
				continue;
			final value = record.get(key);
			final providerValue = JsonCodec.narrowObject(value);
			if (providerValue != null) {
				out.set(key, AiJsonObject.fromBoundary(providerValue));
				copied = true;
			}
		}
		if (!copied)
			return null;
		final options:AiSharedProviderOptions = out;
		return options;
	}

	static function modelToolResultTextPart(text:String):AiModelToolResultContentPart {
		final part:AiModelTextPart = {type: "text", text: text};
		return part;
	}

	static function modelToolResultMediaPart(file:FilePartData):AiModelToolResultContentPart {
		final part:AiModelToolResultMediaPart = {
			type: "media",
			mediaType: file.mime,
			data: modelToolResultMediaData(file.url),
		};
		return part;
	}

	static function modelToolMediaUserFilePart(file:FilePartData):AiModelUserMessagePart {
		final part:AiModelFilePart = {
			type: "file",
			data: modelFileData(file.url),
			mediaType: file.mime,
		};
		return part;
	}

	static function modelToolResultMediaData(url:String):String {
		if (StringTools.startsWith(url, "data:")) {
			final comma = url.indexOf(",");
			return comma == -1 ? url : url.substr(comma + 1);
		}
		return url;
	}

	static function supportsMediaInToolResults(model:ProviderModel):Bool {
		final npm = model.api.npm;
		if (npm == "@ai-sdk/anthropic"
			|| npm == "@ai-sdk/openai"
			|| npm == "@ai-sdk/amazon-bedrock"
			|| npm == "@ai-sdk/google-vertex/anthropic")
			return true;
		if (npm == "@ai-sdk/google") {
			final id = model.api.id.toLowerCase();
			return id.indexOf("gemini-3") != -1 && id.indexOf("gemini-2") == -1;
		}
		return false;
	}

	static function isMediaFile(file:FilePartData):Bool {
		return StringTools.startsWith(file.mime, "image/") || file.mime == "application/pdf";
	}

	static function toolResultModelMessage(part:AiModelToolResultPart):AiModelMessage {
		final content:Array<AiModelToolMessagePart> = [part];
		return {
			role: "tool",
			content: content,
		};
	}

	static function assistantWithParts(sessionIDText:String, parentInfo:Info, text:String, directory:String, agent:String, provider:SessionProviderIdentity,
			toolCall:Null<SessionToolCall>, registry:ToolRegistry, permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>,
			retry:Null<SessionRetryStatus>, providerError:Null<SessionProviderError>, aborted:Bool, tokens:TokenUsage, turnID:Null<String>,
			turnTime:Null<Float>, instructionClaims:SessionInstructionClaims, loadedInstructions:Array<String>, ?filter:ToolFilter):{
		final message:WithParts;
		final tool:Null<SessionToolOutcome>;
	} {
		final sessionID = SessionID.make(sessionIDText);
		final created = assistantCreated(turnTime);
		final completed = assistantCompleted(turnTime);
		final messageID = MessageID.make(scoped(partBase(ASSISTANT_ID, turnID), sessionIDText));
		final parentID = userID(parentInfo);
		final info:AssistantMessage = {
			id: messageID,
			sessionID: sessionID,
			role: "assistant",
			time: {created: created, completed: completed},
			parentID: parentID,
			modelID: provider.model.id,
			providerID: provider.info.id,
			mode: "primary",
			agent: agent,
			path: {cwd: directory, root: directory},
			error: aborted ? MessageJson.checked({name: "MessageAbortedError", message: "User aborted the request"}) : null,
			cost: 0,
			tokens: tokens,
			finish: assistantFinish(events),
		};

		final parts:Array<Part> = [];
		if (retry != null && providerError != null) {
			parts.push(RetryPart({
				id: PartID.make(scoped(partBase(RETRY_PART_ID, turnID), sessionIDText)),
				sessionID: sessionID,
				messageID: messageID,
				type: "retry",
				attempt: retry.attempt,
				error: MessageJson.checked(SessionRetry.errorRecord(providerError)),
				time: {
					created: created
				},
			}));
		}
		var toolOutcome:Null<SessionToolOutcome> = null;
		if (toolCall != null) {
			parts.push(StepStartPart({
				id: PartID.make(scoped(partBase(STEP_START_PART_ID, turnID), sessionIDText)),
				sessionID: sessionID,
				messageID: messageID,
				type: "step-start",
			}));
			toolOutcome = executeTool(sessionID, messageID, directory, agent, toolCall, registry, permission, events, turnID, turnTime, instructionClaims,
				loadedInstructions, filter);
			parts.push(toolOutcome.part);
		}

		parts.push(TextPart({
			id: PartID.make(scoped(partBase(ASSISTANT_PART_ID, turnID), sessionIDText)),
			sessionID: sessionID,
			messageID: messageID,
			type: "text",
			text: text,
			time: {
				start: created,
				end: completed
			},
		}));

		if (toolCall != null) {
			parts.push(StepFinishPart({
				id: PartID.make(scoped(partBase(STEP_FINISH_PART_ID, turnID), sessionIDText)),
				sessionID: sessionID,
				messageID: messageID,
				type: "step-finish",
				reason: "stop",
				cost: 0,
				tokens: tokens,
			}));
		}

		return {
			message: {info: AssistantInfo(info), parts: parts},
			tool: toolOutcome,
		};
	}

	static function executeTool(sessionID:SessionID, messageID:MessageID, directory:String, agent:String, call:SessionToolCall, registry:ToolRegistry,
			permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>, turnID:Null<String>, turnTime:Null<Float>,
			instructionClaims:SessionInstructionClaims, loadedInstructions:Array<String>, ?filter:ToolFilter):SessionToolOutcome {
		events.push({type: "tool-call-start", callID: call.id, tool: call.tool});
		final ctx:ToolContext = switch permission {
			case null:
				{
					directory: directory,
					worktree: directory,
					sessionID: sessionID.toString(),
					messageID: messageID.toString(),
					callID: call.id,
					agent: agent,
					instructionClaims: instructionClaims,
					loadedInstructions: loadedInstructions,
				};
			case runtime:
				{
					directory: directory,
					worktree: directory,
					sessionID: sessionID.toString(),
					messageID: messageID.toString(),
					callID: call.id,
					agent: agent,
					instructionClaims: instructionClaims,
					loadedInstructions: loadedInstructions,
					ask: runtime.toToolAsk(),
				};
		}
		try {
			final toolResult = registry.execute(call.tool, call.input, ctx, filter);
			final part = completedToolPart(sessionID, messageID, call, toolResult, turnID, turnTime);
			events.push({
				type: "tool-call-finish",
				callID: call.id,
				tool: call.tool,
				status: "completed"
			});
			return {
				call: call,
				part: part,
				success: true,
				result: toolResult
			};
		} catch (error:ToolException) {
			final message = error.message == null ? Std.string(error.failure) : error.message;
			final part = erroredToolPart(sessionID, messageID, call, message, turnID, turnTime);
			events.push({
				type: "tool-call-finish",
				callID: call.id,
				tool: call.tool,
				status: "error",
				error: message
			});
			return {
				call: call,
				part: part,
				success: false,
				error: message
			};
		}
	}

	static function completedToolPart(sessionID:SessionID, messageID:MessageID, call:SessionToolCall, result:ToolResult, turnID:Null<String>,
			turnTime:Null<Float>):Part {
		final started = toolStarted(turnTime);
		final ended = toolEnded(turnTime);
		final attachments = result.attachments;
		var state:ToolState;
		if (attachments == null) {
			state = ToolCompleted({
				status: "completed",
				input: call.input,
				output: result.output,
				title: result.title,
				metadata: ToolStateMetadata.fromJson(result.metadata),
				time: {
					start: started,
					end: ended
				},
			});
		} else {
			state = ToolCompleted({
				status: "completed",
				input: call.input,
				output: result.output,
				title: result.title,
				metadata: ToolStateMetadata.fromJson(result.metadata),
				time: {
					start: started,
					end: ended
				},
				attachments: toolAttachments(sessionID, messageID, call, attachments, turnID),
			});
		}
		return ToolPart({
			id: PartID.make(scopedCallPart(partBase(TOOL_PART_ID, turnID), sessionID, call.id)),
			sessionID: sessionID,
			messageID: messageID,
			type: "tool",
			callID: call.id,
			tool: call.tool,
			state: state,
		});
	}

	static function toolAttachments(sessionID:SessionID, messageID:MessageID, call:SessionToolCall, attachments:Array<ToolResultAttachment>,
			turnID:Null<String>):Array<FilePartData> {
		final out:Array<FilePartData> = [];
		for (index in 0...attachments.length) {
			final attachment = attachments[index];
			out.push({
				id: PartID.make(scopedCallPart(partBase(TOOL_ATTACHMENT_PART_ID + "_" + index, turnID), sessionID, call.id)),
				sessionID: sessionID,
				messageID: messageID,
				type: attachment.type,
				mime: attachment.mime,
				filename: attachment.filename,
				url: attachment.url,
			});
		}
		return out;
	}

	static function erroredToolPart(sessionID:SessionID, messageID:MessageID, call:SessionToolCall, message:String, turnID:Null<String>,
			turnTime:Null<Float>):Part {
		final state:ToolState = ToolErrored({
			status: "error",
			input: call.input,
			error: message,
			metadata: ToolStateMetadata.empty(),
			time: {start: toolStarted(turnTime), end: toolEnded(turnTime)},
		});
		return ToolPart({
			id: PartID.make(scopedCallPart(partBase(TOOL_PART_ID, turnID), sessionID, call.id)),
			sessionID: sessionID,
			messageID: messageID,
			type: "tool",
			callID: call.id,
			tool: call.tool,
			state: state,
		});
	}

	static function persist(store:SessionStore, projectID:String, sessionIDText:String, directory:String, parentSessionID:Null<String>, userMessage:WithParts,
			assistantMessage:WithParts):Void {
		store.upsertProject({id: projectID, worktree: directory, name: "OpenCodeHX fixture"});
		store.createSession(persistedSessionInfo(store, projectID, sessionIDText, directory, parentSessionID,
			assistantCompletedFromInfo(assistantMessage.info)));
		persistMessage(store, userMessage);
		persistMessage(store, assistantMessage);
	}

	static function persistMessage(store:SessionStore, message:WithParts):Void {
		store.upsertMessage(message.info);
		final created = createdFromInfo(message.info);
		var offset = 0.0;
		for (part in message.parts) {
			store.upsertPart(part, created + offset);
			offset += 0.01;
		}
	}

	static function persistedSessionInfo(store:SessionStore, projectID:String, sessionIDText:String, directory:String, parentSessionID:Null<String>,
			updated:Float):SessionInfo {
		try {
			return resumedSessionInfo(store.getSession(SessionID.make(sessionIDText)), directory, updated);
		} catch (_:opencodehx.storage.StorageError.StorageException) {
			return sessionInfo(projectID, sessionIDText, directory, parentSessionID, updated);
		}
	}

	static function resumedSessionInfo(existing:SessionInfo, directory:String, updated:Float):SessionInfo {
		return {
			id: existing.id,
			slug: existing.slug,
			projectID: existing.projectID,
			workspaceID: existing.workspaceID,
			parentID: existing.parentID,
			directory: existing.directory,
			title: existing.title,
			version: existing.version,
			summary: existing.summary,
			share: existing.share,
			revert: existing.revert,
			permission: existing.permission,
			time: {
				created: existing.time.created,
				updated: updated,
				compacting: existing.time.compacting,
				archived: existing.time.archived,
			},
		};
	}

	static function sessionInfo(projectID:String, sessionIDText:String, directory:String, parentSessionID:Null<String>, updated:Float):SessionInfo {
		if (parentSessionID != null) {
			return {
				id: SessionID.make(sessionIDText),
				slug: "fixture-slug",
				projectID: projectID,
				parentID: SessionID.make(parentSessionID),
				directory: directory,
				title: "Say hello from the fixture.",
				version: BuildInfo.version,
				time: {
					created: CREATED_USER,
					updated: updated,
				},
			};
		}
		return {
			id: SessionID.make(sessionIDText),
			slug: "fixture-slug",
			projectID: projectID,
			directory: directory,
			title: "Say hello from the fixture.",
			version: BuildInfo.version,
			time: {
				created: CREATED_USER,
				updated: updated,
			},
		};
	}

	static function providerIdentity(info:ProviderInfo, model:ProviderModel, system:Array<String>):SessionProviderIdentity {
		return {
			info: info,
			model: model,
			system: system,
		};
	}

	static function encodeEvents(events:Array<FakeProviderEvent>):Array<SessionEvent> {
		final encoded:Array<SessionEvent> = [];
		for (event in events) {
			switch event {
				case StreamStart:
					encoded.push({type: "start"});
				case TextDelta(text):
					encoded.push({type: "text-delta", text: text});
				case Finish(reason):
					encoded.push({type: "finish", reason: reason});
			}
		}
		return encoded;
	}

	static function encodeAiSdkEvents(events:Array<AiSdkStreamEvent>):Array<SessionEvent> {
		final encoded:Array<SessionEvent> = [];
		for (event in events) {
			switch event {
				case TextDelta(text):
					encoded.push({type: "text-delta", text: text});
				case ToolCall(toolCallID, toolName, _):
					encoded.push({type: "tool-call", callID: toolCallID, tool: toolName});
				case ToolResult(toolCallID, toolName, _):
					encoded.push({type: "tool-result", callID: toolCallID, tool: toolName});
				case StreamError(message):
					encoded.push({type: "error", message: message});
				case StreamAbort(reason):
					encoded.push({type: "abort", message: reason});
				case Finish(reason):
					encoded.push({type: "finish", reason: finishReasonText(reason)});
			}
		}
		return encoded;
	}

	static function assistantFinish(events:Array<SessionEvent>):String {
		var index = events.length - 1;
		while (index >= 0) {
			final event = events[index];
			if (event.type == "finish" && event.reason != null)
				return event.reason;
			index--;
		}
		return "stop";
	}

	static function firstModelToolCall(events:Array<AiSdkStreamEvent>):Null<SessionToolCall> {
		for (event in events) {
			switch event {
				case ToolCall(toolCallID, toolName, input):
					return {
						id: toolCallID,
						tool: toolName,
						input: toolInput(input),
					};
				case _:
			}
		}
		return null;
	}

	static function toolInput(input:Unknown):ToolCallInput {
		// AI SDK providers may surface tool input as a parsed JSON value or as a
		// JSON string. Tool schemas remain the authority, so this boundary only
		// normalizes the transport shape before ToolRegistry validation.
		final raw:Dynamic = cast input;
		if (raw == null)
			return ToolCallInput.fromBoundary({});
		if (Std.isOfType(raw, String)) {
			try {
				return ToolCallInput.fromBoundary(Json.parse(cast raw));
			} catch (_:Dynamic) {
				// If a provider sends a non-JSON string, keep it as-is and let the
				// target tool report a normal invalid-arguments diagnostic.
				return ToolCallInput.fromBoundary(raw);
			}
		}
		return ToolCallInput.fromBoundary(raw);
	}

	static function toolHistoryTurn(outcome:SessionToolOutcome):AiModelToolResultTurn {
		final result = outcome.result;
		return {
			toolCallId: outcome.call.id,
			toolName: outcome.call.tool,
			input: outcome.call.input.unknown(),
			output: result == null ? "" : result.output,
		};
	}

	static function appendAssistantTool(message:WithParts, sessionIDText:String, directory:String, agent:String, call:SessionToolCall, registry:ToolRegistry,
			permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>, turnID:Null<String>, turnTime:Null<Float>,
			instructionClaims:SessionInstructionClaims, loadedInstructions:Array<String>, ?filter:ToolFilter):SessionToolOutcome {
		final sessionID = SessionID.make(sessionIDText);
		final messageID = MessageID.make(scoped(partBase(ASSISTANT_ID, turnID), sessionIDText));
		final outcome = executeTool(sessionID, messageID, directory, agent, call, registry, permission, events, turnID, turnTime, instructionClaims,
			loadedInstructions, filter);
		insertBeforeAssistantText(message, outcome.part);
		return outcome;
	}

	static function insertBeforeAssistantText(message:WithParts, part:Part):Void {
		for (index in 0...message.parts.length) {
			switch message.parts[index] {
				case TextPart(_):
					message.parts.insert(index, part);
					return;
				case _:
			}
		}
		message.parts.push(part);
	}

	static function replaceAssistantText(message:WithParts, text:String):Void {
		for (index in 0...message.parts.length) {
			switch message.parts[index] {
				case TextPart(data):
					message.parts[index] = TextPart({
						id: data.id,
						sessionID: data.sessionID,
						messageID: data.messageID,
						type: data.type,
						text: text,
						time: data.time,
					});
					return;
				case _:
			}
		}
	}

	static function abortedAssistantRecord(message:WithParts, events:Array<SessionEvent>):WithParts {
		return switch message.info {
			case AssistantInfo(assistant):
				{
					info: AssistantInfo({
						id: assistant.id,
						sessionID: assistant.sessionID,
						role: assistant.role,
						time: assistant.time,
						error: MessageJson.checked({name: "MessageAbortedError", message: "User aborted the request"}),
						parentID: assistant.parentID,
						modelID: assistant.modelID,
						providerID: assistant.providerID,
						mode: assistant.mode,
						agent: assistant.agent,
						path: assistant.path,
						summary: assistant.summary,
						cost: assistant.cost,
						tokens: assistant.tokens,
						structured: assistant.structured,
						variant: assistant.variant,
						finish: assistantFinish(events),
					}),
					parts: message.parts,
				};
			case _:
				message;
		}
	}

	static function collectText(events:Array<SessionEvent>):String {
		final parts:Array<String> = [];
		for (event in events) {
			if (event.type == "text-delta" && event.text != null)
				parts.push(event.text);
		}
		return parts.join("");
	}

	static function tokenUsage():TokenUsage {
		return {
			total: 12,
			input: 7,
			output: 5,
			reasoning: 0,
			cache: {read: 0, write: 0},
		};
	}

	static function tokenUsageFromAiSdk(usage:AiLanguageModelUsage):TokenUsage {
		final inputTokens = usage.inputTokens == null ? 0 : usage.inputTokens;
		final outputTokens = usage.outputTokens == null ? 0 : usage.outputTokens;
		final reasoningTokens = usage.reasoningTokens == null ? 0 : usage.reasoningTokens;
		final cacheRead = usage.cachedInputTokens == null ? 0 : usage.cachedInputTokens;
		final cacheWrite = usage.inputTokenDetails.cacheWriteTokens == null ? 0 : usage.inputTokenDetails.cacheWriteTokens;
		final total = usage.totalTokens == null ? inputTokens + outputTokens : usage.totalTokens;
		return {
			total: total,
			input: inputTokens,
			output: outputTokens,
			reasoning: reasoningTokens,
			cache: {read: cacheRead, write: cacheWrite},
		};
	}

	static function finishReasonText(reason:AiFinishReason):String {
		return reason;
	}

	static function userID(info:Info):MessageID {
		return switch info {
			case UserInfo(userData):
				userData.id;
			case AssistantInfo(assistantData):
				assistantData.id;
		}
	}

	static function normalizePrompt(input:String):String {
		if (input == null || StringTools.trim(input) == "")
			return "Say hello from the fixture.";
		return input;
	}

	static function fallback(value:Null<String>, fallbackValue:String):String {
		if (value == null || value == "")
			return fallbackValue;
		return value;
	}

	static function partBase(base:String, turnID:Null<String>):String {
		if (turnID == null || turnID == "")
			return base;
		return base + "_" + sanitizeID(turnID);
	}

	static function userCreated(turnTime:Null<Float>):Float {
		return turnTime == null ? CREATED_USER : turnTime;
	}

	static function assistantCreated(turnTime:Null<Float>):Float {
		return userCreated(turnTime) + 1;
	}

	static function assistantCompleted(turnTime:Null<Float>):Float {
		return userCreated(turnTime) + 2;
	}

	static function toolStarted(turnTime:Null<Float>):Float {
		return userCreated(turnTime) + 1.25;
	}

	static function toolEnded(turnTime:Null<Float>):Float {
		return userCreated(turnTime) + 1.75;
	}

	static function createdFromInfo(info:Info):Float {
		return switch info {
			case UserInfo(userData):
				userData.time.created;
			case AssistantInfo(assistantData):
				assistantData.time.created;
		}
	}

	static function assistantCompletedFromInfo(info:Info):Float {
		return switch info {
			case AssistantInfo(assistantData):
				assistantData.time.completed == null ? assistantData.time.created : assistantData.time.completed;
			case UserInfo(userData):
				userData.time.created;
		}
	}

	static function scopedFromSession(base:String, sessionID:SessionID):String {
		return scoped(base, sessionID.toString());
	}

	static function scopedCallPart(base:String, sessionID:SessionID, callID:String):String {
		return scoped(base + "_" + sanitizeID(callID), sessionID.toString());
	}

	static function scoped(base:String, sessionIDText:String):String {
		if (sessionIDText == SESSION_ID)
			return base;
		return base + "_" + sanitizeID(sessionIDText);
	}

	static function sanitizeID(value:String):String {
		final out = new StringBuf();
		for (index in 0...value.length) {
			final char = value.charAt(index);
			final code = char.charCodeAt(0);
			final alpha = (code >= "A".code && code <= "Z".code) || (code >= "a".code && code <= "z".code);
			final digit = code >= "0".code && code <= "9".code;
			out.add(alpha || digit || char == "_" || char == "-" ? char : "_");
		}
		return out.toString();
	}

	static function transcriptTools():Array<String> {
		return ["read", "write", "edit", "apply_patch"];
	}
}
