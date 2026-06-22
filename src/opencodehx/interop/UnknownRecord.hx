package opencodehx.interop;

import genes.ts.Unknown;

/**
 * Transitional read-only view over a non-null, non-array JavaScript object.
 *
 * This is a broad record-like object, not a "plain object" proof. It keeps
 * ownership-aware field reads and key enumeration behind a named boundary until
 * the generic version lands in `genes.ts`.
 */
@:ts.type("Readonly<Record<string, unknown>>")
abstract UnknownRecord(Unknown) {
	@:allow(opencodehx.interop.UnknownAccess)
	inline function new(value:Unknown) {
		this = value;
	}

	public inline function get(name:String):Unknown {
		return UnknownAccess.recordGet(cast this, name);
	}

	public inline function hasOwn(name:String):Bool {
		return UnknownAccess.recordHasOwn(cast this, name);
	}

	public inline function keys():Array<String> {
		return UnknownAccess.recordKeys(cast this);
	}
}
