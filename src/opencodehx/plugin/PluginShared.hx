package opencodehx.plugin;

import haxe.DynamicAccess;
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
	final json:DynamicAccess<Dynamic>;
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
		final raw:Dynamic = Json.parse(Fs.readFileSync(pkg, "utf8"));
		final json = new DynamicAccess<Dynamic>();
		for (name in Reflect.fields(raw))
			json.set(name, Reflect.field(raw, name));
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
		final name = hit.json.get("name");
		if (!isString(name) || StringTools.trim(cast name) == "")
			throw 'Plugin package ${hit.pkg} is missing name';
		return StringTools.trim(cast name);
	}

	public static function readPackageThemes(spec:String, pkg:PluginPackage):Array<String> {
		final field = pkg.json.get("oc-themes");
		if (field == null)
			return [];
		if (!isArray(field))
			throw 'Plugin ${spec} has invalid oc-themes field';
		final out:Array<String> = [];
		final list:Array<Dynamic> = cast field;
		for (item in list) {
			if (!isString(item))
				throw 'Plugin ${spec} has invalid oc-themes entry';
			final raw = StringTools.trim(cast item);
			if (raw == "")
				throw 'Plugin ${spec} has empty oc-themes entry';
			if (StringTools.startsWith(raw, "file://") || isAbsolutePath(raw))
				throw 'Plugin ${spec} oc-themes entry must be relative: ${item}';
			out.push(NodePath.join(pkg.dir, raw));
		}
		return out;
	}

	static function packageEntrypoint(pkg:PluginPackage):String {
		final main = pkg.json.get("main");
		if (isString(main) && StringTools.trim(cast main) != "")
			return Url.pathToFileURL(NodePath.resolve(pkg.dir, cast main)).href;
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

	static function isString(value:Dynamic):Bool {
		// Package metadata is untrusted JSON. Haxe has no native unknown/string
		// guard, so keep the raw JS typeof check inside this decoder.
		return js.Syntax.code("typeof {0} === 'string'", value);
	}

	static function isArray(value:Dynamic):Bool {
		// See isString: this is a package metadata boundary guard.
		return js.Syntax.code("Array.isArray({0})", value);
	}

	static function isWindowsAbsolutePath(raw:String):Bool {
		if (raw.length < 3)
			return false;
		final drive = raw.charCodeAt(0);
		final letter = (drive >= 0x41 && drive <= 0x5A) || (drive >= 0x61 && drive <= 0x7A);
		return letter && raw.charAt(1) == ":" && (raw.charAt(2) == "\\" || raw.charAt(2) == "/");
	}
}
