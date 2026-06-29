package opencodehx.session;

import genes.ts.JsonValue;
import genes.ts.Undefinable;
import genes.ts.Unknown;
import haxe.extern.EitherType;
import opencodehx.session.MessageTypes.AssistantMessage;
import opencodehx.session.MessageTypes.CreatedTime;
import opencodehx.session.MessageTypes.FilePartData;
import opencodehx.session.MessageTypes.FilePartSource;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.MessageJson;
import opencodehx.session.MessageTypes.OutputFormat;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TextSelection;
import opencodehx.session.MessageTypes.TimeRange;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.MessageTypes.ToolStateMetadata;
import opencodehx.session.MessageTypes.ToolTimeRange;
import opencodehx.session.MessageTypes.UserMessage;
import opencodehx.session.MessageTypes.UserSummary;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.session.SessionInfo.SessionRevert;
import opencodehx.session.SessionInfo.SessionShare;
import opencodehx.session.SessionInfo.SessionSummary;
import opencodehx.storage.SessionStore;

typedef SessionExportData = {
	final info:SessionExportInfo;
	final messages:Array<SessionExportMessage>;
}

typedef SessionExportInfo = {
	final id:String;
	final slug:String;
	final projectID:String;
	final workspaceID:Undefinable<String>;
	final parentID:Undefinable<String>;
	final directory:String;
	final title:String;
	final version:String;
	final summary:Undefinable<SessionSummary>;
	final share:Undefinable<SessionShare>;
	final revert:Undefinable<SessionExportRevert>;
	final permission:Undefinable<Unknown>;
	final time:SessionInfo.SessionTime;
}

typedef SessionExportRevert = {
	final messageID:String;
	final partID:Undefinable<String>;
	final snapshot:Undefinable<String>;
	final diff:Undefinable<String>;
}

typedef SessionExportMessage = {
	final info:SessionExportMessageInfo;
	final parts:Array<SessionExportPart>;
}

typedef SessionExportMessageInfo = {
	final id:String;
	final sessionID:String;
	final role:String;
	final time:SessionExportCreatedTime;
	final format:Undefinable<SessionExportOutputFormat>;
	final summary:Undefinable<EitherType<Bool, SessionExportUserSummary>>;
	final agent:String;
	final model:Undefinable<SessionExportModelSelection>;
	final system:Undefinable<String>;
	final tools:Undefinable<MessageJson>;
	final error:Undefinable<MessageJson>;
	final parentID:Undefinable<String>;
	final modelID:Undefinable<String>;
	final providerID:Undefinable<String>;
	final mode:Undefinable<String>;
	final path:Undefinable<SessionExportAssistantPath>;
	final cost:Undefinable<Float>;
	final tokens:Undefinable<SessionExportTokenUsage>;
	final structured:Undefinable<MessageJson>;
	final variant:Undefinable<String>;
	final finish:Undefinable<String>;
}

typedef SessionExportCreatedTime = {
	final created:Float;
	final completed:Undefinable<Float>;
}

typedef SessionExportOutputFormat = {
	final type:String;
	final schema:Undefinable<MessageJson>;
	final retryCount:Undefinable<Int>;
}

typedef SessionExportUserSummary = {
	final title:Undefinable<String>;
	final body:Undefinable<String>;
	final diffs:MessageJson;
}

typedef SessionExportModelSelection = {
	final providerID:String;
	final modelID:String;
	final variant:Undefinable<String>;
}

typedef SessionExportAssistantPath = {
	final cwd:String;
	final root:String;
}

typedef SessionExportTokenUsage = {
	final total:Undefinable<Float>;
	final input:Float;
	final output:Float;
	final reasoning:Float;
	final cache:MessageTypes.TokenCache;
}

typedef SessionExportPart = {
	final id:String;
	final sessionID:String;
	final messageID:String;
	final type:String;
	final snapshot:Undefinable<String>;
	final hash:Undefinable<String>;
	final files:Undefinable<Array<String>>;
	final text:Undefinable<String>;
	final synthetic:Undefinable<Bool>;
	final ignored:Undefinable<Bool>;
	final time:Undefinable<EitherType<SessionExportTimeRange, SessionExportCreatedTime>>;
	final metadata:Undefinable<JsonValue>;
	final mime:Undefinable<String>;
	final filename:Undefinable<String>;
	final url:Undefinable<String>;
	final source:Undefinable<EitherType<SessionExportFileSource, SessionExportTextSelection>>;
	final name:Undefinable<String>;
	final auto:Undefinable<Bool>;
	final overflow:Undefinable<Bool>;
	final tail_start_id:Undefinable<String>;
	final prompt:Undefinable<String>;
	final description:Undefinable<String>;
	final agent:Undefinable<String>;
	final model:Undefinable<SessionExportModelSelection>;
	final command:Undefinable<String>;
	final attempt:Undefinable<Float>;
	final error:Undefinable<MessageJson>;
	final reason:Undefinable<String>;
	final cost:Undefinable<Float>;
	final tokens:Undefinable<SessionExportTokenUsage>;
	final callID:Undefinable<String>;
	final tool:Undefinable<String>;
	final state:Undefinable<SessionExportToolState>;
}

