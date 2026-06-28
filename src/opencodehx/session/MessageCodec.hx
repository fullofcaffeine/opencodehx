package opencodehx.session;

import genes.ts.JsonCodec;
import genes.ts.Unknown;
import haxe.Json;
import opencodehx.host.node.NodeBuffer;
import opencodehx.session.MessageError.MessageException;
import opencodehx.session.MessageError.MessageFailure;
import opencodehx.session.MessageTypes.AssistantMessage;
import opencodehx.session.MessageTypes.CompactionPartData;
import opencodehx.session.MessageTypes.Cursor;
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
import opencodehx.session.MessageTypes.UserMessage;
import opencodehx.session.MessageTypes.WithParts;

typedef PartBase = {
	final id:PartID;
	final sessionID:SessionID;
	final messageID:MessageID;
}

class MessageCodec {
	public static function parseWithParts(text:String, ?source:String):WithParts {
		try {
			return decodeWithParts(Json.parse(text), source == null ? "json" : source);
		} catch (messageError:MessageException) {
			throw messageError;
		} catch (parseError:Dynamic) {
			throw invalid(source == null ? "json" : source, ['Invalid JSON: ${Std.string(parseError)}']);
		}
	}

	public static function stringifyWithParts(value:WithParts):String {
		return Json.stringify(encodeWithParts(value));
	}

	public static function decodeWithParts(data:Dynamic, ?source:String):WithParts {
		final label = source == null ? "message" : source;
		final issues:Array<String> = [];
		if (!isObjectRecord(data)) {
			throw invalid(label, ["Expected message wrapper to be an object"]);
		}
		final info = decodeInfo(requiredObject(data, "info", issues, "info"), issues, "info");
		final rawParts = requiredArray(data, "parts", issues, "parts");
		final parts:Array<Part> = [];
		for (index in 0...rawParts.length) {
			parts.push(decodePart(rawParts[index], issues, 'parts[${index}]'));
		}
		if (issues.length > 0)
			throw invalid(label, issues);
		return {info: info, parts: parts};
	}

	public static function encodeWithParts(value:WithParts):Dynamic {
		final result:Dynamic = {};
		Reflect.setField(result, "info", encodeInfo(value.info));
		Reflect.setField(result, "parts", value.parts.map(encodePart));
		return result;
	}

	public static function decodeInfoRecord(data:Dynamic, ?source:String):Info {
		final label = source == null ? "message.info" : source;
		final issues:Array<String> = [];
		final info = decodeInfo(data, issues, label);
		if (issues.length > 0)
			throw invalid(label, issues);
		return info;
	}

	public static function encodeInfoRecord(info:Info):Dynamic {
		return encodeInfo(info);
	}

	public static function decodePartRecord(data:Dynamic, ?source:String):Part {
		final label = source == null ? "message.part" : source;
		final issues:Array<String> = [];
		final part = decodePart(data, issues, label);
		if (issues.length > 0)
			throw invalid(label, issues);
		return part;
	}

	public static function encodePartRecord(part:Part):Dynamic {
		return encodePart(part);
	}

	public static function encodeCursor(cursor:Cursor):String {
		return NodeBuffer.toBase64Url(Json.stringify({
			id: cursor.id.toString(),
			time: cursor.time,
		}));
	}

	public static function decodeCursor(value:String):Cursor {
		try {
			final issues:Array<String> = [];
			final data = Json.parse(NodeBuffer.fromBase64Url(value));
			final cursor:Cursor = {
				id: MessageID.make(requiredString(data, "id", issues, "cursor.id")),
				time: requiredFloat(data, "time", issues, "cursor.time"),
			};
			if (issues.length > 0)
				throw invalid("cursor", issues);
			return cursor;
		} catch (messageError:MessageException) {
			throw messageError;
		} catch (parseError:Dynamic) {
			// Base64/JSON parsing crosses through JS runtime exceptions that do
			// not share a Haxe type. Convert them immediately into the typed
			// message-codec failure used by callers.
			throw invalid("cursor", ['Invalid cursor: ${Std.string(parseError)}']);
		}
	}

