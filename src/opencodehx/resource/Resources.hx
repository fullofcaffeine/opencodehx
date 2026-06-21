package opencodehx.resource;

import js.Syntax;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodeBuffer;

typedef WasmResource = {
	final path:String;
	final byteLength:Int;
	final prefix:Array<Int>;
}

@:ts.type("URL")
abstract ResourceUrl(Dynamic) from Dynamic to Dynamic {}

class Resources {
	public static function text(relative:String):String {
		return Fs.readFileSync(file(relative), "utf8");
	}

	public static function file(relative:String):String {
		return Url.fileURLToPath(url(relative));
	}

	public static function wasm(relative:String):WasmResource {
		final path = file(relative);
		final bytes = Fs.readFileBufferSync(path);
		return {
			path: path,
			byteLength: NodeBuffer.byteLength(bytes),
			prefix: NodeBuffer.prefixBytes(bytes, 4),
		};
	}

	static function url(relative:String):ResourceUrl {
		// import.meta.url is an ESM module boundary; keep it localized here until
		// genes-ts grows generic text/file/WASM resource import helpers.
		return Syntax.code("new URL({0}, import.meta.url)", "../../resources/" + clean(relative));
	}

	static function clean(relative:String):String {
		final normalized = StringTools.replace(relative, "\\", "/");
		if (StringTools.startsWith(normalized, "/") || normalized.indexOf("../") != -1 || normalized == "..")
			throw 'invalid resource path ${relative}';
		return normalized;
	}
}
