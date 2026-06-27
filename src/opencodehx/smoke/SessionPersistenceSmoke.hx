package opencodehx.smoke;

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
			eq(Reflect.field(exported.info, "id").toString(), "ses_export", "session export info id");
			eq(exported.messages.length, 2, "session export message count");
			eq(Reflect.field(Reflect.field(cast exported.messages[0], "info"), "role"), "user", "session export first role");
			final rawPart = cast(Reflect.field(cast exported.messages[0], "parts"), Array<Dynamic>)[0];
			eq(Reflect.field(rawPart, "text"), "Export me", "session export raw text");

			final sanitized = SessionExport.exportData(store, sessionID, true);
			eq(Reflect.field(sanitized.info, "title"), "[redacted:session-title:ses_export]", "session export sanitized title");
			final sanitizedPart = cast(Reflect.field(cast sanitized.messages[0], "parts"), Array<Dynamic>)[0];
			eq(Reflect.field(sanitizedPart, "text"), "[redacted:text:prt_user_text_ses_export]", "session export sanitized text");

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
			final toolParts = cast(Reflect.field(cast toolExport.messages[1], "parts"), Array<Dynamic>);
			eq(Reflect.field(toolParts[0], "type"), "step-start", "session export tool step start");
			eq(Reflect.field(toolParts[1], "type"), "tool", "session export tool part");
			eq(Reflect.field(toolParts[1], "callID"), "call_read_export", "session export tool call id");
			final toolState = Reflect.field(toolParts[1], "state");
			eq(Std.string(Reflect.field(toolState, "output")).indexOf("exported tool fixture") != -1, true, "session export tool output");
			eq(Reflect.field(toolState, "title"), "src/input.txt", "session export tool title");
			eq(Reflect.field(toolParts[2], "type"), "text", "session export tool text part");
			eq(Reflect.field(toolParts[2], "text"), "Hello from the fake provider.", "session export tool assistant text");
			eq(Reflect.field(toolParts[3], "type"), "step-finish", "session export tool step finish");
			final sanitizedTool = SessionExport.exportData(store, SessionID.make("ses_export_tool"), true);
			final sanitizedToolParts = cast(Reflect.field(cast sanitizedTool.messages[1], "parts"), Array<Dynamic>);
			eq(Reflect.field(sanitizedToolParts[1], "callID"), "call_read_export", "session export sanitized tool call id");
			final sanitizedToolState = Reflect.field(sanitizedToolParts[1], "state");
			eq(Reflect.field(sanitizedToolState, "output"), "[redacted:tool-output:prt_tool_call_call_read_export_ses_export_tool]",
				"session export sanitized tool output");
			eq(Reflect.field(sanitizedToolState, "title"), "[redacted:tool-title:prt_tool_call_call_read_export_ses_export_tool]",
				"session export sanitized tool title");
			eq(Reflect.field(sanitizedToolParts[2], "text"), "[redacted:text:prt_assistant_text_ses_export_tool]", "session export sanitized tool text");

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
			final failedToolParts = cast(Reflect.field(cast failedToolExport.messages[1], "parts"), Array<Dynamic>);
			final failedToolState = Reflect.field(failedToolParts[1], "state");
			eq(Reflect.field(failedToolState, "status"), "error", "session export failed tool status");
			eq(Std.string(Reflect.field(failedToolState, "error")).indexOf("File not found") != -1, true, "session export failed tool error");
			final sanitizedFailedTool = SessionExport.exportData(store, SessionID.make("ses_export_tool_error"), true);
			final sanitizedFailedToolParts = cast(Reflect.field(cast sanitizedFailedTool.messages[1], "parts"), Array<Dynamic>);
			eq(Reflect.field(sanitizedFailedToolParts[1], "callID"), "call_read_missing_export", "session export sanitized failed call id");
			final sanitizedFailedToolState = Reflect.field(sanitizedFailedToolParts[1], "state");
			eq(Reflect.field(sanitizedFailedToolState, "status"), "error", "session export sanitized failed tool status");
			eq(Reflect.field(sanitizedFailedToolState, "error"), "[redacted:tool-error:prt_tool_call_call_read_missing_export_ses_export_tool_error]",
				"session export sanitized failed tool error");

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
}