	static function decodeInfo(data:Dynamic, issues:Array<String>, path:String):Info {
		return switch requiredString(data, "role", issues, path + ".role") {
			case "user":
				UserInfo(decodeUser(data, issues, path));
			case "assistant":
				AssistantInfo(decodeAssistant(data, issues, path));
			case role:
				issues.push('${path}.role: unknown message role "${role}"');
				UserInfo({
					id: MessageID.make(""),
					sessionID: SessionID.make(""),
					role: "user",
					time: {created: 0},
					agent: "",
					model: {providerID: "", modelID: ""},
				});
		}
	}

	static function decodeUser(data:Dynamic, issues:Array<String>, path:String):UserMessage {
		final result:UserMessage = {
			id: MessageID.make(requiredString(data, "id", issues, path + ".id")),
			sessionID: SessionID.make(requiredString(data, "sessionID", issues, path + ".sessionID")),
			role: "user",
			time: decodeCreatedTime(requiredObject(data, "time", issues, path + ".time"), issues, path + ".time"),
			agent: requiredString(data, "agent", issues, path + ".agent"),
			model: decodeUserModel(requiredObject(data, "model", issues, path + ".model"), issues, path + ".model"),
		};
		if (has(data, "format"))
			Reflect.setField(result, "format", decodeOutputFormat(Reflect.field(data, "format"), issues, path + ".format"));
		if (has(data, "summary"))
			Reflect.setField(result, "summary", decodeUserSummary(Reflect.field(data, "summary"), issues, path + ".summary"));
		copyOptional(data, result, "system");
		copyOptionalMessageJson(data, result, "tools", issues, path + ".tools");
		return result;
	}

	static function decodeAssistant(data:Dynamic, issues:Array<String>, path:String):AssistantMessage {
		final result:AssistantMessage = {
			id: MessageID.make(requiredString(data, "id", issues, path + ".id")),
			sessionID: SessionID.make(requiredString(data, "sessionID", issues, path + ".sessionID")),
			role: "assistant",
			time: decodeCreatedTime(requiredObject(data, "time", issues, path + ".time"), issues, path + ".time"),
			parentID: MessageID.make(requiredString(data, "parentID", issues, path + ".parentID")),
			modelID: requiredString(data, "modelID", issues, path + ".modelID"),
			providerID: requiredString(data, "providerID", issues, path + ".providerID"),
			mode: requiredString(data, "mode", issues, path + ".mode"),
			agent: requiredString(data, "agent", issues, path + ".agent"),
			path: {
				cwd: requiredString(requiredObject(data, "path", issues, path + ".path"), "cwd", issues, path + ".path.cwd"),
				root: requiredString(requiredObject(data, "path", issues, path + ".path"), "root", issues, path + ".path.root"),
			},
			cost: requiredFloat(data, "cost", issues, path + ".cost"),
			tokens: decodeTokens(requiredObject(data, "tokens", issues, path + ".tokens"), issues, path + ".tokens"),
		};
		copyOptionalMessageJson(data, result, "error", issues, path + ".error");
		copyOptional(data, result, "summary");
		copyOptionalMessageJson(data, result, "structured", issues, path + ".structured");
		copyOptional(data, result, "variant");
		copyOptional(data, result, "finish");
		return result;
	}