typedef SessionExportTextSelection = {
	final value:String;
	final start:Int;
	final end:Int;
}

typedef SessionExportFileSource = {
	final type:String;
	final text:SessionExportTextSelection;
	final path:Undefinable<String>;
	final range:Undefinable<MessageJson>;
	final name:Undefinable<String>;
	final kind:Undefinable<Int>;
	final clientName:Undefinable<String>;
	final uri:Undefinable<String>;
}

typedef SessionExportTimeRange = {
	final start:Float;
	final end:Undefinable<Float>;
}

typedef SessionExportToolStartTime = {
	final start:Float;
}

typedef SessionExportToolTimeRange = {
	final start:Float;
	final end:Float;
	final compacted:Undefinable<Float>;
}

typedef SessionExportToolState = {
	final status:String;
	final input:Unknown;
	final raw:Undefinable<String>;
	final title:Undefinable<String>;
	final output:Undefinable<String>;
	final error:Undefinable<String>;
	final metadata:Undefinable<JsonValue>;
	final time:Undefinable<EitherType<SessionExportToolStartTime, SessionExportToolTimeRange>>;
	final attachments:Undefinable<Array<SessionExportPart>>;
}

class SessionExport {
	static inline final DEFAULT_EXPORT_LIMIT = 100000;

	public static function exportData(store:SessionStore, sessionID:SessionID, sanitize:Bool = false):SessionExportData {
		final info = store.getSession(sessionID);
		final page = store.pageMessages(sessionID, DEFAULT_EXPORT_LIMIT);
		final messages:Array<SessionExportMessage> = [];
		for (message in page.items) {
			messages.push(exportMessage(message, sanitize));
		}
		return {
			info: exportInfo(info, sanitize),
			messages: messages,
		};
	}

	static function exportInfo(info:SessionInfo, sanitize:Bool):SessionExportInfo {
		return {
			id: info.id.toString(),
			slug: info.slug,
			projectID: info.projectID,
			workspaceID: stringOrAbsent(info.workspaceID),
			parentID: info.parentID == null ? absent() : info.parentID.toString(),
			directory: sanitize ? redact("session-directory", info.id.toString(), info.directory) : info.directory,
			title: sanitize ? redact("session-title", info.id.toString(), info.title) : info.title,
			version: info.version,
			summary: info.summary == null ? absent() : info.summary,
			share: info.share == null ? absent() : info.share,
			revert: info.revert == null ? absent() : exportRevert(info.revert),
			permission: info.permission == null ? absent() : Unknown.fromBoundary(info.permission),
			time: info.time,
		};
	}

	static function exportRevert(revert:SessionRevert):SessionExportRevert {
		return {
			messageID: revert.messageID.toString(),
			partID: revert.partID == null ? absent() : revert.partID.toString(),
			snapshot: stringOrAbsent(revert.snapshot),
			diff: stringOrAbsent(revert.diff),
		};
	}

	static function exportMessage(message:WithParts, sanitize:Bool):SessionExportMessage {
		final parts:Array<SessionExportPart> = [];
		for (part in message.parts) {
			parts.push(exportPart(part, sanitize));
		}
		return {
			info: exportMessageInfo(message.info),
			parts: parts,
		};
	}

	static function exportMessageInfo(info:Info):SessionExportMessageInfo {
		return switch info {
			case UserInfo(user):
				exportUserInfo(user);
			case AssistantInfo(assistant):
				exportAssistantInfo(assistant);
		}
	}

	static function exportUserInfo(user:UserMessage):SessionExportMessageInfo {
		return {
			id: user.id.toString(),
			sessionID: user.sessionID.toString(),
			role: "user",
			time: exportCreatedTime(user.time),
			format: user.format == null ? absent() : exportOutputFormat(user.format),
			summary: user.summary == null ? absent() : exportUserSummary(user.summary),
			agent: user.agent,
			model: exportModel(user.model.providerID, user.model.modelID, user.model.variant),
			system: stringOrAbsent(user.system),
			tools: user.tools == null ? absent() : user.tools,
			error: absent(),
			parentID: absent(),
			modelID: absent(),
			providerID: absent(),
			mode: absent(),
			path: absent(),
			cost: absent(),
			tokens: absent(),
			structured: absent(),
			variant: absent(),
			finish: absent(),
		};
	}

