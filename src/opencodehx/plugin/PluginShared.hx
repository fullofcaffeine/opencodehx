package opencodehx.plugin;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.Json;
import opencodehx.config.ConfigPlugin;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;

enum abstract PluginSource(String) to String {
	var File = "file";
	var Npm = "npm";
}

typedef ParsedPluginSpecifier = {
	final pkg:String;
	final version:String;
}

typedef PluginPackage = {
	final dir:String;
	final pkg:String;
	final json:UnknownRecord;
}

typedef PluginEntry = {
	final spec:String;
	final source:PluginSource;
	final target:String;
	@:optional final pkg:PluginPackage;
	@:optional final entry:String;
}

class PluginShared {
	public static function parsePluginSpecifier(spec:String):ParsedPluginSpecifier {
		if (StringTools.startsWith(spec, "npm:"))
			return parseNpmProtocol(spec.substr(4));
		if (StringTools.startsWith(spec, "git+"))
			return {pkg: spec, version: ""};

		final split = versionSplit(spec);
		if (split == -1)
			return {pkg: spec, version: "latest"};
		return {
			pkg: spec.substr(0, split),
			version: spec.substr(split + 1),
		};
	}

	public static function pluginSource(spec:String):PluginSource {
		return isPathPluginSpec(spec) ? File : Npm;
	}

	public static function isPathPluginSpec(spec:String):Bool {
		return StringTools.startsWith(spec, "file://") || StringTools.startsWith(spec, ".") || isAbsolutePath(spec);
	}

	public static function createPluginEntry(spec:String, target:String):PluginEntry {
		final source = pluginSource(spec);
		final pkg = readPluginPackage(target);
		final entry = if (pkg != null) packageEntrypoint(pkg) else target;
		return {
			spec: spec,
			source: source,
			target: target,
			pkg: pkg,
			entry: entry,
		};
	}

	public static function resolvePathPluginTarget(spec:String):String {
		return ConfigPlugin.resolvePathPluginTarget(spec);
	}

	public static function readPluginPackage(target:String):Null<PluginPackage> {
		final file = StringTools.startsWith(target, "file://") ? Url.fileURLToPath(target) : target;
		if (!Fs.existsSync(file))
			return null;
		final stat = Fs.statSync(file);
		final dir = stat.isDirectory() ? file : NodePath.dirname(file);
		final pkg = NodePath.join(dir, "package.json");
		if (!Fs.existsSync(pkg))
			return null;
		final json = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(Fs.readFileSync(pkg, "utf8"))));
		if (json == null)
			return null;
		return {dir: dir, pkg: pkg, json: json};
	}

	public static function resolvePluginId(source:PluginSource, spec:String, target:String, id:Null<String>, ?pkg:PluginPackage):String {
		if (id != null && StringTools.trim(id) != "")
			return StringTools.trim(id);
		if (source == File)
			throw 'Path plugin ${spec} must export id';
		final hit = pkg != null ? pkg : readPluginPackage(target);
		if (hit == null)
			throw 'Plugin package ${target} is missing package.json';
		final name = stringField(hit.json, "name");
		if (name == null || StringTools.trim(name) == "")
			throw 'Plugin package ${hit.pkg} is missing name';
		return StringTools.trim(name);
	}

	public static function readPackageThemes(spec:String, pkg:PluginPackage):Array<String> {
		if (!pkg.json.hasOwn("oc-themes"))
			return [];
		final list = UnknownNarrow.array(pkg.json.get("oc-themes"));
		if (list == null)
			throw 'Plugin ${spec} has invalid oc-themes field';
		final out:Array<String> = [];
		for (index in 0...list.length) {
			final item = stringAt(list, index);
			if (item == null)
				throw 'Plugin ${spec} has invalid oc-themes entry';
			final raw = StringTools.trim(item);
			if (raw == "")
				throw 'Plugin ${spec} has empty oc-themes entry';
			if (StringTools.startsWith(raw, "file://") || isAbsolutePath(raw))
				throw 'Plugin ${spec} oc-themes entry must be relative: ${raw}';
			out.push(NodePath.join(pkg.dir, raw));
		}
		return out;
	}

	static function packageEntrypoint(pkg:PluginPackage):String {
		final main = stringField(pkg.json, "main");
		if (main != null && StringTools.trim(main) != "")
			return Url.pathToFileURL(NodePath.resolve(pkg.dir, main)).href;
		return Url.pathToFileURL(pkg.dir).href;
	}

	static function parseNpmProtocol(raw:String):ParsedPluginSpecifier {
		final split = versionSplit(raw);
		if (split == -1)
			return {pkg: raw, version: "latest"};
		return {
			pkg: raw.substr(0, split),
			version: raw.substr(split + 1),
		};
	}

	static function versionSplit(spec:String):Int {
		if (StringTools.startsWith(spec, "@")) {
			final slash = spec.indexOf("/");
			if (slash == -1)
				return -1;
			return spec.indexOf("@", slash + 1);
		}
		return spec.indexOf("@");
	}

	static function isAbsolutePath(raw:String):Bool {
		return NodePath.isAbsolute(raw) || isWindowsAbsolutePath(raw);
	}

	static function stringField(data:UnknownRecord, field:String):Null<String> {
		return UnknownNarrow.string(data.get(field));
	}

	static function stringAt(items:UnknownArray, index:Int):Null<String> {
		return UnknownNarrow.string(items.get(index));
	}

	static function isWindowsAbsolutePath(raw:String):Bool {
		if (raw.length < 3)
			return false;
		final drive = raw.charCodeAt(0);
		final letter = (drive >= 0x41 && drive <= 0x5A) || (drive >= 0x61 && drive <= 0x7A);
		return letter && raw.charAt(1) == ":" && (raw.charAt(2) == "\\" || raw.charAt(2) == "/");
	}
}