	static function decodePart(data:Dynamic, issues:Array<String>, path:String):Part {
		if (!isObjectRecord(data)) {
			issues.push('${path}: expected object');
			return TextPart(emptyTextPart());
		}
		final base = decodePartBase(data, issues, path);
		return switch requiredString(data, "type", issues, path + ".type") {
			case "snapshot":
				SnapshotPart({
					id: base.id,
					sessionID: base.sessionID,
					messageID: base.messageID,
					type: "snapshot",
					snapshot: requiredString(data, "snapshot", issues, path + ".snapshot"),
				});
			case "patch":
				PatchPart({
					id: base.id,
					sessionID: base.sessionID,
					messageID: base.messageID,
					type: "patch",
					hash: requiredString(data, "hash", issues, path + ".hash"),
					files: decodeStringArray(requiredArray(data, "files", issues, path + ".files"), issues, path + ".files"),
				});
			case "text":
				decodeTextPart(data, base, issues, path);
			case "reasoning":
				ReasoningPart({
					id: base.id,
					sessionID: base.sessionID,
					messageID: base.messageID,
					type: "reasoning",
					text: requiredString(data, "text", issues, path + ".text"),
					time: decodeTimeRange(requiredObject(data, "time", issues, path + ".time"), issues, path + ".time"),
				});
			case "file":
				FilePart(decodeFilePart(data, base, issues, path));
			case "agent":
				decodeAgentPart(data, base, issues, path);
			case "compaction":
				CompactionPart(decodeCompactionPart(data, base, issues, path));
			case "subtask":
				decodeSubtaskPart(data, base, issues, path);
			case "retry":
				RetryPart({
					id: base.id,
					sessionID: base.sessionID,
					messageID: base.messageID,
					type: "retry",
					attempt: requiredFloat(data, "attempt", issues, path + ".attempt"),
					error: Reflect.field(data, "error"),
					time: decodeCreatedTime(requiredObject(data, "time", issues, path + ".time"), issues, path + ".time"),
				});
			case "step-start":
				final stepStart:Dynamic = {
					id: base.id,
					sessionID: base.sessionID,
					messageID: base.messageID,
					type: "step-start",
				};
				copyOptional(data, stepStart, "snapshot");
				StepStartPart(cast stepStart);
			case "step-finish":
				final finish:Dynamic = {
					id: base.id,
					sessionID: base.sessionID,
					messageID: base.messageID,
					type: "step-finish",
					reason: requiredString(data, "reason", issues, path + ".reason"),
					cost: requiredFloat(data, "cost", issues, path + ".cost"),
					tokens: decodeTokens(requiredObject(data, "tokens", issues, path + ".tokens"), issues, path + ".tokens"),
				};
				copyOptional(data, finish, "snapshot");
				StepFinishPart(cast finish);
			case "tool":
				decodeToolPart(data, base, issues, path);
			case kind:
				issues.push('${path}.type: unknown part type "${kind}"');
				TextPart(emptyTextPart());
		}
	}

	static function decodeTextPart(data:Dynamic, base:PartBase, issues:Array<String>, path:String):Part {
		final text:Dynamic = {
			id: base.id,
			sessionID: base.sessionID,
			messageID: base.messageID,
			type: "text",
			text: requiredString(data, "text", issues, path + ".text"),
		};
		copyOptional(data, text, "synthetic");
		copyOptional(data, text, "ignored");
		copyOptional(data, text, "metadata");
		if (has(data, "time"))
			Reflect.setField(text, "time", decodeTimeRange(Reflect.field(data, "time"), issues, path + ".time"));
		return TextPart(cast text);
	}

	static function decodeAgentPart(data:Dynamic, base:PartBase, issues:Array<String>, path:String):Part {
		final agent:Dynamic = {
			id: base.id,
			sessionID: base.sessionID,
			messageID: base.messageID,
			type: "agent",
			name: requiredString(data, "name", issues, path + ".name"),
		};
		if (has(data, "source"))
			Reflect.setField(agent, "source", decodeTextSelection(Reflect.field(data, "source"), issues, path + ".source"));
		return AgentPart(cast agent);
	}

	static function decodeCompactionPart(data:Dynamic, base:PartBase, issues:Array<String>, path:String):CompactionPartData {
		final compact:Dynamic = {
			id: base.id,
			sessionID: base.sessionID,
			messageID: base.messageID,
			type: "compaction",
			auto: requiredBool(data, "auto", issues, path + ".auto"),
		};
		copyOptional(data, compact, "overflow");
		if (has(data, "tail_start_id"))
			Reflect.setField(compact, "tail_start_id", MessageID.make(requiredString(data, "tail_start_id", issues, path + ".tail_start_id")));
		return cast compact;
	}

	static function decodeSubtaskPart(data:Dynamic, base:PartBase, issues:Array<String>, path:String):Part {
		final subtask:Dynamic = {
			id: base.id,
			sessionID: base.sessionID,
			messageID: base.messageID,
			type: "subtask",
			prompt: requiredString(data, "prompt", issues, path + ".prompt"),
			description: requiredString(data, "description", issues, path + ".description"),
			agent: requiredString(data, "agent", issues, path + ".agent"),
		};
		if (has(data, "model")) {
			final model = requiredObject(data, "model", issues, path + ".model");
			Reflect.setField(subtask, "model", {
				providerID: requiredString(model, "providerID", issues, path + ".model.providerID"),
				modelID: requiredString(model, "modelID", issues, path + ".model.modelID"),
			});
		}
		copyOptional(data, subtask, "command");
		return SubtaskPart(cast subtask);
	}

