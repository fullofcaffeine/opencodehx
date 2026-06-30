package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;

/**
 * Validation and narrow reads for the still-open `lsp` config boundary.
 *
 * `ConfigInfo.lsp` remains boundary debt until the full LSP config schema is
 * modeled. Keep object traversal here so callers do not use raw reflection over
 * the open config payload.
 */
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

	public static function hasServer(value:Unknown, id:String):Bool {
		return server(value, id) != null;
	}

	public static function hasServerField(value:Unknown, id:String, field:String):Bool {
		final record = server(value, id);
		return record != null && record.hasOwn(field);
	}

	public static function disabled(value:Unknown, id:String):Null<Bool> {
		final record = server(value, id);
		return record == null ? null : UnknownNarrow.bool(record.get("disabled"));
	}

	public static function extensions(value:Unknown, id:String):Null<Array<String>> {
		final record = server(value, id);
		if (record == null)
			return null;
		final source = UnknownNarrow.array(record.get("extensions"));
		if (source == null)
			return null;
		final out:Array<String> = [];
		for (index in 0...source.length) {
			final item = UnknownNarrow.string(source.get(index));
			if (item == null)
				return null;
			out.push(item);
		}
		return out;
	}

	static function server(value:Unknown, id:String):Null<UnknownRecord> {
		final root = UnknownNarrow.record(value);
		return root == null ? null : UnknownNarrow.record(root.get(id));
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
