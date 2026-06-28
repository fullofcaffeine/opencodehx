package opencodehx.externs.node;

import js.lib.Uint8Array;
import opencodehx.externs.web.WebStreams.WebArrayBufferData;

/**
 * Narrow Node Buffer instance surface used by host facades.
 *
 * The runtime value still comes from Node's `Buffer`, but modeling the
 * inspected fields/methods here lets app-facing host code avoid raw
 * `js.Syntax.code` for ordinary buffer operations.
 */
@:ts.type("import('node:buffer').Buffer")
extern class NodeBufferData {
	public final byteLength:Int;

	function toString(?encoding:String):String;
	function subarray(start:Int, ?end:Int):Uint8Array;
}

@:jsRequire("node:buffer", "Buffer")
extern class Buffer {
	@:overload(function(data:WebArrayBufferData):NodeBufferData {})
	@:overload(function(data:Uint8Array):NodeBufferData {})
	static function from(data:String, encoding:String):NodeBufferData;
	static function concat(chunks:Array<Uint8Array>):NodeBufferData;
}