	static function decodeToolPart(data:Dynamic, base:PartBase, issues:Array<String>, path:String):Part {
		final tool:Dynamic = {
			id: base.id,
			sessionID: base.sessionID,
			messageID: base.messageID,
			type: "tool",
			callID: requiredString(data, "callID", issues, path + ".callID"),
			tool: requiredString(data, "tool", issues, path + ".tool"),
			state: decodeToolState(requiredObject(data, "state", issues, path + ".state"), issues, path + ".state"),
		};
		copyOptional(data, tool, "metadata");
		return ToolPart(cast tool);
	}

	static function decodeFilePart(data:Dynamic, base:PartBase, issues:Array<String>, path:String):FilePartData {
		final file:Dynamic = {
			id: base.id,
			sessionID: base.sessionID,
			messageID: base.messageID,
			type: "file",
			mime: requiredString(data, "mime", issues, path + ".mime"),
			url: requiredString(data, "url", issues, path + ".url"),
		};
		copyOptional(data, file, "filename");
		if (has(data, "source"))
			Reflect.setField(file, "source", decodeFileSource(Reflect.field(data, "source"), issues, path + ".source"));
		return cast file;
	}

	static function decodeFileSource(data:Dynamic, issues:Array<String>, path:String):FilePartSource {
		final text = decodeTextSelection(requiredObject(data, "text", issues, path + ".text"), issues, path + ".text");
		return switch requiredString(data, "type", issues, path + ".type") {
			case "file":
				FileSource({text: text, path: requiredString(data, "path", issues, path + ".path")});
			case "symbol":
				SymbolSource({
					text: text,
					path: requiredString(data, "path", issues, path + ".path"),
					range: requiredMessageJson(data, "range", issues, path + ".range"),
					name: requiredString(data, "name", issues, path + ".name"),
					kind: requiredInt(data, "kind", issues, path + ".kind"),
				});
			case "resource":
				ResourceSource({
					text: text,
					clientName: requiredString(data, "clientName", issues, path + ".clientName"),
					uri: requiredString(data, "uri", issues, path + ".uri"),
				});
			case kind:
				issues.push('${path}.type: unknown file source type "${kind}"');
				FileSource({text: text, path: ""});
		}
	}

	static function decodeToolState(data:Dynamic, issues:Array<String>, path:String):ToolState {
		return switch requiredString(data, "status", issues, path + ".status") {
			case "pending":
				ToolPending({
					status: "pending",
					input: requiredObject(data, "input", issues, path + ".input"),
					raw: requiredString(data, "raw", issues, path + ".raw"),
				});
			case "running":
				final running:Dynamic = {
					status: "running",
					input: requiredObject(data, "input", issues, path + ".input"),
					time: {start: requiredFloat(requiredObject(data, "time", issues, path + ".time"), "start", issues, path + ".time.start")},
				};
				copyOptional(data, running, "title");
				copyOptionalToolStateMetadata(data, running, "metadata", issues, path + ".metadata");
				ToolRunning(cast running);
			case "completed":
				final completed:Dynamic = {
					status: "completed",
					input: requiredObject(data, "input", issues, path + ".input"),
					output: requiredString(data, "output", issues, path + ".output"),
					title: requiredString(data, "title", issues, path + ".title"),
					metadata: requiredToolStateMetadata(data, "metadata", issues, path + ".metadata"),
					time: decodeToolTimeRange(requiredObject(data, "time", issues, path + ".time"), issues, path + ".time"),
				};
				if (has(data, "attachments")) {
					final rawAttachments = requiredArray(data, "attachments", issues, path + ".attachments");
					final attachments:Array<FilePartData> = [];
					for (index in 0...rawAttachments.length) {
						final attachment = rawAttachments[index];
						final base = decodePartBase(attachment, issues, '${path}.attachments[${index}]');
						attachments.push(decodeFilePart(attachment, base, issues, '${path}.attachments[${index}]'));
					}
					Reflect.setField(completed, "attachments", attachments);
				}
				ToolCompleted(cast completed);
			case "error":
				final error:Dynamic = {
					status: "error",
					input: requiredObject(data, "input", issues, path + ".input"),
					error: requiredString(data, "error", issues, path + ".error"),
					time: decodeToolTimeRange(requiredObject(data, "time", issues, path + ".time"), issues, path + ".time"),
				};
				copyOptionalToolStateMetadata(data, error, "metadata", issues, path + ".metadata");
				ToolErrored(cast error);
			case status:
				issues.push('${path}.status: unknown tool state "${status}"');
				ToolPending({status: "pending", input: {}, raw: ""});
		}
	}

