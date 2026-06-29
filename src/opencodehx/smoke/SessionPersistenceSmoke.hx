package opencodehx.smoke;

import genes.ts.Undefinable;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.session.SessionExport;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.storage.SqliteSessionStore;

class SessionPersistenceSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-session-persist-"));
		final store = new SqliteSessionStore(NodePath.join(root, "opencodehx.db"));
		try {
			SessionProcessor.run({
				prompt: "Export me",
				directory: root,
				sessionID: "ses_export",
				projectID: "proj_export",
				store: store,
			});
			final sessionID = SessionID.make("ses_export");
			final exported = SessionExport.exportData(store, sessionID);
			eq(exported.info.id, "ses_export", "session export info id");
			eq(exported.messages.length, 2, "session export message count");
			eq(exported.messages[0].info.role, "user", "session export first role");
			eq(present(exported.messages[0].parts[0].text, "session export raw text"), "Export me", "session export raw text");

			final sanitized = SessionExport.exportData(store, sessionID, true);
			eq(sanitized.info.title, "[redacted:session-title:ses_export]", "session export sanitized title");
			eq(present(sanitized.messages[0].parts[0].text, "session export sanitized text"), "[redacted:text:prt_user_text_ses_export]",
				"session export sanitized text");

			Fs.mkdirSync(NodePath.join(root, "src"), {recursive: true});
			Fs.writeFileSync(NodePath.join(root, "src/input.txt"), "exported tool fixture\n");
			SessionProcessor.run({
				prompt: "Export a tool turn",
				directory: root,
				sessionID: "ses_export_tool",
				projectID: "proj_export",
				store: store,
				toolCall: {
					id: "call_read_export",
					tool: "read",
					input: {filePath: "src/input.txt"},
				},
			});
			final toolExport = SessionExport.exportData(store, SessionID.make("ses_export_tool"));
			eq(toolExport.messages.length, 2, "session export tool message count");
			final toolParts = toolExport.messages[1].parts;
			eq(toolParts[0].type, "step-start", "session export tool step start");
			eq(toolParts[1].type, "tool", "session export tool part");
			eq(present(toolParts[1].callID, "session export tool call id"), "call_read_export", "session export tool call id");
			final toolState = present(toolParts[1].state, "session export tool state");
			eq(unknownStringField(toolState.input, "filePath", "session export tool input"), "src/input.txt", "session export tool input");
			eq(present(toolState.output, "session export tool output").indexOf("exported tool fixture") != -1, true, "session export tool output");
			eq(present(toolState.title, "session export tool title"), "src/input.txt", "session export tool title");
			eq(toolParts[2].type, "text", "session export tool text part");
			eq(present(toolParts[2].text, "session export tool assistant text"), "Hello from the fake provider.", "session export tool assistant text");
			eq(toolParts[3].type, "step-finish", "session export tool step finish");
			final sanitizedTool = SessionExport.exportData(store, SessionID.make("ses_export_tool"), true);
			final sanitizedToolParts = sanitizedTool.messages[1].parts;
			eq(present(sanitizedToolParts[1].callID, "session export sanitized tool call id"), "call_read_export", "session export sanitized tool call id");
			final sanitizedToolState = present(sanitizedToolParts[1].state, "session export sanitized tool state");
			eq(unknownString(sanitizedToolState.input, "session export sanitized tool input"),
				"[redacted:tool-input:prt_tool_call_call_read_export_ses_export_tool]", "session export sanitized tool input");
			eq(present(sanitizedToolState.output, "session export sanitized tool output"),
				"[redacted:tool-output:prt_tool_call_call_read_export_ses_export_tool]", "session export sanitized tool output");
			eq(present(sanitizedToolState.title, "session export sanitized tool title"),
				"[redacted:tool-title:prt_tool_call_call_read_export_ses_export_tool]", "session export sanitized tool title");
			eq(present(sanitizedToolParts[2].text, "session export sanitized tool text"), "[redacted:text:prt_assistant_text_ses_export_tool]",
				"session export sanitized tool text");

			SessionProcessor.run({
				prompt: "Export a failed tool turn",
				directory: root,
				sessionID: "ses_export_tool_error",
				projectID: "proj_export",
				store: store,
				toolCall: {
					id: "call_read_missing_export",
					tool: "read",
					input: {filePath: "src/missing.txt"},
				},
			});
			final failedToolExport = SessionExport.exportData(store, SessionID.make("ses_export_tool_error"));
			final failedToolParts = failedToolExport.messages[1].parts;
			final failedToolState = present(failedToolParts[1].state, "session export failed tool state");
			eq(failedToolState.status, "error", "session export failed tool status");
			eq(unknownStringField(failedToolState.input, "filePath", "session export failed tool input"), "src/missing.txt",
				"session export failed tool input");
			eq(present(failedToolState.error, "session export failed tool error").indexOf("File not found") != -1, true, "session export failed tool error");
			final sanitizedFailedTool = SessionExport.exportData(store, SessionID.make("ses_export_tool_error"), true);
			final sanitizedFailedToolParts = sanitizedFailedTool.messages[1].parts;
			eq(present(sanitizedFailedToolParts[1].callID, "session export sanitized failed call id"), "call_read_missing_export",
				"session export sanitized failed call id");
			final sanitizedFailedToolState = present(sanitizedFailedToolParts[1].state, "session export sanitized failed tool state");
			eq(sanitizedFailedToolState.status, "error", "session export sanitized failed tool status");
			eq(unknownString(sanitizedFailedToolState.input, "session export sanitized failed tool input"),
				"[redacted:tool-input:prt_tool_call_call_read_missing_export_ses_export_tool_error]", "session export sanitized failed tool input");
			eq(present(sanitizedFailedToolState.error, "session export sanitized failed tool error"),
				"[redacted:tool-error:prt_tool_call_call_read_missing_export_ses_export_tool_error]", "session export sanitized failed tool error");

			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}

	static function present<T>(value:Undefinable<T>, label:String):T {
		final out = value.orNull();
		if (out == null)
			throw '${label}: expected present value';
		return out;
	}

	static function unknownString(value:Unknown, label:String):String {
		final text = UnknownNarrow.string(value);
		if (text == null)
			throw '${label}: expected string';
		return text;
	}

	static function unknownStringField(value:Unknown, field:String, label:String):String {
		final record = UnknownNarrow.record(value);
		if (record == null)
			throw '${label}: expected object';
		return unknownString(record.get(field), label);
	}
}
