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
}