	static function decodeOutputFormat(data:Dynamic, issues:Array<String>, path:String):OutputFormat {
		return switch requiredString(data, "type", issues, path + ".type") {
			case "text":
				OutputText;
			case "json_schema":
				final retry = has(data, "retryCount") ? requiredInt(data, "retryCount", issues, path + ".retryCount") : 2;
				if (retry < 0)
					issues.push(path + ".retryCount: expected non-negative integer");
				OutputJsonSchema(requiredMessageJson(data, "schema", issues, path + ".schema"), retry);
			case kind:
				issues.push('${path}.type: unknown output format "${kind}"');
				OutputText;
		}
	}

	static function decodeUserModel(data:Dynamic, issues:Array<String>, path:String):Dynamic {
		final model:Dynamic = {
			providerID: requiredString(data, "providerID", issues, path + ".providerID"),
			modelID: requiredString(data, "modelID", issues, path + ".modelID"),
		};
		copyOptional(data, model, "variant");
		return model;
	}

	static function decodeUserSummary(data:Dynamic, issues:Array<String>, path:String):Dynamic {
		final summary:Dynamic = {diffs: requiredMessageJson(data, "diffs", issues, path + ".diffs")};
		copyOptional(data, summary, "title");
		copyOptional(data, summary, "body");
		return summary;
	}

	static function decodePartBase(data:Dynamic, issues:Array<String>, path:String):PartBase {
		return {
			id: PartID.make(requiredString(data, "id", issues, path + ".id")),
			sessionID: SessionID.make(requiredString(data, "sessionID", issues, path + ".sessionID")),
			messageID: MessageID.make(requiredString(data, "messageID", issues, path + ".messageID")),
		};
	}

	static function decodeCreatedTime(data:Dynamic, issues:Array<String>, path:String):Dynamic {
		final time:Dynamic = {created: requiredFloat(data, "created", issues, path + ".created")};
		copyOptional(data, time, "completed");
		return time;
	}

	static function decodeTimeRange(data:Dynamic, issues:Array<String>, path:String):TimeRange {
		final time:Dynamic = {start: requiredFloat(data, "start", issues, path + ".start")};
		copyOptional(data, time, "end");
		return cast time;
	}

	static function decodeToolTimeRange(data:Dynamic, issues:Array<String>, path:String):Dynamic {
		final time:Dynamic = {
			start: requiredFloat(data, "start", issues, path + ".start"),
			end: requiredFloat(data, "end", issues, path + ".end"),
		};
		copyOptional(data, time, "compacted");
		return time;
	}

	static function decodeTextSelection(data:Dynamic, issues:Array<String>, path:String):TextSelection {
		return {
			value: requiredString(data, "value", issues, path + ".value"),
			start: requiredInt(data, "start", issues, path + ".start"),
			end: requiredInt(data, "end", issues, path + ".end"),
		};
	}

	static function decodeTokens(data:Dynamic, issues:Array<String>, path:String):TokenUsage {
		final tokens:Dynamic = {
			input: requiredFloat(data, "input", issues, path + ".input"),
			output: requiredFloat(data, "output", issues, path + ".output"),
			reasoning: requiredFloat(data, "reasoning", issues, path + ".reasoning"),
			cache: {
				read: requiredFloat(requiredObject(data, "cache", issues, path + ".cache"), "read", issues, path + ".cache.read"),
				write: requiredFloat(requiredObject(data, "cache", issues, path + ".cache"), "write", issues, path + ".cache.write"),
			},
		};
		copyOptional(data, tokens, "total");
		return cast tokens;
	}

