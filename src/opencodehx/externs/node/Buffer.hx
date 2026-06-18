package opencodehx.externs.node;

@:jsRequire("node:buffer", "Buffer")
extern class Buffer {
	static function from(data:String, encoding:String):BufferValue;
}

extern class BufferValue {
	function toString(?encoding:String):String;
}