	static function exportAssistantInfo(assistant:AssistantMessage):SessionExportMessageInfo {
		return {
			id: assistant.id.toString(),
			sessionID: assistant.sessionID.toString(),
			role: "assistant",
			time: exportCreatedTime(assistant.time),
			format: absent(),
			summary: assistant.summary == null ? absent() : assistant.summary,
			agent: assistant.agent,
			model: absent(),
			system: absent(),
			tools: absent(),
			error: assistant.error == null ? absent() : assistant.error,
			parentID: assistant.parentID.toString(),
			modelID: assistant.modelID,
			providerID: assistant.providerID,
			mode: assistant.mode,
			path: {
				cwd: assistant.path.cwd,
				root: assistant.path.root,
			},
			cost: assistant.cost,
			tokens: exportTokens(assistant.tokens),
			structured: assistant.structured == null ? absent() : assistant.structured,
			variant: stringOrAbsent(assistant.variant),
			finish: stringOrAbsent(assistant.finish),
		};
	}

	static function exportPart(part:Part, sanitize:Bool):SessionExportPart {
		return switch part {
			case SnapshotPart(data):
				partBase(data.id, data.sessionID, data.messageID, "snapshot", {
					snapshot: textValue("snapshot", data.id.toString(), data.snapshot, sanitize),
				});
			case PatchPart(data):
				partBase(data.id, data.sessionID, data.messageID, "patch", {
					hash: textValue("patch", data.id.toString(), data.hash, sanitize),
					files: data.files,
				});
			case TextPart(data):
				partBase(data.id, data.sessionID, data.messageID, "text", {
					text: textValue("text", data.id.toString(), data.text, sanitize),
					synthetic: boolOrAbsent(data.synthetic),
					ignored: boolOrAbsent(data.ignored),
					time: data.time == null ? absent() : exportTimeRange(data.time),
					metadata: messageJsonOrAbsent(data.metadata),
				});
			case ReasoningPart(data):
				partBase(data.id, data.sessionID, data.messageID, "reasoning", {
					text: textValue("reasoning", data.id.toString(), data.text, sanitize),
					time: exportTimeRange(data.time),
					metadata: messageJsonOrAbsent(data.metadata),
				});
			case FilePart(data):
				exportFilePart(data, sanitize);
			case AgentPart(data):
				partBase(data.id, data.sessionID, data.messageID, "agent", {
					name: data.name,
					source: data.source == null ? absent() : exportTextSelection(data.source),
				});
			case CompactionPart(data):
				partBase(data.id, data.sessionID, data.messageID, "compaction", {
					auto: data.auto,
					overflow: boolOrAbsent(data.overflow),
					tail_start_id: data.tail_start_id == null ? absent() : data.tail_start_id.toString(),
				});
			case SubtaskPart(data):
				partBase(data.id, data.sessionID, data.messageID, "subtask", {
					prompt: textValue("subtask-prompt", data.id.toString(), data.prompt, sanitize),
					description: textValue("subtask-description", data.id.toString(), data.description, sanitize),
					agent: data.agent,
					model: data.model == null ? absent() : exportModel(data.model.providerID, data.model.modelID, null),
					command: stringOrAbsent(data.command),
				});
			case RetryPart(data):
				partBase(data.id, data.sessionID, data.messageID, "retry", {
					attempt: data.attempt,
					error: data.error,
					time: exportCreatedTime(data.time),
				});
			case StepStartPart(data):
				partBase(data.id, data.sessionID, data.messageID, "step-start", {
					snapshot: stringOrAbsent(data.snapshot),
				});
			case StepFinishPart(data):
				partBase(data.id, data.sessionID, data.messageID, "step-finish", {
					reason: data.reason,
					snapshot: stringOrAbsent(data.snapshot),
					cost: data.cost,
					tokens: exportTokens(data.tokens),
				});
			case ToolPart(data):
				partBase(data.id, data.sessionID, data.messageID, "tool", {
					callID: data.callID,
					tool: data.tool,
					state: exportToolState(data.id.toString(), data.state, sanitize),
					metadata: toolMetadataOrAbsent(data.metadata),
				});
		}
	}

	static function exportFilePart(data:FilePartData, sanitize:Bool):SessionExportPart {
		return partBase(data.id, data.sessionID, data.messageID, "file", {
			mime: data.mime,
			filename: data.filename == null ? absent() : textValue("file-name", data.id.toString(), data.filename, sanitize),
			url: textValue("file-url", data.id.toString(), data.url, sanitize),
			source: data.source == null ? absent() : exportFileSource(data.source),
		});
	}

