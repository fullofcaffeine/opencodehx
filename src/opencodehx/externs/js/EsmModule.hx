package opencodehx.externs.js;

import js.Syntax;

/**
 * ES module metadata boundary.
 *
 * Haxe/genes-ts does not yet expose a structured `import.meta` expression.
 * Keep the raw access here as a tiny string-valued facade so callers can use
 * typed APIs, such as `new URL(relative, EsmModule.url())`, around it.
 */
class EsmModule {
	public static inline function url():String {
		return Syntax.code("import.meta.url");
	}
}
