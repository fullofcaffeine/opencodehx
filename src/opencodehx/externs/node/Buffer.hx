package opencodehx.externs.node;

import js.lib.Uint8Array;

@:jsRequire("node:buffer", "Buffer")
extern class Buffer {
	@:overload(function(data:Uint8Array):BufferValue {})
	static function from(data:String, encoding:String):BufferValue;
}

extern class BufferValue {
	function toString(?encoding:String):String;
}
