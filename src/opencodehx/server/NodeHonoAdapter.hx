package opencodehx.server;

import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.hono.Hono;
import opencodehx.externs.hono.NodeServer;
import opencodehx.externs.hono.NodeWs.NodeWebSocketRuntime;
import opencodehx.server.ServerTypes.ServerListener;

class NodeHonoAdapter {
	public static function listen(app:Hono, ws:NodeWebSocketRuntime, hostname:String, port:Int):Promise<ServerListener> {
		return Syntax.code("new Promise((resolve, reject) => {
			const start = (nextPort: number) => {
				const server = {0}({ fetch: {1}.fetch });
				{2}.injectWebSocket(server);
				const cleanup = () => {
					server.off('error', fail);
					server.off('listening', ready);
				};
				const fail = (error: Error) => {
					cleanup();
					reject(error);
				};
				const ready = () => {
					cleanup();
					const address = server.address();
					if (!address || typeof address === 'string') {
						reject(new Error('Failed to resolve server address'));
						return;
					}
					let closing: Promise<void> | undefined;
					resolve({
						port: address.port,
						hostname: {3},
						url: 'http://' + {3} + ':' + address.port,
						stop(close?: boolean) {
							if (!closing) {
								closing = new Promise<void>((stopResolve, stopReject) => {
									server.close((error?: Error) => {
										if (error) stopReject(error);
										else stopResolve();
									});
									if (close) {
										const closeable = server as typeof server & {
											closeAllConnections?: () => void;
											closeIdleConnections?: () => void;
										};
										if (typeof closeable.closeAllConnections === 'function') closeable.closeAllConnections();
										if (typeof closeable.closeIdleConnections === 'function') closeable.closeIdleConnections();
									}
								});
							}
							return closing;
						}
					});
				};
				server.once('error', fail);
				server.once('listening', ready);
				server.listen(nextPort, {3});
			};
			if ({4} === 0) {
				const first = {0}({ fetch: {1}.fetch });
				first.once('error', () => start(0));
				first.once('listening', () => {
					first.close(() => start(4096));
				});
				first.listen(4096, {3});
			} else {
				start({4});
			}
		})", NodeServer.createAdaptorServer, app, ws, hostname, port);
	}
}