	static function encodeInfo(info:Info):Dynamic {
		return switch info {
			case UserInfo(userData):
				final out:Dynamic = {
					id: userData.id.toString(),
					sessionID: userData.sessionID.toString(),
					role: "user",
					time: encodeCreatedTime(userData.time),
					agent: userData.agent,
					model: encodeObject(userData.model),
				};
				if (userData.format != null)
					Reflect.setField(out, "format", encodeOutputFormat(userData.format));
				copyOut(userData, out, "summary");
				copyOut(userData, out, "system");
				copyOut(userData, out, "tools");
				out;
			case AssistantInfo(assistantData):
				final out:Dynamic = {
					id: assistantData.id.toString(),
					sessionID: assistantData.sessionID.toString(),
					role: "assistant",
					time: encodeCreatedTime(assistantData.time),
					parentID: assistantData.parentID.toString(),
					modelID: assistantData.modelID,
					providerID: assistantData.providerID,
					mode: assistantData.mode,
					agent: assistantData.agent,
					path: encodeObject(assistantData.path),
					cost: assistantData.cost,
					tokens: encodeTokens(assistantData.tokens),
				};
				copyOut(assistantData, out, "error");
				copyOut(assistantData, out, "summary");
				copyOut(assistantData, out, "structured");
				copyOut(assistantData, out, "variant");
				copyOut(assistantData, out, "finish");
				out;
		}
	}

	static function encodePart(part:Part):Dynamic {
		return switch part {
			case SnapshotPart(snapshotData):
				withBase(snapshotData, "snapshot", {snapshot: snapshotData.snapshot});
			case PatchPart(patchData):
				withBase(patchData, "patch", {hash: patchData.hash, files: patchData.files});
			case TextPart(textData):
				final out = withBase(textData, "text", {text: textData.text});
				copyOut(textData, out, "synthetic");
				copyOut(textData, out, "ignored");
				if (textData.time != null)
					Reflect.setField(out, "time", encodeObject(textData.time));
				copyOut(textData, out, "metadata");
				out;
			case ReasoningPart(reasoningData):
				final out = withBase(reasoningData, "reasoning", {text: reasoningData.text, time: encodeObject(reasoningData.time)});
				copyOut(reasoningData, out, "metadata");
				out;
			case FilePart(fileData):
				encodeFilePart(fileData);
			case AgentPart(agentData):
				final out = withBase(agentData, "agent", {name: agentData.name});
				copyOut(agentData, out, "source");
				out;
			case CompactionPart(compactionData):
				final out = withBase(compactionData, "compaction", {auto: compactionData.auto});
				copyOut(compactionData, out, "overflow");
				if (compactionData.tail_start_id != null)
					Reflect.setField(out, "tail_start_id", compactionData.tail_start_id.toString());
				out;
			case SubtaskPart(subtaskData):
				final out = withBase(subtaskData, "subtask", {
					prompt: subtaskData.prompt,
					description: subtaskData.description,
					agent: subtaskData.agent,
				});
				copyOut(subtaskData, out, "model");
				copyOut(subtaskData, out, "command");
				out;
			case RetryPart(retryData):
				withBase(retryData, "retry", {attempt: retryData.attempt, error: retryData.error, time: encodeCreatedTime(retryData.time)});
			case StepStartPart(stepStartData):
				final out = withBase(stepStartData, "step-start", {});
				copyOut(stepStartData, out, "snapshot");
				out;
			case StepFinishPart(stepFinishData):
				final out = withBase(stepFinishData, "step-finish", {
					reason: stepFinishData.reason,
					cost: stepFinishData.cost,
					tokens: encodeTokens(stepFinishData.tokens),
				});
				copyOut(stepFinishData, out, "snapshot");
				out;
			case ToolPart(toolData):
				final out = withBase(toolData, "tool", {
					callID: toolData.callID,
					tool: toolData.tool,
					state: encodeToolState(toolData.state),
				});
				copyOut(toolData, out, "metadata");
				out;
		}
	}

	static function encodeFilePart(data:FilePartData):Dynamic {
		final out = withBase(data, "file", {mime: data.mime, url: data.url});
		copyOut(data, out, "filename");
		if (data.source != null)
			Reflect.setField(out, "source", encodeFileSource(data.source));
		return out;
	}

