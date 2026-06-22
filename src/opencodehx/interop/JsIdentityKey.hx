package opencodehx.interop;

import genes.ts.Unknown;
import js.Syntax;

/**
 * Opaque JavaScript reference-identity token.
 *
 * This is not decoded data and it intentionally exposes no record/field API.
 * It exists for host objects that OpenCode identifies only by JavaScript
 * reference equality, such as PTY websocket subscriber keys. Haxe can type the
 * socket facade structurally, but it has no portable type for "an arbitrary JS
 * object reference that may only be compared with `===`", so the raw operation
 * is contained here.
 *
 * The source-level concept is retargetable: a future non-JS host can implement
 * the same opaque identity-token contract using that runtime's stable
 * connection handle or reference identity while keeping product code unchanged.
 * The current implementation is intentionally JS-shaped because OpenCode parity
 * depends on upstream websocket object identity.
 */
abstract JsIdentityKey(Unknown) {
	inline function new(value:Unknown) {
		this = value;
	}

	public static inline function truthyObjectOrFallback<T>(candidate:Null<Unknown>, fallback:T):JsIdentityKey {
		// This does not prove a plain object or any field shape. It only selects
		// an opaque JS reference for later identity comparison.
		return new JsIdentityKey(Unknown.fromBoundary(Syntax.code("({0} && typeof {0} === 'object' ? {0} : {1})", candidate, fallback)));
	}

	public inline function same(other:JsIdentityKey):Bool {
		// Identity keys preserve upstream JS Map-key semantics; structural Haxe
		// equality would be the wrong contract for host websocket wrappers.
		return Syntax.code("{0} === {1}", this, other.raw());
	}

	@:noCompletion
	inline function raw():Unknown {
		return this;
	}
}
