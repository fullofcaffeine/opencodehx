package opencodehx.externs.node;

import js.lib.Uint8Array;

/**
 * Opaque Node Buffer value. Haxe has no native Node Buffer model, so the
 * concrete byte operations stay in `host.node.NodeBuffer`.
 */
@:ts.type("import('node:buffer').Buffer")
abstract NodeBufferData(Dynamic) from Dynamic to Dynamic {}

@:jsRequire("node:buffer", "Buffer")
extern class Buffer {
	@:overload(function(data:Uint8Array):NodeBufferData {})
	static function from(data:String, encoding:String):NodeBufferData;
}