	static function encodeFileSource(source:FilePartSource):Dynamic {
		return switch source {
			case FileSource(fileSourceData):
				{type: "file", text: encodeObject(fileSourceData.text), path: fileSourceData.path};
			case SymbolSource(symbolSourceData):
				{
					type: "symbol",
					text: encodeObject(symbolSourceData.text),
					path: symbolSourceData.path,
					range: symbolSourceData.range,
					name: symbolSourceData.name,
					kind: symbolSourceData.kind
				};
			case ResourceSource(resourceSourceData):
				{
					type: "resource",
					text: encodeObject(resourceSourceData.text),
					clientName: resourceSourceData.clientName,
					uri: resourceSourceData.uri
				};
		}
	}

	static function encodeToolState(state:ToolState):Dynamic {
		return switch state {
			case ToolPending(pendingData):
				{status: "pending", input: pendingData.input, raw: pendingData.raw};
			case ToolRunning(runningData):
				final out:Dynamic = {status: "running", input: runningData.input, time: encodeObject(runningData.time)};
				copyOut(runningData, out, "title");
				copyOut(runningData, out, "metadata");
				out;
			case ToolCompleted(completedData):
				final out:Dynamic = {
					status: "completed",
					input: completedData.input,
					output: completedData.output,
					title: completedData.title,
					metadata: completedData.metadata,
					time: encodeObject(completedData.time),
				};
				if (completedData.attachments != null) {
					final attachments:Array<FilePartData> = completedData.attachments;
					Reflect.setField(out, "attachments", attachments.map(encodeFilePart));
				}
				out;
			case ToolErrored(errorData):
				final out:Dynamic = {
					status: "error",
					input: errorData.input,
					error: errorData.error,
					time: encodeObject(errorData.time)
				};
				copyOut(errorData, out, "metadata");
				out;
		}
	}

	static function encodeOutputFormat(format:OutputFormat):Dynamic {
		return switch format {
			case OutputText:
				{type: "text"};
			case OutputJsonSchema(schema, retryCount):
				{type: "json_schema", schema: schema, retryCount: retryCount};
		}
	}

	static function withBase(base:Dynamic, type:String, fields:Dynamic):Dynamic {
		final out:Dynamic = {
			id: base.id.toString(),
			sessionID: base.sessionID.toString(),
			messageID: base.messageID.toString(),
			type: type,
		};
		for (field in Reflect.fields(fields)) {
			Reflect.setField(out, field, Reflect.field(fields, field));
		}
		return out;
	}

	static function encodeCreatedTime(time:Dynamic):Dynamic {
		final out:Dynamic = {created: time.created};
		copyOut(time, out, "completed");
		return out;
	}

	static function encodeTokens(tokens:TokenUsage):Dynamic {
		final out:Dynamic = {
			input: tokens.input,
			output: tokens.output,
			reasoning: tokens.reasoning,
			cache: encodeObject(tokens.cache),
		};
		copyOut(tokens, out, "total");
		return out;
	}

	static function encodeObject(value:Dynamic):Dynamic {
		final out:Dynamic = {};
		for (field in Reflect.fields(value)) {
			Reflect.setField(out, field, Reflect.field(value, field));
		}
		return out;
	}

	static function has(data:Dynamic, field:String):Bool {
		return data != null && Reflect.hasField(data, field) && Reflect.field(data, field) != null;
	}

	static function copyOptional(from:Dynamic, to:Dynamic, field:String):Void {
		if (has(from, field))
			Reflect.setField(to, field, Reflect.field(from, field));
	}

	static function copyOptionalMessageJson(from:Dynamic, to:Dynamic, field:String, issues:Array<String>, path:String):Void {
		if (has(from, field))
			Reflect.setField(to, field, decodeMessageJsonValue(Reflect.field(from, field), issues, path));
	}

	static function copyOptionalToolStateMetadata(from:Dynamic, to:Dynamic, field:String, issues:Array<String>, path:String):Void {
		if (has(from, field))
			Reflect.setField(to, field, decodeToolStateMetadataValue(Reflect.field(from, field), issues, path));
	}

	static function copyOut(from:Dynamic, to:Dynamic, field:String):Void {
		if (has(from, field))
			Reflect.setField(to, field, Reflect.field(from, field));
	}

	static function requiredMessageJson(data:Dynamic, field:String, issues:Array<String>, path:String):MessageJson {
		if (!has(data, field)) {
			issues.push(path + ": expected JSON value");
			return MessageJson.emptyObject();
		}
		return decodeMessageJsonValue(Reflect.field(data, field), issues, path);
	}

