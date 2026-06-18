package opencodehx.externs.ws;

@:jsRequire("ws", "WebSocket")
extern class WebSocket {
	function new(url:String);
	function on(event:String, handler:Dynamic):WebSocket;
	function send(data:Dynamic):Void;
	function close():Void;
}