	static function exportToolState(partID:String, state:ToolState, sanitize:Bool):SessionExportToolState {
		return switch state {
			case ToolPending(pending):
				{
					status: "pending",
					input: exportToolInput(partID, pending.input, sanitize),
					raw: textValue("tool-raw", partID, pending.raw, sanitize),
					title: absent(),
					output: absent(),
					error: absent(),
					metadata: absent(),
					time: absent(),
					attachments: absent(),
				};
			case ToolRunning(running):
				{
					status: "running",
					input: exportToolInput(partID, running.input, sanitize),
					raw: absent(),
					title: running.title == null ? absent() : textValue("tool-title", partID, running.title, sanitize),
					output: absent(),
					error: absent(),
					metadata: toolMetadataOrAbsent(running.metadata),
					time: {
						start: running.time.start
					},
					attachments: absent(),
				};
			case ToolCompleted(completed):
				{
					status: "completed",
					input: exportToolInput(partID, completed.input, sanitize),
					raw: absent(),
					title: textValue("tool-title", partID, completed.title, sanitize),
					output: textValue("tool-output", partID, completed.output, sanitize),
					error: absent(),
					metadata: toolMetadataOrAbsent(completed.metadata),
					time: exportToolTimeRange(completed.time),
					attachments: completed.attachments == null ? absent() : exportAttachments(completed.attachments, sanitize),
				};
			case ToolErrored(errored):
				{
					status: "error",
					input: exportToolInput(partID, errored.input, sanitize),
					raw: absent(),
					title: absent(),
					output: absent(),
					error: textValue("tool-error", partID, errored.error, sanitize),
					metadata: toolMetadataOrAbsent(errored.metadata),
					time: exportToolTimeRange(errored.time),
					attachments: absent(),
				};
		}
	}

	static function exportAttachments(attachments:Array<FilePartData>, sanitize:Bool):Array<SessionExportPart> {
		final out:Array<SessionExportPart> = [];
		for (attachment in attachments) {
			out.push(exportFilePart(attachment, sanitize));
		}
		return out;
	}

	static function exportFileSource(source:FilePartSource):SessionExportFileSource {
		return switch source {
			case FileSource(data):
				{
					type: "file",
					text: exportTextSelection(data.text),
					path: data.path,
					range: absent(),
					name: absent(),
					kind: absent(),
					clientName: absent(),
					uri: absent(),
				};
			case SymbolSource(data):
				{
					type: "symbol",
					text: exportTextSelection(data.text),
					path: data.path,
					range: data.range,
					name: data.name,
					kind: data.kind,
					clientName: absent(),
					uri: absent(),
				};
			case ResourceSource(data):
				{
					type: "resource",
					text: exportTextSelection(data.text),
					path: absent(),
					range: absent(),
					name: absent(),
					kind: absent(),
					clientName: data.clientName,
					uri: data.uri,
				};
		}
	}

	static function partBase(id:PartID, sessionID:SessionID, messageID:MessageID, type:String, fields:SessionExportPartPatch):SessionExportPart {
		return {
			id: id.toString(),
			sessionID: sessionID.toString(),
			messageID: messageID.toString(),
			type: type,
			snapshot: optional(fields.snapshot),
			hash: optional(fields.hash),
			files: optional(fields.files),
			text: optional(fields.text),
			synthetic: optional(fields.synthetic),
			ignored: optional(fields.ignored),
			time: optional(fields.time),
			metadata: optional(fields.metadata),
			mime: optional(fields.mime),
			filename: optional(fields.filename),
			url: optional(fields.url),
			source: optional(fields.source),
			name: optional(fields.name),
			auto: optional(fields.auto),
			overflow: optional(fields.overflow),
			tail_start_id: optional(fields.tail_start_id),
			prompt: optional(fields.prompt),
			description: optional(fields.description),
			agent: optional(fields.agent),
			model: optional(fields.model),
			command: optional(fields.command),
			attempt: optional(fields.attempt),
			error: optional(fields.error),
			reason: optional(fields.reason),
			cost: optional(fields.cost),
			tokens: optional(fields.tokens),
			callID: optional(fields.callID),
			tool: optional(fields.tool),
			state: optional(fields.state),
		};
	}

	static function exportOutputFormat(format:OutputFormat):SessionExportOutputFormat {
		return switch format {
			case OutputText:
				{type: "text", schema: absent(), retryCount: absent()};
			case OutputJsonSchema(schema, retryCount):
				{type: "json_schema", schema: schema, retryCount: retryCount};
		}
	}

