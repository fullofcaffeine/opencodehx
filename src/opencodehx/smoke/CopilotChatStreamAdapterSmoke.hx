package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import js.html.Response;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.provider.copilot.CopilotChatStream.CopilotChatStreamEventType;
import opencodehx.provider.copilot.CopilotChatStreamAdapter;

class CopilotChatStreamAdapterSmoke {
	@:async
	public static function run():Promise<Void> {
		final response = streamResponse([
			'data: {"id":"chatcmpl-123","created":1677652288,"model":"gemini-2.0-flash-001","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}\n\n',
			'data: {"choices":[{"delta":{"content":" world"},"finish_reason":"stop"}]}\n\n',
			"data: [DONE]\n\n",
		]);
		final events = @:await CopilotChatStreamAdapter.responseEvents(response, true, ["fixture-warning"]);
		eq(events[0].type, CopilotChatStreamEventType.StreamStart, "stream start");
		eq(present(events[0].warnings.orNull(), "warnings")[0], "fixture-warning", "stream warning");
		eq(events[1].type, CopilotChatStreamEventType.Raw, "first raw");
		eq(events[2].type, CopilotChatStreamEventType.ResponseMetadata, "metadata");
		eq(events[3].type, CopilotChatStreamEventType.TextStart, "text start");
		eq(events[4].delta.orNull(), "Hello", "first text");
		eq(events[6].delta.orNull(), " world", "second text");
		return null;
	}

	static function streamResponse(chunks:Array<String>):Response {
		final stream = new WebReadableStream<Uint8Array>({
			start: controller -> enqueueChunks(controller, chunks),
		});
		final headers = new DynamicAccess<String>();
		headers.set("content-type", "text/event-stream");
		return new Response(stream, {
			headers: headers,
		});
	}

	static function enqueueChunks(controller:WebReadableStreamDefaultController<Uint8Array>, chunks:Array<String>):Void {
		final encoder = new WebTextEncoder();
		for (chunk in chunks)
			controller.enqueue(encoder.encode(chunk));
		controller.close();
	}

	static function present<T>(value:Null<T>, label:String):T {
		if (value == null)
			throw '${label}: expected value';
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
