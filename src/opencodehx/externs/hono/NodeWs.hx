package opencodehx.externs.hono;

import opencodehx.externs.hono.Hono.HonoHandler;
import opencodehx.externs.hono.NodeServer.NodeServerType;

typedef NodeWebSocketOptions = {
	final app:Hono;
}

typedef NodeWebSocketRuntime = {
	final upgradeWebSocket:(handler:Dynamic) -> HonoHandler;
	final injectWebSocket:(server:NodeServerType) -> Void;
}

@:jsRequire("@hono/node-ws")
extern class NodeWs {
	static function createNodeWebSocket(options:NodeWebSocketOptions):NodeWebSocketRuntime;
}
