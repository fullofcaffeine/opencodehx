package opencodehx.server;

import js.Syntax;
import js.html.Response;
import opencodehx.server.ServerEventBus.ServerEventListener;
import opencodehx.server.ServerEventBus.ServerEventSubscribe;
import opencodehx.server.ServerProtocol.ServerEvent;

class ServerEventStream {
	public static function response(history:Array<ServerEvent>, subscribe:ServerEventSubscribe):Response {
		final connected = ServerProtocol.connectedEvent();
		final heartbeat = ServerProtocol.heartbeatEvent();
		// Justified raw TS boundary: Web `ReadableStream` controller and timer
		// lifecycle types differ between DOM and Node libs, and the current
		// narrow externs do not model streaming SSE construction. Keep the raw
		// code isolated here; callers pass typed events and a typed unsubscribe
		// function, and the returned surface is a normal `Response`.
		return
			Syntax.code("((history: Array<ServerEvent>, subscribe: (listener: (event: ServerEvent) => void) => () => void, connected: ServerEvent, heartbeat: ServerEvent): Response => {
			const encoder = new TextEncoder();
			let unsubscribe: (() => void) | null = null;
			let interval: ReturnType<typeof setInterval> | null = null;
			const stream = new ReadableStream<Uint8Array>({
				start(controller) {
					let closed = false;
					const write = (event: ServerEvent) => {
						if (closed) return;
						controller.enqueue(encoder.encode('data: ' + JSON.stringify(event) + '\\n\\n'));
					};
					const stop = () => {
						if (closed) return;
						closed = true;
						if (interval !== null) clearInterval(interval);
						if (unsubscribe !== null) unsubscribe();
						interval = null;
						unsubscribe = null;
					};
					write(connected);
					for (const event of history) write(event);
					write(heartbeat);
					interval = setInterval(() => write(heartbeat), 10000);
					unsubscribe = subscribe(write);
				},
				cancel() {
					if (interval !== null) clearInterval(interval);
					if (unsubscribe !== null) unsubscribe();
					interval = null;
					unsubscribe = null;
				},
			});
			return new Response(stream, { headers: { 'content-type': 'text/event-stream' } });
		})({0}, {1}, {2}, {3})", history, subscribe, connected, heartbeat);
	}
}
