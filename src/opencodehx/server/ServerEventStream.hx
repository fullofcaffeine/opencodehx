package opencodehx.server;

import haxe.DynamicAccess;
import haxe.Json;
import js.html.Response;
import js.lib.Uint8Array;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebReadableStreamDefaultController;
import opencodehx.externs.web.WebStreams.WebTextEncoder;
import opencodehx.externs.web.WebStreams.WebTimerHandle;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.server.ServerEventBus.ServerEventSubscribe;
import opencodehx.server.ServerProtocol.ServerEvent;

class ServerEventStream {
	public static function response(history:Array<ServerEvent>, subscribe:ServerEventSubscribe):Response {
		final connected = ServerProtocol.connectedEvent();
		final heartbeat = ServerProtocol.heartbeatEvent();
		final encoder = new WebTextEncoder();
		var unsubscribe:Null<Void->Void> = null;
		var interval:Null<WebTimerHandle> = null;
		var closed = false;

		function stop():Void {
			if (closed)
				return;
			closed = true;
			if (interval != null)
				WebTimers.clearInterval(interval);
			if (unsubscribe != null)
				unsubscribe();
			interval = null;
			unsubscribe = null;
		}

		function write(controller:WebReadableStreamDefaultController<Uint8Array>, event:ServerEvent):Void {
			if (closed)
				return;
			controller.enqueue(encoder.encode('data: ${Json.stringify(event)}\n\n'));
		}

		final stream = new WebReadableStream<Uint8Array>({
			start: controller -> {
				write(controller, connected);
				for (event in history)
					write(controller, event);
				write(controller, heartbeat);
				interval = WebTimers.setInterval(() -> write(controller, heartbeat), 10000);
				unsubscribe = subscribe(event -> write(controller, event));
			},
			cancel: _ -> stop(),
		});
		final headers = new DynamicAccess<String>();
		headers.set("content-type", "text/event-stream");
		// Haxe's DOM Response extern does not accept ReadableStream bodies even
		// though Node/modern browsers do. The cast is localized to the standard
		// SSE response boundary and genes-ts emits a checked `new Response(stream)`.
		return new Response(cast stream, {headers: headers});
	}
}
