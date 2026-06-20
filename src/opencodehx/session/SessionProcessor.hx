package opencodehx.session;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.externs.ai.AiSdk.AiFinishReason;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelUsage;
import opencodehx.provider.AiSdkProvider;
import opencodehx.provider.AiSdkProvider.AiSdkStreamEvent;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.FakeProvider.FakeProviderEvent;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.session.MessageTypes.AssistantMessage;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TextPartData;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.ToolState;
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
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolResult;

typedef SessionToolCall = {
	final id:String;
	final tool:String;
	// Tool inputs are JSON-shaped runtime payloads owned by each tool schema.
	// The registry validates them before tool implementations use the fields.
	final input:Dynamic;
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

typedef SessionProcessorInput = {
	final prompt:String;
	final directory:String;
	@:optional final sessionID:String;
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
}

typedef SessionAiSdkProcessorInput = {
	final prompt:String;
	final directory:String;
	final provider:ProviderInfo;
	final model:ProviderModel;
	final language:AiLanguageModel;
	@:optional final sessionID:String;
	@:optional final projectID:String;
	@:optional final agent:String;
	@:optional final aborted:Bool;
	@:optional final store:SessionStore;
	@:optional final registry:ToolRegistry;
	@:optional final permission:opencodehx.permission.PermissionRuntime;
	@:optional final toolCall:SessionToolCall;
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
	public static inline final ASSISTANT_PART_ID = "prt_assistant_text";
	public static inline final STEP_START_PART_ID = "prt_step_start";
	public static inline final STEP_FINISH_PART_ID = "prt_step_finish";
	public static inline final TOOL_PART_ID = "prt_tool_call";
	public static inline final RETRY_PART_ID = "prt_retry";
	public static inline final COMPACTION_PART_ID = "prt_compaction";
	public static inline final CREATED_USER = 1000.0;
	public static inline final CREATED_ASSISTANT = 1001.0;
	public static inline final COMPLETED_ASSISTANT = 1002.0;
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
		final userMessage = userWithParts(sessionIDText, prompt, agent, provider);
		final compaction = input.compaction == null ? null : SessionCompaction.check(input.compaction);
		if (compaction != null && compaction.overflow) {
			userMessage.parts.push(SessionCompaction.part(SessionID.make(sessionIDText), MessageID.make(scoped(USER_ID, sessionIDText)),
				PartID.make(scoped(COMPACTION_PART_ID, sessionIDText)), true, true));
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
			input.permission, events, retry, input.providerError, aborted, tokens);

		if (input.store != null) {
			persist(input.store, projectID, sessionIDText, input.directory, userMessage, assistantMessage.message);
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
		var tokens = tokenUsage();
		var modelToolCall:Null<SessionToolCall> = null;
		if (aborted) {
			events.push({type: "start"});
			events.push({type: "abort", message: "User aborted the request"});
		} else {
			events.push({type: "start"});
			final stream = @:await AiSdkProvider.stream({
				model: input.language,
				prompt: prompt,
				tools: AiSdkProvider.toolsFromRegistry(registry),
			});
			tokens = tokenUsageFromAiSdk(stream.totalUsage);
			modelToolCall = firstModelToolCall(stream.events);
			for (event in encodeAiSdkEvents(stream.events))
				events.push(event);
		}

		final assistantText = collectText(events);
		final userMessage = userWithParts(sessionIDText, prompt, agent, provider);
		final text = aborted ? "Request aborted." : assistantText;
		final toolCall = input.toolCall == null ? modelToolCall : input.toolCall;
		final assistantMessage = assistantWithParts(sessionIDText, userMessage.info, text, input.directory, agent, provider, toolCall, registry,
			input.permission, events, null, null, aborted, tokens);

		if (input.store != null) {
			persist(input.store, projectID, sessionIDText, input.directory, userMessage, assistantMessage.message);
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
			aborted: aborted ? true : null,
			tool: assistantMessage.tool,
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

	static function userWithParts(sessionIDText:String, prompt:String, agent:String, provider:SessionProviderIdentity):WithParts {
		final sessionID = SessionID.make(sessionIDText);
		final messageID = MessageID.make(scoped(USER_ID, sessionIDText));
		final info:UserMessage = {
			id: messageID,
			sessionID: sessionID,
			role: "user",
			time: {created: CREATED_USER},
			agent: agent,
			model: {providerID: provider.info.id, modelID: provider.model.id},
			format: OutputText,
			tools: {
				read: true,
				write: true,
				edit: true,
				apply_patch: true
			},
		};
		final text:TextPartData = {
			id: PartID.make(scoped(USER_PART_ID, sessionIDText)),
			sessionID: sessionID,
			messageID: messageID,
			type: "text",
			text: prompt,
			time: {start: CREATED_USER, end: CREATED_USER},
		};
		return {info: UserInfo(info), parts: [TextPart(text)]};
	}

	static function assistantWithParts(sessionIDText:String, parentInfo:Info, text:String, directory:String, agent:String, provider:SessionProviderIdentity,
			toolCall:Null<SessionToolCall>, registry:ToolRegistry, permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>,
			retry:Null<SessionRetryStatus>, providerError:Null<SessionProviderError>, aborted:Bool, tokens:TokenUsage):{
		final message:WithParts;
		final tool:Null<SessionToolOutcome>;
	} {
		final sessionID = SessionID.make(sessionIDText);
		final messageID = MessageID.make(scoped(ASSISTANT_ID, sessionIDText));
		final parentID = userID(parentInfo);
		final info:AssistantMessage = {
			id: messageID,
			sessionID: sessionID,
			role: "assistant",
			time: {created: CREATED_ASSISTANT, completed: COMPLETED_ASSISTANT},
			parentID: parentID,
			modelID: provider.model.id,
			providerID: provider.info.id,
			mode: "primary",
			agent: agent,
			path: {cwd: directory, root: directory},
			error: aborted ? {name: "AbortedError", message: "User aborted the request"} : null,
			cost: 0,
			tokens: tokens,
			finish: "stop",
		};

		final parts:Array<Part> = [];
		if (retry != null && providerError != null) {
			parts.push(RetryPart({
				id: PartID.make(scoped(RETRY_PART_ID, sessionIDText)),
				sessionID: sessionID,
				messageID: messageID,
				type: "retry",
				attempt: retry.attempt,
				error: SessionRetry.errorRecord(providerError),
				time: {
					created: CREATED_ASSISTANT
				},
			}));
		}
		var toolOutcome:Null<SessionToolOutcome> = null;
		if (toolCall != null) {
			parts.push(StepStartPart({
				id: PartID.make(scoped(STEP_START_PART_ID, sessionIDText)),
				sessionID: sessionID,
				messageID: messageID,
				type: "step-start",
			}));
			toolOutcome = executeTool(sessionID, messageID, directory, agent, toolCall, registry, permission, events);
			parts.push(toolOutcome.part);
		}

		parts.push(TextPart({
			id: PartID.make(scoped(ASSISTANT_PART_ID, sessionIDText)),
			sessionID: sessionID,
			messageID: messageID,
			type: "text",
			text: text,
			time: {start: CREATED_ASSISTANT, end: COMPLETED_ASSISTANT},
		}));

		if (toolCall != null) {
			parts.push(StepFinishPart({
				id: PartID.make(scoped(STEP_FINISH_PART_ID, sessionIDText)),
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
			permission:Null<opencodehx.permission.PermissionRuntime>, events:Array<SessionEvent>):SessionToolOutcome {
		events.push({type: "tool-call-start", callID: call.id, tool: call.tool});
		final ctx:ToolContext = {
			directory: directory,
			worktree: directory,
			sessionID: sessionID.toString(),
			messageID: messageID.toString(),
			callID: call.id,
			agent: agent,
		};
		if (permission != null)
			Reflect.setField(ctx, "ask", permission.toToolAsk());
		try {
			final toolResult = registry.execute(call.tool, call.input, ctx);
			final part = completedToolPart(sessionID, messageID, call, toolResult);
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
			final part = erroredToolPart(sessionID, messageID, call, message);
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

	static function completedToolPart(sessionID:SessionID, messageID:MessageID, call:SessionToolCall, result:ToolResult):Part {
		final state:ToolState = ToolCompleted({
			status: "completed",
			input: call.input,
			output: result.output,
			title: result.title,
			metadata: result.metadata == null ? {} : result.metadata,
			time: {
				start: TOOL_STARTED,
				end: TOOL_ENDED
			},
		});
		return ToolPart({
			id: PartID.make(scopedFromSession(TOOL_PART_ID, sessionID)),
			sessionID: sessionID,
			messageID: messageID,
			type: "tool",
			callID: call.id,
			tool: call.tool,
			state: state,
		});
	}

	static function erroredToolPart(sessionID:SessionID, messageID:MessageID, call:SessionToolCall, message:String):Part {
		final state:ToolState = ToolErrored({
			status: "error",
			input: call.input,
			error: message,
			metadata: {},
			time: {start: TOOL_STARTED, end: TOOL_ENDED},
		});
		return ToolPart({
			id: PartID.make(scopedFromSession(TOOL_PART_ID, sessionID)),
			sessionID: sessionID,
			messageID: messageID,
			type: "tool",
			callID: call.id,
			tool: call.tool,
			state: state,
		});
	}

	static function persist(store:SessionStore, projectID:String, sessionIDText:String, directory:String, userMessage:WithParts,
			assistantMessage:WithParts):Void {
		store.upsertProject({id: projectID, worktree: directory, name: "OpenCodeHX fixture"});
		store.createSession(sessionInfo(projectID, sessionIDText, directory));
		persistMessage(store, userMessage, CREATED_USER);
		persistMessage(store, assistantMessage, CREATED_ASSISTANT);
	}

	static function persistMessage(store:SessionStore, message:WithParts, created:Float):Void {
		store.upsertMessage(message.info);
		var offset = 0.0;
		for (part in message.parts) {
			store.upsertPart(part, created + offset);
			offset += 0.01;
		}
	}

	static function sessionInfo(projectID:String, sessionIDText:String, directory:String):SessionInfo {
		return {
			id: SessionID.make(sessionIDText),
			slug: "fixture-slug",
			projectID: projectID,
			directory: directory,
			title: "Say hello from the fixture.",
			version: BuildInfo.version,
			time: {
				created: CREATED_USER,
				updated: COMPLETED_ASSISTANT,
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

	static function toolInput(input:Unknown):Dynamic {
		// AI SDK providers may surface tool input as a parsed JSON value or as a
		// JSON string. Tool schemas remain the authority, so this boundary only
		// normalizes the transport shape before ToolRegistry validation.
		final raw:Dynamic = cast input;
		if (raw == null)
			return {};
		if (Std.isOfType(raw, String)) {
			try {
				return Json.parse(cast raw);
			} catch (_:Dynamic) {
				// If a provider sends a non-JSON string, keep it as-is and let the
				// target tool report a normal invalid-arguments diagnostic.
				return raw;
			}
		}
		return raw;
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

	static function scopedFromSession(base:String, sessionID:SessionID):String {
		return scoped(base, sessionID.toString());
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
