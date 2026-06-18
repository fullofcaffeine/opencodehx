package opencodehx.tool;

class ToolValidation {
	public static function requireString(args:Dynamic, field:String, issues:Array<String>):String {
		if (!Reflect.hasField(args, field) || Reflect.field(args, field) == null) {
			issues.push('${field}: expected string');
			return "";
		}
		final value = Reflect.field(args, field);
		if (!Std.isOfType(value, String)) {
			issues.push('${field}: expected string');
			return "";
		}
		if (StringTools.trim(value) == "") {
			issues.push('${field}: expected non-empty string');
			return "";
		}
		return value;
	}

	public static function optionalString(args:Dynamic, field:String, issues:Array<String>):Null<String> {
		if (!Reflect.hasField(args, field) || Reflect.field(args, field) == null)
			return null;
		final value = Reflect.field(args, field);
		if (!Std.isOfType(value, String)) {
			issues.push('${field}: expected string');
			return null;
		}
		final text = Std.string(value);
		if (text == "undefined" || text == "null") {
			issues.push('${field}: omit this field instead of passing "${text}"');
			return null;
		}
		return text;
	}

	public static function optionalInt(args:Dynamic, field:String, issues:Array<String>):Null<Int> {
		if (!Reflect.hasField(args, field) || Reflect.field(args, field) == null)
			return null;
		final value:Dynamic = Reflect.field(args, field);
		if (!Std.isOfType(value, Int) && !Std.isOfType(value, Float)) {
			issues.push('${field}: expected integer');
			return null;
		}
		final number = Std.int(value);
		if (number != value) {
			issues.push('${field}: expected integer');
			return null;
		}
		return number;
	}

	public static function optionalBool(args:Dynamic, field:String, issues:Array<String>):Null<Bool> {
		if (!Reflect.hasField(args, field) || Reflect.field(args, field) == null)
			return null;
		final value:Dynamic = Reflect.field(args, field);
		if (!Std.isOfType(value, Bool)) {
			issues.push('${field}: expected boolean');
			return null;
		}
		return value;
	}
}
