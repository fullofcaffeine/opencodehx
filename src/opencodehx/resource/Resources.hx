package opencodehx.resource;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end
#if !macro
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json;
import js.html.URL;
import opencodehx.externs.js.EsmModule;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodeBuffer;
#end

enum abstract ResourceKind(String) from String to String {
	final Text = "text";
	final JsonResource = "json";
	final File = "file";
	final Wasm = "wasm";
	final Worker = "worker";
}

enum abstract KnownResourcePath(String) to String {
	var AssetPulseA = "asset/pulse-a.wav";
	var ErrorDiagnosticsGolden = "errors/diagnostics.golden.json";
	var PromptExample = "prompt/example.txt";
	var SmokeResourceJson = "smoke-resource.json";
	var TreeSitterBashWasm = "wasm/tree-sitter-bash.wasm";
	var TreeSitterFixtureWasm = "wasm/tree-sitter-fixture.wasm";
	var TreeSitterPowerShellWasm = "wasm/tree-sitter-powershell.wasm";
	var TreeSitterWasm = "wasm/tree-sitter.wasm";
	var ParserWorker = "worker/parser-worker.mjs";
	var TuiWorker = "worker/tui-worker.mjs";
}

class ResourcePaths {
	public static macro function known(path:Expr):Expr {
		final resourcePath = literalString(path);
		final entries = resourceEntries();
		for (entry in entries) {
			if (entry.value == resourcePath) {
				final resourceExpr:Expr = {
					expr: EField(macro opencodehx.resource.Resources.KnownResourcePath, entry.fieldName),
					pos: path.pos,
				};
				final out = macro $resourceExpr;
				out.pos = path.pos;
				return out;
			}
		}

		Context.error('Unknown source-authored resource path "${resourcePath}". Known resource paths: ${knownResourcePaths(entries)}.', path.pos);
		return macro null;
	}

	#if macro
	static function resourceEntries():Array<{final fieldName:String; final value:String;}> {
		return switch Context.getType("opencodehx.resource.Resources.KnownResourcePath") {
			case TAbstract(_.get() => abstractType, _):
				final impl = abstractType.impl.get();
				final out:Array<{final fieldName:String; final value:String;}> = [];
				for (field in impl.statics.get()) {
					switch field.kind {
						case FVar(_, _):
							final value = typedStringValue(field.expr());
							if (value != null) out.push({fieldName: field.name, value: value});
						default:
					}
				}
				out;
			default:
				[];
		}
	}

	static function typedStringValue(expr:TypedExpr):Null<String> {
		if (expr == null)
			return null;
		return switch expr.expr {
			case TMeta(_, inner) | TParenthesis(inner) | TCast(inner, _):
				typedStringValue(inner);
			case TConst(TString(value)):
				value;
			default:
				null;
		}
	}

	static function knownResourcePaths(entries:Array<{final fieldName:String; final value:String;}>):String {
		return [for (entry in entries) entry.value].join(", ");
	}

	static function literalString(expr:Expr):String {
		return switch expr.expr {
			case EConst(CString(value, _)):
				value;
			default:
				Context.error("Source-authored resource paths must be string literals so the resource catalog can be checked at compile time.", expr.pos);
		}
	}
	#end
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

#if !macro
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
#end
