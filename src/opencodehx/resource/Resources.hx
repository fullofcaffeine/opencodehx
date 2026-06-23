package opencodehx.resource;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import js.html.URL;
import opencodehx.externs.js.EsmModule;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodeBuffer;

enum abstract ResourceKind(String) from String to String {
	final Text = "text";
	final JsonResource = "json";
	final File = "file";
	final Wasm = "wasm";
	final Worker = "worker";
}

typedef ResourceManifestEntry = {
	final path:String;
	final kind:ResourceKind;
	final bytes:Int;
	final sha256:String;
}

typedef ResourceManifest = {
	final version:Int;
	final generatedBy:String;
	final resources:Array<ResourceManifestEntry>;
}

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

	public static function worker(relative:String):String {
		return file(relative);
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

	public static function manifest():ResourceManifest {
		return decodeManifest(text("manifest.json"));
	}

	public static function manifestEntry(relative:String):Null<ResourceManifestEntry> {
		final wanted = clean(relative);
		for (entry in manifest().resources) {
			if (entry.path == wanted)
				return entry;
		}
		return null;
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

	static function decodeManifest(text:String):ResourceManifest {
		final record = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(text)));
		if (record == null)
			throw "invalid resource manifest";
		final version = UnknownNarrow.int32(record.get("version"));
		final generatedBy = UnknownNarrow.string(record.get("generatedBy"));
		final rawResources = UnknownNarrow.array(record.get("resources"));
		if (version == null || generatedBy == null || rawResources == null)
			throw "invalid resource manifest";

		final resources:Array<ResourceManifestEntry> = [];
		for (index in 0...rawResources.length) {
			final entry = decodeManifestEntry(rawResources.get(index));
			if (entry == null)
				throw 'invalid resource manifest entry ${index}';
			resources.push(entry);
		}
		return {
			version: version,
			generatedBy: generatedBy,
			resources: resources,
		};
	}

	static function decodeManifestEntry(raw:Unknown):Null<ResourceManifestEntry> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return null;
		final path = UnknownNarrow.string(record.get("path"));
		final kindText = UnknownNarrow.string(record.get("kind"));
		final bytes = UnknownNarrow.int32(record.get("bytes"));
		final sha256 = UnknownNarrow.string(record.get("sha256"));
		final kind:Null<ResourceKind> = kindText == null ? null : decodeKind(kindText);
		if (path == null || kind == null || bytes == null || sha256 == null)
			return null;
		return {
			path: clean(path),
			kind: kind,
			bytes: bytes,
			sha256: sha256,
		};
	}

	static function decodeKind(kind:String):Null<ResourceKind> {
		return switch kind {
			case "text": Text;
			case "json": JsonResource;
			case "file": File;
			case "wasm": Wasm;
			case "worker": Worker;
			case _: null;
		}
	}
}
