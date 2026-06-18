package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionAskRecord;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.storage.SqliteSessionStore;

class SessionProcessorSmoke {
	public static function run():Void {
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
			eq(Reflect.field(result.events[3], "type"), "tool-call-start", "tool start event");
			eq(prompts.length, 1, "permission prompt count");
			eq(prompts[0].permission, "read", "permission name");
			eq(prompts[0].tool.messageID, SessionProcessor.ASSISTANT_ID, "permission message id");
			assertAssistant(result.messages[1].info);
			assertAssistantParts(result.messages[1].parts);
			assertToolOutcome(result.tool);

			final page = store.pageMessages(SessionID.make(SessionProcessor.SESSION_ID), 10);
			eq(page.items.length, 2, "stored message count");
			eq(page.items[1].parts.length, 4, "stored assistant parts");
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			store.close();
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
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

	static function assertAssistantParts(parts:Array<Part>):Void {
		eq(parts.length, 4, "assistant part count");
		switch parts[0] {
			case StepStartPart(_):
			case _:
				throw "session processor: expected step-start part";
		}
		switch parts[1] {
			case ToolPart(tool):
				eq(tool.callID, "call_read_one", "tool call id");
				assertCompleted(tool.state);
			case _:
				throw "session processor: expected tool part";
		}
		switch parts[2] {
			case TextPart(text):
				eq(text.text, "Hello from the fake provider.", "assistant text");
			case _:
				throw "session processor: expected text part";
		}
		switch parts[3] {
			case StepFinishPart(finish):
				eq(finish.reason, "stop", "step finish reason");
			case _:
				throw "session processor: expected step-finish part";
		}
	}

	static function assertCompleted(state:ToolState):Void {
		switch state {
			case ToolCompleted(completed):
				eq(completed.output.indexOf("session processor fixture") != -1, true, "tool output");
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

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
