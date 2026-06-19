package opencodehx.externs.web;

import haxe.DynamicAccess;
import js.html.Response;
import js.lib.Promise;
import js.lib.Uint8Array;

typedef WebTextDecodeOptions = {
	@:optional final stream:Bool;
}

typedef WebReadableStreamReadResult<T> = {
	final done:Bool;
	@:optional final value:Null<T>;
}

typedef WebReadableStreamSource<T> = {
	function start(controller:WebReadableStreamDefaultController<T>):Void;
}

typedef WebResponseInit = {
	final headers:DynamicAccess<String>;
}

extern typedef WebResponseWithBody = {
	final body:Null<WebReadableStream<Uint8Array>>;
}

@:native("ReadableStream")
extern class WebReadableStream<T> {
	function new(source:WebReadableStreamSource<T>);
	function getReader():WebReadableStreamDefaultReader<T>;
}

@:native("ReadableStreamDefaultController")
extern class WebReadableStreamDefaultController<T> {
	function enqueue(value:T):Void;
	function close():Void;
}

@:native("ReadableStreamDefaultReader")
extern class WebReadableStreamDefaultReader<T> {
	function read():Promise<WebReadableStreamReadResult<T>>;
	function cancel():Promise<Void>;
}

@:native("TextDecoder")
extern class WebTextDecoder {
	function new();
	function decode(?input:Uint8Array, ?options:WebTextDecodeOptions):String;
}

@:native("TextEncoder")
extern class WebTextEncoder {
	function new();
	function encode(input:String):Uint8Array;
}

class WebResponseStreams {
	public static inline function body(response:Response):Null<WebReadableStream<Uint8Array>> {
		// Haxe 4.3's js.html.Response extern does not expose the standard
		// `body` property. Keep the structural cast at this Web-platform facade;
		// callers receive a typed ReadableStream and never touch Dynamic.
		final withBody:WebResponseWithBody = cast response;
		return withBody.body;
	}
}