	static function requiredToolStateMetadata(data:Dynamic, field:String, issues:Array<String>, path:String):ToolStateMetadata {
		if (!has(data, field)) {
			issues.push(path + ": expected JSON value");
			return ToolStateMetadata.empty();
		}
		return decodeToolStateMetadataValue(Reflect.field(data, field), issues, path);
	}

	static function decodeMessageJsonValue(value:Dynamic, issues:Array<String>, path:String):MessageJson {
		final json = JsonCodec.narrow(Unknown.fromBoundary(value));
		if (json == null) {
			issues.push(path + ": expected JSON value");
			return MessageJson.emptyObject();
		}
		return MessageJson.fromJson(json);
	}

	static function decodeToolStateMetadataValue(value:Dynamic, issues:Array<String>, path:String):ToolStateMetadata {
		final json = JsonCodec.narrow(Unknown.fromBoundary(value));
		if (json == null) {
			issues.push(path + ": expected JSON value");
			return ToolStateMetadata.empty();
		}
		return ToolStateMetadata.fromJson(json);
	}

	static function requiredObject(data:Dynamic, field:String, issues:Array<String>, path:String):Dynamic {
		if (!has(data, field)) {
			issues.push(path + ": expected object");
			return {};
		}
		final value = Reflect.field(data, field);
		if (!isObjectRecord(value)) {
			issues.push(path + ": expected object");
			return {};
		}
		return value;
	}

	static function requiredArray(data:Dynamic, field:String, issues:Array<String>, path:String):Array<Dynamic> {
		if (!has(data, field)) {
			issues.push(path + ": expected array");
			return [];
		}
		final value = Reflect.field(data, field);
		if (!Std.isOfType(value, Array)) {
			issues.push(path + ": expected array");
			return [];
		}
		return cast value;
	}

	static function requiredString(data:Dynamic, field:String, issues:Array<String>, path:String):String {
		if (!has(data, field)) {
			issues.push(path + ": expected string");
			return "";
		}
		final value = Reflect.field(data, field);
		if (!Std.isOfType(value, String)) {
			issues.push(path + ": expected string");
			return "";
		}
		return value;
	}

	static function requiredBool(data:Dynamic, field:String, issues:Array<String>, path:String):Bool {
		if (!has(data, field)) {
			issues.push(path + ": expected boolean");
			return false;
		}
		final value = Reflect.field(data, field);
		if (!Std.isOfType(value, Bool)) {
			issues.push(path + ": expected boolean");
			return false;
		}
		return value;
	}

	static function requiredFloat(data:Dynamic, field:String, issues:Array<String>, path:String):Float {
		if (!has(data, field)) {
			issues.push(path + ": expected number");
			return 0;
		}
		final value = Reflect.field(data, field);
		if (!Std.isOfType(value, Float) && !Std.isOfType(value, Int)) {
			issues.push(path + ": expected number");
			return 0;
		}
		return cast value;
	}

	static function requiredInt(data:Dynamic, field:String, issues:Array<String>, path:String):Int {
		final value = requiredFloat(data, field, issues, path);
		final intValue = Std.int(value);
		if (value != intValue)
			issues.push(path + ": expected integer");
		return intValue;
	}

	static function decodeStringArray(items:Array<Dynamic>, issues:Array<String>, path:String):Array<String> {
		final result:Array<String> = [];
		for (index in 0...items.length) {
			final item = items[index];
			if (Std.isOfType(item, String)) {
				result.push(item);
			} else {
				issues.push('${path}[${index}]: expected string');
			}
		}
		return result;
	}

	static function isObjectRecord(value:Dynamic):Bool {
		if (value == null)
			return false;
		if (Std.isOfType(value, Array))
			return false;
		if (Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return false;
		return Reflect.isObject(value);
	}

	static function emptyTextPart():MessageTypes.TextPartData {
		return {
			id: PartID.make(""),
			sessionID: SessionID.make(""),
			messageID: MessageID.make(""),
			type: "text",
			text: "",
		};
	}

	static function invalid(source:String, issues:Array<String>):MessageException {
		return new MessageException(InvalidMessage(source, issues));
	}
}
