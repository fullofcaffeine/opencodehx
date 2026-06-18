package opencodehx.harness;

import haxe.Json;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.FakeProvider.FakeProviderEvent;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageID;
import opencodehx.session.MessageTypes.AssistantMessage;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.TextPartData;
import opencodehx.session.MessageTypes.TokenUsage;
import opencodehx.session.MessageTypes.UserMessage;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.PartID;
import opencodehx.session.SessionID;

typedef TranscriptTurn = {
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
	final events:Array<Dynamic>;
	final messages:Array<Dynamic>;
}

class TranscriptHarness {
	static inline final SESSION_ID = "ses_fake_one";
	static inline final USER_ID = "msg_user_one";
	static inline final ASSISTANT_ID = "msg_assistant_one";
	static inline final USER_PART_ID = "prt_user_text";
	static inline final ASSISTANT_PART_ID = "prt_assistant_text";
	static inline final CREATED_USER = 1000.0;
	static inline final CREATED_ASSISTANT = 1001.0;
	static inline final COMPLETED_ASSISTANT = 1002.0;

	public static function oneTurnJson():String {
		return Json.stringify(oneTurn(), null, "  ");
	}

	public static function oneTurn():TranscriptTurn {
		final prompt = "Say hello from the fixture.";
		final provider = new FakeProvider();
		final events = encodeEvents(provider.stream(prompt));
		final assistantText = collectText(events);
		final userMessage = userWithParts(prompt, provider);
		final assistantMessage = assistantWithParts(assistantText, provider);
		return {
			provider: {
				id: provider.info.id,
				modelID: provider.model.id,
				source: provider.info.source,
			},
			request: {
				sessionID: SESSION_ID,
				prompt: prompt,
				system: ["You are a deterministic fixture provider."],
				tools: ["read", "write", "edit", "apply_patch"],
			},
			events: events,
			messages: [
				MessageCodec.encodeWithParts(userMessage),
				MessageCodec.encodeWithParts(assistantMessage),
			],
		};
	}

	static function userWithParts(prompt:String, provider:FakeProvider):WithParts {
		final sessionID = SessionID.make(SESSION_ID);
		final messageID = MessageID.make(USER_ID);
		final info:UserMessage = {
			id: messageID,
			sessionID: sessionID,
			role: "user",
			time: {created: CREATED_USER},
			agent: "fixture",
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
			id: PartID.make(USER_PART_ID),
			sessionID: sessionID,
			messageID: messageID,
			type: "text",
			text: prompt,
			time: {start: CREATED_USER, end: CREATED_USER},
		};
		return {info: UserInfo(info), parts: [TextPart(text)]};
	}

	static function assistantWithParts(text:String, provider:FakeProvider):WithParts {
		final sessionID = SessionID.make(SESSION_ID);
		final messageID = MessageID.make(ASSISTANT_ID);
		final tokens:TokenUsage = {
			total: 12,
			input: 7,
			output: 5,
			reasoning: 0,
			cache: {read: 0, write: 0},
		};
		final info:AssistantMessage = {
			id: messageID,
			sessionID: sessionID,
			role: "assistant",
			time: {created: CREATED_ASSISTANT, completed: COMPLETED_ASSISTANT},
			parentID: MessageID.make(USER_ID),
			modelID: provider.model.id,
			providerID: provider.info.id,
			mode: "primary",
			agent: "fixture",
			path: {cwd: "/workspace/opencodehx-fixture", root: "/workspace/opencodehx-fixture"},
			cost: 0,
			tokens: tokens,
			finish: "stop",
		};
		final part:TextPartData = {
			id: PartID.make(ASSISTANT_PART_ID),
			sessionID: sessionID,
			messageID: messageID,
			type: "text",
			text: text,
			time: {start: CREATED_ASSISTANT, end: COMPLETED_ASSISTANT},
		};
		return {info: AssistantInfo(info), parts: [TextPart(part)]};
	}

	static function encodeEvents(events:Array<FakeProviderEvent>):Array<Dynamic> {
		final encoded:Array<Dynamic> = [];
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

	static function collectText(events:Array<Dynamic>):String {
		final parts:Array<String> = [];
		for (event in events) {
			if (Reflect.field(event, "type") == "text-delta")
				parts.push(Std.string(Reflect.field(event, "text")));
		}
		return parts.join("");
	}
}
