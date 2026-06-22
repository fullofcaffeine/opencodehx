package opencodehx.interop;

import genes.ts.Unknown;
import js.Syntax;

/**
 * Transitional guarded conversions for values that crossed a JSON/JS boundary
 * as TypeScript `unknown`.
 *
 * OpenCodeHX owns domain decoding, while the reusable narrowing primitives
 * should move into `genes.ts.UnknownNarrow`/`UnknownRecord`. Until then, keep
 * JavaScript's exact `typeof`, `Array.isArray`, own-property, and `Object.keys`
 * semantics in this small raw-interop island. Public methods combine guard and
 * conversion; unchecked target casts remain private.
 */
@:noCompletion
class UnknownAccess {
	public static function string(value:Unknown):Null<String> {
		return isString(value) ? stringUnsafe(value) : null;
	}

	public static function bool(value:Unknown):Null<Bool> {
		return Syntax.code("typeof {0} === 'boolean'", value) ? boolUnsafe(value) : null;
	}

	public static function number(value:Unknown):Null<Float> {
		return Syntax.code("typeof {0} === 'number'", value) ? floatUnsafe(value) : null;
	}

	public static function finiteNumber(value:Unknown):Null<Float> {
		return Syntax.code("typeof {0} === 'number' && Number.isFinite({0})", value) ? floatUnsafe(value) : null;
	}

	public static function safeInteger(value:Unknown):Null<Float> {
		return Syntax.code("typeof {0} === 'number' && Number.isSafeInteger({0})", value) ? floatUnsafe(value) : null;
	}

	public static function int32(value:Unknown):Null<Int> {
		return Syntax.code("typeof {0} === 'number' && Number.isInteger({0}) && {0} >= -2147483648 && {0} <= 2147483647", value) ? intUnsafe(value) : null;
	}

	public static function array(value:Unknown):Null<Array<Unknown>> {
		return Syntax.code("Array.isArray({0})", value) ? arrayUnsafe(value) : null;
	}

	public static function record(value:Unknown):Null<UnknownRecord> {
		return isRecordLike(value) ? recordUnsafe(value) : null;
	}

	public static function stringField(data:Unknown, name:String):Null<String> {
		final record = record(data);
		return record == null ? null : string(record.get(name));
	}

	public static function arrayField(data:Unknown, name:String):Null<Array<Unknown>> {
		final record = record(data);
		return record == null ? null : array(record.get(name));
	}

	public static function isNull(value:Unknown):Bool {
		return Syntax.code("{0} === null", value);
	}

	public static function isUndefined(value:Unknown):Bool {
		return Syntax.code("typeof {0} === 'undefined'", value);
	}

	@:allow(opencodehx.interop.UnknownRecord)
	static function recordGet(record:UnknownRecord, name:String):Unknown {
		// Only own properties are exposed. Missing or inherited fields become
		// runtime undefined, still wrapped as Unknown for the caller to narrow.
		return Unknown.fromBoundary(Syntax.code("Object.prototype.hasOwnProperty.call({0}, {1}) ? ({0} as Record<string, unknown>)[{1}] : undefined", record,
			name));
	}

	@:allow(opencodehx.interop.UnknownRecord)
	static function recordHasOwn(record:UnknownRecord, name:String):Bool {
		return Syntax.code("Object.prototype.hasOwnProperty.call({0}, {1})", record, name);
	}

	@:allow(opencodehx.interop.UnknownRecord)
	static function recordKeys(record:UnknownRecord):Array<String> {
		return Syntax.code("Object.keys({0})", record);
	}

	static function isRecordLike(value:Unknown):Bool {
		return Syntax.code("typeof {0} === 'object' && {0} !== null && !Array.isArray({0})", value);
	}

	static function isString(value:Unknown):Bool {
		return Syntax.code("typeof {0} === 'string'", value);
	}

	static function stringUnsafe(value:Unknown):String {
		return Syntax.code("{0} as string", value);
	}

	static function boolUnsafe(value:Unknown):Bool {
		return Syntax.code("{0} as boolean", value);
	}

	static function floatUnsafe(value:Unknown):Float {
		return Syntax.code("{0} as number", value);
	}

	static function intUnsafe(value:Unknown):Int {
		return Syntax.code("{0} as number", value);
	}

	static function arrayUnsafe(value:Unknown):Array<Unknown> {
		return Syntax.code("{0} as Array<unknown>", value);
	}

	static function recordUnsafe(value:Unknown):UnknownRecord {
		return Syntax.code("{0} as Readonly<Record<string, unknown>>", value);
	}
}
