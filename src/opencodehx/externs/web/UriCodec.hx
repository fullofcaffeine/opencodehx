package opencodehx.externs.web;

import js.Syntax;

/**
 * Narrow facade for JavaScript's global URI component decoder.
 *
 * OpenCode's data-url helper relies on `decodeURIComponent` semantics:
 * percent escapes are decoded, but `+` remains a literal plus. Haxe's
 * higher-level URL helpers do not model that exact boundary clearly.
 */
class UriCodec {
	public static inline function decodeComponent(value:String):String {
		// This is a tiny target-global boundary. Keep the raw call here so
		// application code can depend on a typed helper with upstream JS semantics.
		return Syntax.code("decodeURIComponent({0})", value);
	}
}
