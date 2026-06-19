package opencodehx.server;

import js.lib.Error;
import js.lib.Promise;
import opencodehx.externs.hono.Hono;
import opencodehx.externs.hono.NodeServer;
import opencodehx.externs.hono.NodeServer.NodeServerAddress;
import opencodehx.externs.hono.NodeServer.NodeServerType;
import opencodehx.externs.hono.NodeWs.NodeWebSocketRuntime;
import opencodehx.server.ServerTypes.ServerListener;

class NodeHonoAdapter {
	public static function listen(app:Hono, ws:NodeWebSocketRuntime, hostname:String, port:Int):Promise<ServerListener> {
		return new Promise<ServerListener>((resolve, reject) -> {
			function createServer(injectWebSocket:Bool):NodeServerType {
				final server = NodeServer.createAdaptorServer({fetch: app.fetch});
				if (injectWebSocket)
					ws.injectWebSocket(server);
				return server;
			}

			function start(nextPort:Int):Void {
				final server = createServer(true);
				var closing:Null<Promise<Void>> = null;
				var fail:Error->Void = null;
				var ready:Void->Void = null;
				function cleanup():Void {
					server.off("error", fail);
					server.off("listening", ready);
				}
				fail = error -> {
					cleanup();
					reject(error);
				};
				ready = () -> {
					cleanup();
					final address = server.address();
					if (address == null || Std.isOfType(address, String)) {
						reject(new Error("Failed to resolve server address"));
						return;
					}
					// The only remaining union member is the TCP address shape
					// because this adapter calls listen(port, hostname), not
					// listen(path). Keep the cast after the runtime guard.
					final tcpAddress:NodeServerAddress = cast address;
					final listener:ServerListener = {
						port: tcpAddress.port,
						hostname: hostname,
						url: 'http://${hostname}:${tcpAddress.port}',
						stop: (?close:Bool) -> {
							if (closing == null)
								closing = stopServer(server, close == true);
							return closing;
						}
					};
					resolve(listener);
				};
				server.once("error", fail);
				server.once("listening", ready);
				server.listen(nextPort, hostname);
			}

			if (port == 0)
				probePreferredPort(app, hostname, start);
			else
				start(port);
		});
	}

	static function probePreferredPort(app:Hono, hostname:String, start:Int->Void):Void {
		final probe = NodeServer.createAdaptorServer({fetch: app.fetch});
		probe.once("error", (_:Error) -> start(0));
		probe.once("listening", () -> {
			probe.close(_ -> start(4096));
		});
		probe.listen(4096, hostname);
	}

	static function stopServer(server:NodeServerType, close:Bool):Promise<Void> {
		return new Promise<Void>((resolve, reject) -> {
			// Haxe cannot call a `Promise<Void>` resolver because `Void` has no
			// value. Cast only the resolver to a zero-arg function and keep the
			// server lifecycle itself typed through the NodeServer extern.
			final resolveVoid:Void->Void = cast resolve;
			server.close(error -> {
				if (error != null)
					reject(error);
				else
					resolveVoid();
			});
			if (close) {
				final closeAllConnections = server.closeAllConnections;
				if (closeAllConnections != null)
					closeAllConnections();
				final closeIdleConnections = server.closeIdleConnections;
				if (closeIdleConnections != null)
					closeIdleConnections();
			}
		});
	}
}
