package opencodehx.host;

import js.lib.Date;

/**
 * Portable clock boundary for runtime code that needs JavaScript-compatible
 * millisecond timestamps.
 *
 * Keep wall-clock reads here instead of scattering `js.Syntax.code("Date...")`
 * through app modules. That makes future deterministic tests and non-JS host
 * adapters easier without changing the OpenCode-facing timestamp semantics.
 */
class Clock {
	public static inline function nowMillis():Float {
		return Date.now();
	}

	public static inline function parseHttpDateMillis(value:String):Float {
		return Date.parse(value);
	}
}
