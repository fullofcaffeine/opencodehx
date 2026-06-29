package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;

// Boundary debt: upstream plugin options are `Record<string, unknown>` passthrough
// data consumed by plugin packages. Keep the map contained and narrow once plugin
// manifests or package-specific schemas own these values.

typedef PluginOptionValue = Unknown;
typedef PluginOptions = haxe.DynamicAccess<PluginOptionValue>;

typedef PluginSpec = {
	final specifier:String;
	@:optional final options:PluginOptions;
}

enum abstract PluginScope(String) to String {
	var PluginScopeGlobal = "global";
	var PluginScopeLocal = "local";
}

typedef PluginOrigin = {
	final spec:PluginSpec;
	final source:String;
	final scope:PluginScope;
}

class ConfigPlugin {
	static final INDEX_FILES:Array<String> = ["index.ts", "index.tsx", "index.js", "index.mjs", "index.cjs"];

	public static function load(dir:String):Array<PluginSpec> {
		final result:Array<PluginSpec> = [];
		for (root in ["plugin", "plugins"]) {
			final base = NodePath.join(dir, root);
			if (!Fs.existsSync(base))
				continue;
			for (name in Fs.readdirNamesSync(base)) {
				final absolute = NodePath.join(base, name);
				final stat = Fs.statSync(absolute);
				if (stat.isFile() && isPluginFile(name))
					result.push({specifier: Url.pathToFileURL(absolute).href});
			}
		}
		result.sort((a, b) -> Reflect.compare(a.specifier, b.specifier));
		return result;
	}

	public static function specifier(spec:PluginSpec):String {
		return spec.specifier;
	}

	public static function optionsFromRecord(record:UnknownRecord):PluginOptions {
		final options = new haxe.DynamicAccess<PluginOptionValue>();
		for (key in record.keys())
			options.set(key, record.get(key));
		return options;
	}

	public static function stringOption(spec:PluginSpec, key:String):Null<String> {
		return spec.options == null ? null : UnknownNarrow.string(spec.options.get(key));
	}

	public static function boolOption(spec:PluginSpec, key:String):Null<Bool> {
		return spec.options == null ? null : UnknownNarrow.bool(spec.options.get(key));
	}

	public static function resolveSpec(spec:PluginSpec, configFilepath:String):PluginSpec {
		final raw = specifier(spec);
		if (!isPathSpec(raw))
			return spec;

		final base = NodePath.dirname(configFilepath);
		final file = if (StringTools.startsWith(raw, "file://")) {
			raw;
		} else if (isAbsolutePath(raw)) {
			Url.pathToFileURL(raw).href;
		} else {
			Url.pathToFileURL(NodePath.resolve(base, raw)).href;
		}

		final resolved = try {
			resolvePathPluginTarget(file);
		} catch (_:Dynamic) {
			file;
		}

		if (resolved == raw)
			return spec;
		if (spec.options == null)
			return {specifier: resolved};
		return {specifier: resolved, options: spec.options};
	}

	public static function resolvePathPluginTarget(spec:String):String {
		final startedAsFileUrl = StringTools.startsWith(spec, "file://");
		final raw = startedAsFileUrl ? Url.fileURLToPath(spec) : spec;
		final file = isAbsolutePath(raw) ? raw : NodePath.resolve(".", raw);
		final asUrl = startedAsFileUrl ? spec : Url.pathToFileURL(file).href;
		if (!Fs.existsSync(file))
			return asUrl;

		final stat = Fs.statSync(file);
		if (!stat.isDirectory())
			return asUrl;

		if (Fs.existsSync(NodePath.join(file, "package.json")))
			return Url.pathToFileURL(file).href;

		for (name in INDEX_FILES) {
			final index = NodePath.join(file, name);
			if (Fs.existsSync(index))
				return Url.pathToFileURL(index).href;
		}

		throw 'Plugin directory ${file} is missing package.json or index file';
	}

	public static function withOrigin(spec:PluginSpec, source:String, scope:PluginScope):PluginOrigin {
		return {
			spec: spec,
			source: source,
			scope: scope,
		};
	}

	public static function deduplicateOrigins(origins:Array<PluginOrigin>):Array<PluginOrigin> {
		final seen:Map<String, Bool> = [];
		final reversed:Array<PluginOrigin> = [];
		var index = origins.length - 1;
		while (index >= 0) {
			final origin = origins[index];
			final key = identity(origin.spec);
			if (!seen.exists(key)) {
				seen.set(key, true);
				reversed.push(origin);
			}
			index--;
		}
		reversed.reverse();
		return reversed;
	}

	static function identity(spec:PluginSpec):String {
		final raw = spec.specifier;
		if (StringTools.startsWith(raw, "file://"))
			return raw;
		return packageName(raw);
	}

	static function isPluginFile(name:String):Bool {
		return StringTools.endsWith(name, ".ts") || StringTools.endsWith(name, ".js");
	}

	static function isPathSpec(raw:String):Bool {
		return StringTools.startsWith(raw, "file://") || StringTools.startsWith(raw, ".") || isAbsolutePath(raw);
	}

	static function isAbsolutePath(raw:String):Bool {
		return NodePath.isAbsolute(raw) || isWindowsAbsolutePath(raw);
	}

	static function isWindowsAbsolutePath(raw:String):Bool {
		if (raw.length < 3)
			return false;
		final drive = raw.charCodeAt(0);
		final colon = raw.charAt(1) == ":";
		final slash = raw.charAt(2) == "\\" || raw.charAt(2) == "/";
		final letter = (drive >= 0x41 && drive <= 0x5A) || (drive >= 0x61 && drive <= 0x7A);
		return letter && colon && slash;
	}

	static function packageName(raw:String):String {
		final alias = raw.indexOf("npm:");
		if (alias != -1)
			return packageName(raw.substr(alias + 4));

		if (StringTools.startsWith(raw, "@")) {
			final slash = raw.indexOf("/");
			if (slash == -1)
				return raw;
			final version = raw.indexOf("@", slash + 1);
			return version == -1 ? raw : raw.substr(0, version);
		}

		final version = raw.indexOf("@");
		if (version > 0)
			return raw.substr(0, version);
		return raw;
	}
}
