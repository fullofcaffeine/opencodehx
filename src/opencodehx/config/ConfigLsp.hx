package opencodehx.config;

class ConfigLsp {
	static inline final CUSTOM_EXTENSIONS_REQUIRED = "For custom LSP servers, 'extensions' array is required.";
	static final BUILTIN = ["typescript"];

	public static function validate(value:Dynamic, issues:Array<String>):Dynamic {
		if (Std.isOfType(value, Bool))
			return value;
		if (value == null || !Reflect.isObject(value) || Std.isOfType(value, Array)) {
			issues.push("lsp: expected boolean or object");
			return value;
		}
		for (id in Reflect.fields(value))
			validateServer(id, Reflect.field(value, id), issues);
		return value;
	}

	static function validateServer(id:String, server:Dynamic, issues:Array<String>):Void {
		if (server == null || !Reflect.isObject(server) || Std.isOfType(server, Array)) {
			issues.push('lsp.${id}: expected object');
			return;
		}
		if (Reflect.field(server, "disabled") == true)
			return;
		if (BUILTIN.indexOf(id) != -1)
			return;
		if (!Reflect.hasField(server, "extensions")) {
			issues.push(CUSTOM_EXTENSIONS_REQUIRED);
			return;
		}
		final extensions = Reflect.field(server, "extensions");
		if (!Std.isOfType(extensions, Array)) {
			issues.push('lsp.${id}.extensions: expected array');
			return;
		}
		for (item in (cast extensions : Array<Dynamic>)) {
			if (!Std.isOfType(item, String))
				issues.push('lsp.${id}.extensions: expected string entries');
		}
	}
}
