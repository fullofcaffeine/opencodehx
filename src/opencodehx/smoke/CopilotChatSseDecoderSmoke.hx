package opencodehx.smoke;

import opencodehx.provider.copilot.CopilotChatSseDecoder;
import opencodehx.provider.copilot.CopilotChatStream;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEventType;

class CopilotChatSseDecoderSmoke {
	public static function run():Void {
		decodesTextFrames();
		decodesErrorFrames();
		rejectsInvalidJson();
		rejectsInvalidShape();
	}

	static function decodesTextFrames():Void {
		final first = '{"id":"chatcmpl-123","created":1677652288,"model":"gemini-2.0-flash-001","choices":[{"delta":{"content":"Hello"},"finish_reason":null}],"usage":{"prompt_tokens":3,"completion_tokens":1,"total_tokens":4,"prompt_tokens_details":{"cached_tokens":1},"completion_tokens_details":{"reasoning_tokens":0}}}';
		final second = '{"choices":[{"delta":{"content":" world"},"finish_reason":"stop"}]}';
		final raw = 'event: ignored\n' + ': keepalive\n' + 'data: ${first}\n\n' + 'data: ${second}\n\n' + 'data: [DONE]\n\n';

		final chunks = CopilotChatSseDecoder.decodeText(raw);
		eq(chunks.length, 2, "decoded chunk count");
		eq(chunks[0].rawValue.indexOf("chatcmpl-123") != -1, true, "raw value preserved");
		eq(chunks[0].chunk.id, "chatcmpl-123", "chunk id");
		eq(chunks[0].chunk.created, 1677652288.0, "chunk created");
		eq(chunks[0].chunk.model, "gemini-2.0-flash-001", "chunk model");
		eq(chunks[0].chunk.usage.prompt_tokens, 3.0, "chunk usage prompt");
		eq(chunks[0].chunk.usage.prompt_tokens_details.cached_tokens, 1.0, "chunk cached tokens");

		final events = CopilotChatStream.collectRaw(chunks, true);
		eq(events[0].type, CopilotChatStreamEventType.StreamStart, "stream start");
		eq(events[1].type, CopilotChatStreamEventType.Raw, "first raw event");
		eq(events[2].type, CopilotChatStreamEventType.ResponseMetadata, "metadata event");
		eq(events[3].type, CopilotChatStreamEventType.TextStart, "text start");
		eq(events[4].type, CopilotChatStreamEventType.TextDelta, "first text delta");
		eq(events[4].delta.orNull(), "Hello", "first text");
		eq(events[5].type, CopilotChatStreamEventType.Raw, "second raw event");
		eq(events[6].type, CopilotChatStreamEventType.TextDelta, "second text delta");
		eq(events[6].delta.orNull(), " world", "second text");
	}

	static function decodesErrorFrames():Void {
		final chunks = CopilotChatSseDecoder.decodeText('data: {"error":{"message":"provider exploded"}}\n\n');
		eq(chunks.length, 1, "error chunk count");
		eq(chunks[0].chunk.error.message, "provider exploded", "error message");
		final events = CopilotChatStream.collectRaw(chunks, false);
		eq(events[1].type, CopilotChatStreamEventType.Error, "error event");
		eq(events[1].error.orNull(), "provider exploded", "error event message");
	}

	static function rejectsInvalidJson():Void {
		expectInvalid(() -> CopilotChatSseDecoder.decodeText("data: {nope}\n\n"), "invalid json", "Invalid SSE JSON chunk");
	}

	static function rejectsInvalidShape():Void {
		expectInvalid(() -> CopilotChatSseDecoder.decodeText('data: {"choices":{"delta":{}}}\n\n'), "invalid choices", "Expected 'choices' to be an array.");
		expectInvalid(() -> CopilotChatSseDecoder.decodeText('data: {"choices":[{"delta":{"tool_calls":[{"index":0.5}]}}]}\n\n'), "invalid tool index",
			"Expected tool_calls.index to be an integer.");
	}

	static function expectInvalid(run:Void->Void, label:String, contains:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(contains) == -1)
				throw '${label}: expected ${error.message} to contain ${contains}';
			return;
		}
		throw 'Expected invalid SSE chunk for ${label}';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
