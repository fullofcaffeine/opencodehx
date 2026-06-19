package opencodehx.smoke;

import opencodehx.config.ConfigInfo;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionAskRecord;
import opencodehx.provider.FakeProvider;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.ToolState;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.session.SessionRetry.SessionProviderError;
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
			final recovered = SessionProcessor.recover(store, SessionProcessor.SESSION_ID, 10);
			eq(recovered.session.directory, root, "recovered session directory");
			eq(recovered.messages.length, 2, "recovered message count");
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
		assertRetryPart(result.messages[1].parts, "runtime retry part");

		final recovered = SessionProcessor.recover(store, "ses_retry_overflow", 10);
		eq(recovered.session.id.toString(), "ses_retry_overflow", "recovered retry session id");
		eq(recovered.messages.length, 2, "recovered retry messages");
		assertCompactionPart(recovered.messages[0].parts, "recovered compaction part");
		assertRetryPart(recovered.messages[1].parts, "recovered retry part");
	}

	static function abortFlow(root:String):Void {
		final result = SessionProcessor.run({
			sessionID: "ses_abort",
			prompt: "Abort me.",
			directory: root,
			aborted: true,
		});
		eq(result.aborted == true, true, "abort result flag");
		eq(Reflect.field(result.events[1], "type"), "abort", "abort event");
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

	static function assertRetryPart(parts:Array<Part>, label:String):Void {
		for (part in parts) {
			switch part {
				case RetryPart(retry):
					eq(retry.attempt, 2.0, label + " attempt");
					eq(Reflect.field(retry.error, "name"), "APIError", label + " error");
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
}
