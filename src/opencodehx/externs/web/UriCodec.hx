package opencodehx.externs.web;

@:native("globalThis")
extern class UriGlobals {
	@:native("decodeURIComponent")
	static function decodeComponent(value:String):String;
}

/**
 * Narrow facade for JavaScript's global URI component decoder.
 *
 * OpenCode's data-url helper relies on `decodeURIComponent` semantics:
 * percent escapes are decoded, but `+` remains a literal plus. Haxe's
 * higher-level URL helpers do not model that exact boundary clearly.
 */
class UriCodec {
	public static inline function decodeComponent(value:String):String {
		return UriGlobals.decodeComponent(value);
	}
}
