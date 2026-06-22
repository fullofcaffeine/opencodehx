package opencodehx.resource;

import js.html.URL;
import opencodehx.externs.js.EsmModule;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodeBuffer;

typedef WasmResource = {
	final path:String;
	final byteLength:Int;
	final prefix:Array<Int>;
}

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

	static function url(relative:String):URL {
		// import.meta.url is an ESM module boundary; EsmModule keeps the raw
		// access localized until genes-ts grows generic resource import helpers.
		return new URL("../../resources/" + clean(relative), EsmModule.url());
	}

	static function clean(relative:String):String {
		final normalized = StringTools.replace(relative, "\\", "/");
		if (StringTools.startsWith(normalized, "/") || normalized.indexOf("../") != -1 || normalized == "..")
			throw 'invalid resource path ${relative}';
		return normalized;
	}
}
