package opencodehx.session;

import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.SessionInfo.SessionInfo;
import opencodehx.storage.SessionStore;

typedef SessionExportData = {
	// Export data is a JSON serialization boundary. Messages are encoded into
	// upstream-shaped anonymous records before CLI/server code stringifies them.
	final info:Dynamic;
	final messages:Array<Dynamic>;
}

class SessionExport {
	static inline final DEFAULT_EXPORT_LIMIT = 100000;

	public static function exportData(store:SessionStore, sessionID:SessionID, sanitize:Bool = false):SessionExportData {
		final info = store.getSession(sessionID);
		final page = store.pageMessages(sessionID, DEFAULT_EXPORT_LIMIT);
		final messages:Array<Dynamic> = [];
		for (message in page.items) {
			messages.push(sanitize ? sanitizedMessage(message) : MessageCodec.encodeWithParts(message));
		}
		return {
			info: sanitize ? sanitizedInfo(info) : info,
			messages: messages,
		};
	}

	static function sanitizedInfo(info:SessionInfo):Dynamic {
		// This mirrors upstream object-spread export sanitization at the JSON
		// boundary while keeping the stored SessionInfo model typed internally.
		final out:Dynamic = {
			id: info.id.toString(),
			slug: info.slug,
			projectID: info.projectID,
			workspaceID: info.workspaceID,
			parentID: info.parentID == null ? null : info.parentID.toString(),
			directory: redact("session-directory", info.id.toString(), info.directory),
			title: redact("session-title", info.id.toString(), info.title),
			version: info.version,
			time: info.time,
		};
		if (info.summary != null)
			Reflect.setField(out, "summary", info.summary);
		if (info.share != null)
			Reflect.setField(out, "share", info.share);
		if (info.revert != null)
			Reflect.setField(out, "revert", info.revert);
		if (info.permission != null)
			Reflect.setField(out, "permission", info.permission);
		return out;
	}

	static function sanitizedMessage(message:WithParts):Dynamic {
		final encoded = MessageCodec.encodeWithParts(message);
		final parts:Array<Dynamic> = [];
		for (part in message.parts) {
			parts.push(sanitizedPart(part));
		}
		Reflect.setField(encoded, "parts", parts);
		return encoded;
	}

	static function sanitizedPart(part:Part):Dynamic {
		// MessageCodec owns the typed Part -> JSON-record conversion; this
		// function mutates only selected exported fields for redaction.
		final encoded = MessageCodec.encodePartRecord(part);
		switch part {
			case TextPart(data):
				Reflect.setField(encoded, "text", redact("text", data.id.toString(), data.text));
			case ReasoningPart(data):
				Reflect.setField(encoded, "text", redact("reasoning", data.id.toString(), data.text));
			case FilePart(data):
				Reflect.setField(encoded, "url", redact("file-url", data.id.toString(), data.url));
				if (data.filename != null)
					Reflect.setField(encoded, "filename", redact("file-name", data.id.toString(), data.filename));
			case SubtaskPart(data):
				Reflect.setField(encoded, "prompt", redact("subtask-prompt", data.id.toString(), data.prompt));
				Reflect.setField(encoded, "description", redact("subtask-description", data.id.toString(), data.description));
			case PatchPart(data):
				Reflect.setField(encoded, "hash", redact("patch", data.id.toString(), data.hash));
			case SnapshotPart(data):
				Reflect.setField(encoded, "snapshot", redact("snapshot", data.id.toString(), data.snapshot));
			case ToolPart(data):
				final state = Reflect.field(encoded, "state");
				switch data.state {
					case ToolPending(pending):
						Reflect.setField(state, "raw", redact("tool-raw", data.id.toString(), pending.raw));
					case ToolRunning(running):
						if (running.title != null) Reflect.setField(state, "title", redact("tool-title", data.id.toString(), running.title));
					case ToolCompleted(completed):
						Reflect.setField(state, "output", redact("tool-output", data.id.toString(), completed.output));
						Reflect.setField(state, "title", redact("tool-title", data.id.toString(), completed.title));
					case ToolErrored(errored):
						Reflect.setField(state, "error", redact("tool-error", data.id.toString(), errored.error));
				}
			case _:
		}
		return encoded;
	}

	static function redact(kind:String, id:String, value:String):String {
		return StringTools.trim(value) == "" ? value : '[redacted:${kind}:${id}]';
	}
}
