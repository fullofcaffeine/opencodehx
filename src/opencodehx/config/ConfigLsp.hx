package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;

class ConfigLsp {
	static inline final CUSTOM_EXTENSIONS_REQUIRED = "For custom LSP servers, 'extensions' array is required.";
	static final BUILTIN = ["typescript"];

	public static function validate(value:Dynamic, issues:Array<String>):Dynamic {
		final unknown = Unknown.fromBoundary(value);
		if (UnknownNarrow.bool(unknown) != null)
			return value;
		final record = UnknownNarrow.record(unknown);
		if (record == null) {
			issues.push("lsp: expected boolean or object");
			return value;
		}
		for (id in record.keys())
			validateServer(id, record.get(id), issues);
		return value;
	}

	static function validateServer(id:String, server:Unknown, issues:Array<String>):Void {
		final record = UnknownNarrow.record(server);
		if (record == null) {
			issues.push('lsp.${id}: expected object');
			return;
		}
		if (UnknownNarrow.bool(record.get("disabled")) == true)
			return;
		if (BUILTIN.indexOf(id) != -1)
			return;
		if (!record.hasOwn("extensions")) {
			issues.push(CUSTOM_EXTENSIONS_REQUIRED);
			return;
		}
		final extensions = UnknownNarrow.array(record.get("extensions"));
		if (extensions == null) {
			issues.push('lsp.${id}.extensions: expected array');
			return;
		}
		validateExtensions(id, extensions, issues);
	}

	static function validateExtensions(id:String, extensions:UnknownArray, issues:Array<String>):Void {
		for (index in 0...extensions.length)
			if (UnknownNarrow.string(extensions.get(index)) == null)
				issues.push('lsp.${id}.extensions: expected string entries');
	}
}
