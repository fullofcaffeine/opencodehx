package opencodehx.tool;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import opencodehx.tool.ToolTypes.ToolInputDecode;

class ToolValidation {
	public static function record(raw:Unknown, issues:Array<String>):Null<UnknownRecord> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			issues.push("arguments: expected object");
		return record;
	}

	public static function requireString(args:UnknownRecord, field:String, issues:Array<String>):String {
		return requireStringWithEmpty(args, field, issues, false);
	}

	public static function requireStringAllowEmpty(args:UnknownRecord, field:String, issues:Array<String>):String {
		return requireStringWithEmpty(args, field, issues, true);
	}

	static function requireStringWithEmpty(args:UnknownRecord, field:String, issues:Array<String>, allowEmpty:Bool):String {
		if (!args.hasOwn(field) || absent(args.get(field))) {
			issues.push('${field}: expected string');
			return "";
		}
		final value = UnknownNarrow.string(args.get(field));
		if (value == null) {
			issues.push('${field}: expected string');
			return "";
		}
		if (!allowEmpty && StringTools.trim(value) == "") {
			issues.push('${field}: expected non-empty string');
			return "";
		}
		return value;
	}

	public static function optionalString(args:UnknownRecord, field:String, issues:Array<String>):Null<String> {
		if (!args.hasOwn(field) || absent(args.get(field)))
			return null;
		final value = UnknownNarrow.string(args.get(field));
		if (value == null) {
			issues.push('${field}: expected string');
			return null;
		}
		final text = value;
		if (text == "undefined" || text == "null") {
			issues.push('${field}: omit this field instead of passing "${text}"');
			return null;
		}
		return text;
	}

	public static function optionalInt(args:UnknownRecord, field:String, issues:Array<String>):Null<Int> {
		if (!args.hasOwn(field) || absent(args.get(field)))
			return null;
		final value = UnknownNarrow.int32(args.get(field));
		if (value == null) {
			issues.push('${field}: expected integer');
			return null;
		}
		return value;
	}

	public static function requiredInt(args:UnknownRecord, field:String, issues:Array<String>):Int {
		if (!args.hasOwn(field) || absent(args.get(field))) {
			issues.push('${field}: expected integer');
			return 0;
		}
		final value = UnknownNarrow.int32(args.get(field));
		if (value == null) {
			issues.push('${field}: expected integer');
			return 0;
		}
		return value;
	}

	public static function optionalBool(args:UnknownRecord, field:String, issues:Array<String>):Null<Bool> {
		if (!args.hasOwn(field) || absent(args.get(field)))
			return null;
		final value = UnknownNarrow.bool(args.get(field));
		if (value == null) {
			issues.push('${field}: expected boolean');
			return null;
		}
		return value;
	}

	public static function finish<T>(issues:Array<String>, input:T):ToolInputDecode<T> {
		return issues.length == 0 ? Decoded(input) : Invalid(issues);
	}

	static function absent(value:Unknown):Bool {
		return UnknownNarrow.isUndefined(value) || UnknownNarrow.isNull(value);
	}
}
