package opencodehx.externs.node;

/**
 * Narrow extern for the Node/global console methods used by the generated
 * smoke binary. Keeping this as an extern avoids scattering raw
 * `js.Syntax.code("console...")` snippets through application code while
 * still emitting the normal global `console.log(...)` calls.
 */
@:native("console")
extern class Console {
	static function log(value:String):Void;
	// Promise rejection reasons are arbitrary JS values. This is a host-output
	// boundary only: the value is printed and never inspected by application code.
	static function error(value:Dynamic):Void;
}
