package opencodehx.externs.ws;

import genes.ts.Unknown;
import js.lib.Error;

@:jsRequire("ws", "WebSocket")
extern class WebSocket {
	function new(url:String);

	@:native("on")
	function onOpen(event:String, handler:Void->Void):WebSocket;

	@:native("on")
	function onMessage(event:String, handler:(data:Unknown, isBinary:Bool) -> Void):WebSocket;

	@:native("on")
	function onError(event:String, handler:Error->Void):WebSocket;

	function send(data:String):Void;
	function close():Void;
}