	static function exportUserSummary(summary:UserSummary):SessionExportUserSummary {
		return {
			title: stringOrAbsent(summary.title),
			body: stringOrAbsent(summary.body),
			diffs: summary.diffs,
		};
	}

	static function exportModel(providerID:String, modelID:String, variant:Null<String>):SessionExportModelSelection {
		return {
			providerID: providerID,
			modelID: modelID,
			variant: stringOrAbsent(variant),
		};
	}

	static function exportCreatedTime(time:CreatedTime):SessionExportCreatedTime {
		return {
			created: time.created,
			completed: floatOrAbsent(time.completed),
		};
	}

	static function exportTimeRange(time:TimeRange):SessionExportTimeRange {
		return {
			start: time.start,
			end: floatOrAbsent(time.end),
		};
	}

	static function exportToolTimeRange(time:ToolTimeRange):SessionExportToolTimeRange {
		return {
			start: time.start,
			end: time.end,
			compacted: floatOrAbsent(time.compacted),
		};
	}

	static function exportTokens(tokens:TokenUsage):SessionExportTokenUsage {
		return {
			total: floatOrAbsent(tokens.total),
			input: tokens.input,
			output: tokens.output,
			reasoning: tokens.reasoning,
			cache: tokens.cache,
		};
	}

	static function exportTextSelection(selection:TextSelection):SessionExportTextSelection {
		return {
			value: selection.value,
			start: selection.start,
			end: selection.end,
		};
	}

	static function exportToolInput(partID:String, input:Unknown, sanitize:Bool):Unknown {
		return sanitize ? Unknown.fromBoundary(redact("tool-input", partID, "input")) : input;
	}

	static function textValue(kind:String, id:String, value:String, sanitize:Bool):String {
		return sanitize ? redact(kind, id, value) : value;
	}

	static function redact(kind:String, id:String, value:String):String {
		return StringTools.trim(value) == "" ? value : '[redacted:${kind}:${id}]';
	}

	static inline function absent<T>():Undefinable<T> {
		return Undefinable.absent();
	}

	static inline function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? absent() : value;
	}

	static inline function boolOrAbsent(value:Null<Bool>):Undefinable<Bool> {
		return value == null ? absent() : value;
	}

	static inline function floatOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? absent() : value;
	}

	static inline function optional<T>(value:Null<Undefinable<T>>):Undefinable<T> {
		return value == null ? absent() : value;
	}

	static inline function messageJsonOrAbsent(value:Null<MessageJson>):Undefinable<JsonValue> {
		if (value == null)
			return absent();
		final present:JsonValue = value;
		return present;
	}

	static inline function toolMetadataOrAbsent(value:Null<ToolStateMetadata>):Undefinable<JsonValue> {
		if (value == null)
			return absent();
		final present:JsonValue = value;
		return present;
	}
}

private typedef SessionExportPartPatch = {
	@:optional final snapshot:Undefinable<String>;
	@:optional final hash:Undefinable<String>;
	@:optional final files:Undefinable<Array<String>>;
	@:optional final text:Undefinable<String>;
	@:optional final synthetic:Undefinable<Bool>;
	@:optional final ignored:Undefinable<Bool>;
	@:optional final time:Undefinable<EitherType<SessionExportTimeRange, SessionExportCreatedTime>>;
	@:optional final metadata:Undefinable<JsonValue>;
	@:optional final mime:Undefinable<String>;
	@:optional final filename:Undefinable<String>;
	@:optional final url:Undefinable<String>;
	@:optional final source:Undefinable<EitherType<SessionExportFileSource, SessionExportTextSelection>>;
	@:optional final name:Undefinable<String>;
	@:optional final auto:Undefinable<Bool>;
	@:optional final overflow:Undefinable<Bool>;
	@:optional final tail_start_id:Undefinable<String>;
	@:optional final prompt:Undefinable<String>;
	@:optional final description:Undefinable<String>;
	@:optional final agent:Undefinable<String>;
	@:optional final model:Undefinable<SessionExportModelSelection>;
	@:optional final command:Undefinable<String>;
	@:optional final attempt:Undefinable<Float>;
	@:optional final error:Undefinable<MessageJson>;
	@:optional final reason:Undefinable<String>;
	@:optional final cost:Undefinable<Float>;
	@:optional final tokens:Undefinable<SessionExportTokenUsage>;
	@:optional final callID:Undefinable<String>;
	@:optional final tool:Undefinable<String>;
	@:optional final state:Undefinable<SessionExportToolState>;
}
