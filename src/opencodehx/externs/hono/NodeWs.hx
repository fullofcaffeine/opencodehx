package opencodehx.externs.hono;

import genes.ts.Unknown;
import haxe.extern.EitherType;
import js.lib.ArrayBuffer;
import js.lib.Uint8Array;
import opencodehx.externs.hono.Hono.HonoHandler;
import opencodehx.externs.hono.Hono.HonoContext;
import opencodehx.externs.hono.NodeServer.NodeServerType;

typedef NodeWebSocketOptions = {
	final app:Hono;
}

typedef NodeWebSocketPayload = EitherType<String, Uint8Array>;
typedef NodeWebSocketMessage = EitherType<String, ArrayBuffer>;

typedef NodeWebSocketRaw = {
	var readyState:Int;
	@:optional var data:Unknown;
	function send(data:NodeWebSocketPayload):Void;
	function close(?code:Int, ?reason:String):Void;
}

typedef NodeWebSocketPeer = {
	@:optional final raw:NodeWebSocketRaw;
	function close(?code:Int, ?reason:String):Void;
}

typedef NodeWebSocketMessageEvent = {
	final data:Unknown;
}

typedef NodeWebSocketHandlerCallbacks = {
	final onOpen:(event:Unknown, socket:NodeWebSocketPeer) -> Void;
	final onMessage:NodeWebSocketMessageEvent->Void;
	final onClose:Void->Void;
	final onError:Void->Void;
}

typedef NodeWebSocketHandler = HonoContext->NodeWebSocketHandlerCallbacks;

typedef NodeWebSocketRuntime = {
	final upgradeWebSocket:(handler:NodeWebSocketHandler) -> HonoHandler;
	final injectWebSocket:(server:NodeServerType) -> Void;
}

@:jsRequire("@hono/node-ws")
extern class NodeWs {
	static function createNodeWebSocket(options:NodeWebSocketOptions):NodeWebSocketRuntime;
}
