package opencodehx.session;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsage;
import opencodehx.externs.ai.AiSdk.AiModelMessage;
import opencodehx.externs.ai.AiSdk.AiModelToolResultTurn;
import opencodehx.provider.AiSdkProvider;
import opencodehx.provider.AiSdkProvider.AiSdkStreamEvent;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.FakeProvider.FakeProviderEvent;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.session.MessageTypes.AssistantMessage;
import opencodehx.session.MessageTypes.FilePartData;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.MessageJson;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TextPartData;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.MessageTypes.ToolStateMetadata;
import opencodehx.session.MessageTypes.UserMessage;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.SessionCompaction.SessionCompactionCheck;
import opencodehx.session.SessionCompaction.SessionCompactionResult;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.session.SessionRetry.SessionProviderError;
import opencodehx.session.SessionRetry.SessionRetryStatus;
import opencodehx.storage.SessionStore;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolRegistry;
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
	@:optional final files:Array<SessionFileInput>;
	@:optional final history:Array<WithParts>;
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
		final assistantMessage = assistantWithParts(sessionIDText, userMessage.info, text, input.directory, agent, provider, input.toolCall, registry,
			input.permission, events, retry, input.providerError, aborted, tokens, input.turnID, input.turnTime);

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
		final provider = providerIdentity(input.provider, input.model, ["You are an AI SDK provider runtime."]);
		final registry:ToolRegistry = input.registry == null ? new ToolRegistry() : input.registry;
		final events:Array<SessionEvent> = [];
		final aborted = input.aborted == true;
		var streamAborted = false;
		var tokens = tokenUsage();
		var modelToolCall:Null<SessionToolCall> = null;
		var toolOutcome:Null<SessionToolOutcome> = null;
		final messageHistory = textModelHistory(input.history);
		if (aborted) {
			events.push({type: "start"});
			events.push({type: "abort", message: "User aborted the request"});
		} else {
			events.push({type: "start"});
			final requestMessages = SessionLlm.requestModelMessages(provider.system, prompt, false, false, messageHistory);
			final stream = @:await AiSdkProvider.stream({
				model: input.language,
				prompt: prompt,
				messages: requestMessages,
				tools: AiSdkProvider.toolsFromRegistry(registry),
				abortImmediately: input.abortStreamImmediately,
			});
			streamAborted = stream.aborted;
			tokens = tokenUsageFromAiSdk(stream.totalUsage);
			modelToolCall = firstModelToolCall(stream.events);
			for (event in encodeAiSdkEvents(stream.events))
				events.push(event);
		}

		final assistantText = collectText(events);
		final userMessage = userWithParts(sessionIDText, prompt, agent, provider, input.turnID, input.turnTime, input.files);
		var wasAborted = aborted || streamAborted;
		final text = wasAborted ? "Request aborted." : assistantText;
		final toolCall = input.toolCall == null ? modelToolCall : input.toolCall;
		final assistantMessage = assistantWithParts(sessionIDText, userMessage.info, text, input.directory, agent, provider, toolCall, registry,
			input.permission, events, null, null, wasAborted, tokens, input.turnID, input.turnTime);
		toolOutcome = assistantMessage.tool;
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
			final continuation = @:await AiSdkProvider.stream({
				model: input.language,
				prompt: prompt,
				messages: continuationMessages,
				tools: AiSdkProvider.toolsFromRegistry(registry),
				abortImmediately: input.abortStreamImmediately,
			});
			streamAborted = continuation.aborted;
			wasAborted = wasAborted || streamAborted;
			final continuationEvents = encodeAiSdkEvents(continuation.events);
			for (event in continuationEvents)
				events.push(event);
			final continuedText = collectText(continuationEvents);
			final nextToolCall = firstModelToolCall(continuation.events);
			if (nextToolCall != null) {
				toolOutcome = appendAssistantTool(assistantMessage.message, sessionIDText, input.directory, agent, nextToolCall, registry, input.permission,
					events, input.turnID, input.turnTime);
			} else {
				if (continuedText != "")
					replaceAssistantText(assistantMessage.message, continuedText);
				break;
			}
		}

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
				tools: registry.ids(),
			},
			events: events,
			messages: [userMessage, assistantMessage.message],
			retry: null,
			compaction: null,
			aborted: wasAborted ? true : null,
			tool: toolOutcome,
		};
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

	static function textModelHistory(history:Null<Array<WithParts>>):Array<AiModelMessage> {
		final out:Array<AiModelMessage> = [];
		if (history == null)
			return out;
		for (message in history) {
			final text = firstText(message.parts);
			if (StringTools.trim(text) == "")
				continue;
			switch message.info {
				case UserInfo(_):
					out.push({
						role: "user",
						content: text,
					});
				case AssistantInfo(_):
					out.push({
						role: "assistant",
						content: text,
					});
			}
		}
		return out;
	}

	static function firstText(parts:Array<Part>):String {
		for (part in parts) {
			switch part {
				case TextPart(text):
					return text.text;
				case _:
			}
		}
		return "";
	}

	static function assistantWithParts(sessionIDText:String, parentInfo:Info, text:String, directory:String, agent:String, provider:SessionProviderIdentity,
			toolCall:Null<SessionToolCall>, registry:ToolRegistry, permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>,
			retry:Null<SessionRetryStatus>, providerError:Null<SessionProviderError>, aborted:Bool, tokens:TokenUsage, turnID:Null<String>,
			turnTime:Null<Float>):{
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
			error: aborted ? MessageJson.checked({name: "AbortedError", message: "User aborted the request"}) : null,
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
			toolOutcome = executeTool(sessionID, messageID, directory, agent, toolCall, registry, permission, events, turnID, turnTime);
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
			permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>, turnID:Null<String>,
			turnTime:Null<Float>):SessionToolOutcome {
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
				};
			case runtime:
				{
					directory: directory,
					worktree: directory,
					sessionID: sessionID.toString(),
					messageID: messageID.toString(),
					callID: call.id,
					agent: agent,
					ask: runtime.toToolAsk(),
				};
		}
		try {
			final toolResult = registry.execute(call.tool, call.input, ctx);
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
			input: Unknown.fromBoundary(outcome.call.input),
			output: result == null ? "" : result.output,
		};
	}

	static function appendAssistantTool(message:WithParts, sessionIDText:String, directory:String, agent:String, call:SessionToolCall, registry:ToolRegistry,
			permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>, turnID:Null<String>,
			turnTime:Null<Float>):SessionToolOutcome {
		final sessionID = SessionID.make(sessionIDText);
		final messageID = MessageID.make(scoped(partBase(ASSISTANT_ID, turnID), sessionIDText));
		final outcome = executeTool(sessionID, messageID, directory, agent, call, registry, permission, events, turnID, turnTime);
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
