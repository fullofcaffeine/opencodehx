package opencodehx.interop;

import genes.ts.Unknown;
import js.Syntax;

/**
 * Guarded runtime accessors for values that crossed a JSON/JS boundary as
 * `unknown`.
 *
 * Haxe cannot express TypeScript's runtime `typeof`, `Array.isArray`, or
 * `Object.keys` checks directly, so this class is the deliberately small
 * raw-interop island for probing untrusted values. Every cast-like operation
 * is paired with a guard and returns a typed Haxe value or keeps the result as
 * `Unknown`, so application code does not spread `Syntax.code` or unchecked
 * object indexing through product logic.
 */
class UnknownAccess {
	public static function field(data:Unknown, name:String):Null<Unknown> {
		if (!hasOwnField(data, name))
			return null;
		return readField(data, name);
	}

	public static function nonNullField(data:Unknown, name:String):Null<Unknown> {
		if (!hasNonNullField(data, name))
			return null;
		return readField(data, name);
	}

	public static function stringField(data:Unknown, name:String):Null<String> {
		final value = field(data, name);
		if (value == null || !isString(value))
			return null;
		return asString(value);
	}

	public static function arrayField(data:Unknown, name:String):Null<Array<Unknown>> {
		final value = field(data, name);
		if (value == null || !isArray(value))
			return null;
		return asArray(value);
	}

	public static function objectKeys(data:Unknown):Array<String> {
		if (!isPlainObject(data))
			return [];
		// Object.keys is the native JS operation for unknown object boundaries.
		return Syntax.code("Object.keys({0} as Record<string, unknown>)", data);
	}

	public static function hasOwnField(data:Unknown, name:String):Bool {
		return Syntax.code("typeof {0} === 'object' && {0} !== null && !Array.isArray({0}) && Object.prototype.hasOwnProperty.call({0}, {1})", data, name);
	}

	public static function hasNonNullField(data:Unknown, name:String):Bool {
		return Syntax.code("typeof {0} === 'object' && {0} !== null && !Array.isArray({0}) && ({0} as Record<string, unknown>)[{1}] != null", data, name);
	}

	public static function isPlainObject(value:Null<Unknown>):Bool {
		return Syntax.code("typeof {0} === 'object' && {0} !== null && !Array.isArray({0})", value);
	}

	public static function isArray(value:Null<Unknown>):Bool {
		return Syntax.code("Array.isArray({0})", value);
	}

	public static function isString(value:Null<Unknown>):Bool {
		return Syntax.code("typeof {0} === 'string'", value);
	}

	public static function isNonNegativeInteger(value:Null<Unknown>):Bool {
		return Syntax.code("typeof {0} === 'number' && Number.isInteger({0}) && {0} >= 0", value);
	}

	public static function asString(value:Unknown):String {
		// Safe only after isString(value); keep all unknown narrowing in this helper.
		return Syntax.code("{0} as string", value);
	}

	public static function asArray(value:Unknown):Array<Unknown> {
		// Safe only after isArray(value); array contents intentionally remain Unknown.
		return Syntax.code("{0} as Array<unknown>", value);
	}

	public static function asInt(value:Unknown):Int {
		// Safe only after isNonNegativeInteger(value); Haxe Int maps to TS number.
		return Syntax.code("{0} as number", value);
	}

	static function readField(data:Unknown, name:String):Unknown {
		// Safe only after hasOwnField/hasNonNullField proves object shape and field
		// ownership. The result remains Unknown until a caller performs another guard.
		return Unknown.fromBoundary(Syntax.code("({0} as Record<string, unknown>)[{1}]", data, name));
	}
}
