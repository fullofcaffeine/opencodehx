package opencodehx.smoke;

import haxe.Json;
import opencodehx.session.MessageCodec;
import opencodehx.session.MessageError.MessageException;
import opencodehx.session.MessageError.MessageFailure;
import opencodehx.session.MessageID;
import opencodehx.session.MessageTypes.Info;
import opencodehx.session.MessageTypes.OutputFormat;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.MessageTypes.ToolState;

class MessageSmoke {
	public static function run():Void {
		roundtripUserText();
		roundtripAssistantTool();
		outputFormatDefault();
		cursorRoundtrip();
		rejectUnknownPart();
	}

	static function roundtripUserText():Void {
		final input:Dynamic = {
			info: {
				id: "msg_user",
				sessionID: "ses_fixture",
				role: "user",
				time: {created: 1},
				agent: "user",
				model: {providerID: "test", modelID: "test-model"},
				format: {type: "text"},
				tools: {bash: true},
			},
			parts: [
				{
					id: "prt_text",
					sessionID: "ses_fixture",
					messageID: "msg_user",
					type: "text",
					text: "hello",
					synthetic: true,
				},
			],
		};
		final decoded = MessageCodec.decodeWithParts(input, "user-text");
		assertUserAgent(decoded.info, "user");
		assertTextPart(decoded.parts[0], "hello", true);
		final reparsed = MessageCodec.parseWithParts(MessageCodec.stringifyWithParts(decoded), "user-text-roundtrip");
		eq(partCount(reparsed.parts), 1, "roundtrip part count");
	}

	static function roundtripAssistantTool():Void {
		final input:Dynamic = Json.parse('{
			"info": {
				"id": "msg_assistant",
				"sessionID": "ses_fixture",
				"role": "assistant",
				"time": {"created": 2, "completed": 3},
				"parentID": "msg_user",
				"modelID": "test-model",
				"providerID": "test",
				"mode": "",
				"agent": "agent",
				"path": {"cwd": "/tmp/project", "root": "/tmp/project"},
				"cost": 0.25,
				"tokens": {
					"total": 8,
					"input": 3,
					"output": 4,
					"reasoning": 1,
					"cache": {"read": 0, "write": 0}
				},
				"finish": "stop"
			},
			"parts": [
				{
					"id": "prt_step",
					"sessionID": "ses_fixture",
					"messageID": "msg_assistant",
					"type": "step-start",
					"snapshot": "snap"
				},
				{
					"id": "prt_tool",
					"sessionID": "ses_fixture",
					"messageID": "msg_assistant",
					"type": "tool",
					"callID": "call-1",
					"tool": "bash",
					"metadata": {"providerExecuted": true},
					"state": {
						"status": "completed",
						"input": {"cmd": "ls"},
						"output": "ok",
						"title": "Bash",
						"metadata": {},
						"time": {"start": 2, "end": 3},
						"attachments": [{
							"id": "prt_file",
							"sessionID": "ses_fixture",
							"messageID": "msg_assistant",
							"type": "file",
							"mime": "image/png",
							"filename": "image.png",
							"url": "data:image/png;base64,Zm9v"
						}]
					}
				}
			]
		}');
		final decoded = MessageCodec.decodeWithParts(input, "assistant-tool");
		assertAssistantParent(decoded.info, "msg_user", 8);
		assertToolPart(decoded.parts[1], "call-1", 1);
		final encoded = MessageCodec.encodeWithParts(decoded);
		final encodedDecoded = MessageCodec.decodeWithParts(encoded, "assistant-tool-encoded");
		assertToolPart(encodedDecoded.parts[1], "call-1", 1);
	}

	static function outputFormatDefault():Void {
		final input:Dynamic = {
			info: {
				id: "msg_json",
				sessionID: "ses_fixture",
				role: "user",
				time: {created: 1},
				agent: "user",
				model: {providerID: "test", modelID: "test-model"},
				format: {type: "json_schema", schema: {type: "object"}},
			},
			parts: [],
		};
		final decoded = MessageCodec.decodeWithParts(input, "format-default");
		assertJsonSchemaDefault(decoded.info, 2);
	}

	static function cursorRoundtrip():Void {
		final encoded = MessageCodec.encodeCursor({id: MessageID.make("msg_cursor"), time: 42});
		final decoded = MessageCodec.decodeCursor(encoded);
		eq(decoded.id.toString(), "msg_cursor", "cursor id");
		eq(decoded.time, 42, "cursor time");
	}

	static function rejectUnknownPart():Void {
		final input:Dynamic = Json.parse('{
			"info": {
				"id": "msg_user",
				"sessionID": "ses_fixture",
				"role": "user",
				"time": {"created": 1},
				"agent": "user",
				"model": {"providerID": "test", "modelID": "test-model"}
			},
			"parts": [{
				"id": "prt_unknown",
				"sessionID": "ses_fixture",
				"messageID": "msg_user",
				"type": "unknown"
			}]
		}');
		try {
			MessageCodec.decodeWithParts(input, "unknown-part");
		} catch (error:MessageException) {
			if (hasUnknownPartFailure(error.failure))
				return;
			throw error;
		}
		throw "unknown-part: expected failure";
	}

	static function assertUserAgent(info:Info, expectedAgent:String):Void {
		switch info {
			case UserInfo(userData):
				eq(userData.agent, expectedAgent, "user agent");
			case _:
				throw "user-text: expected user info";
		}
	}

	static function assertTextPart(part:Part, expectedText:String, expectedSynthetic:Bool):Void {
		switch part {
			case TextPart(textData):
				eq(textData.text, expectedText, "text part");
				eq(textData.synthetic, expectedSynthetic, "synthetic flag");
			case _:
				throw "user-text: expected text part";
		}
	}

	static function assertAssistantParent(info:Info, expectedParent:String, expectedTotal:Float):Void {
		switch info {
			case AssistantInfo(assistantData):
				eq(assistantData.parentID.toString(), expectedParent, "assistant parent");
				eq(assistantData.tokens.total, expectedTotal, "assistant token total");
			case _:
				throw "assistant-tool: expected assistant info";
		}
	}

	static function assertToolPart(part:Part, expectedCallID:String, expectedAttachmentCount:Int):Void {
		switch part {
			case ToolPart(toolData):
				eq(toolData.callID, expectedCallID, "tool call id");
				assertCompletedState(toolData.state, expectedAttachmentCount);
			case _:
				throw "assistant-tool: expected tool part";
		}
	}

	static function assertCompletedState(state:ToolState, expectedAttachmentCount:Int):Void {
		switch state {
			case ToolCompleted(completedState):
				eq(completedState.attachments.length, expectedAttachmentCount, "tool attachment count");
			case _:
				throw "assistant-tool: expected completed tool state";
		}
	}

	static function assertJsonSchemaDefault(info:Info, expectedRetry:Int):Void {
		switch info {
			case UserInfo(userData):
				assertOutputFormat(userData.format, expectedRetry);
			case _:
				throw "format-default: expected user";
		}
	}

	static function assertOutputFormat(format:OutputFormat, expectedRetry:Int):Void {
		switch format {
			case OutputJsonSchema(_, retryCount):
				eq(retryCount, expectedRetry, "json schema retry default");
			case _:
				throw "format-default: expected json schema";
		}
	}

	static function hasUnknownPartFailure(failure:MessageFailure):Bool {
		return switch failure {
			case InvalidMessage(_, issues):
				issues.join("\n").indexOf("unknown part type") != -1;
		}
	}

	static function partCount(parts:Array<Part>):Int {
		return parts.length;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
