package opencodehx.config;

import haxe.DynamicAccess;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;

// Boundary debt: upstream plugin options are `Record<string, unknown>` passthrough
// data consumed by plugin packages. Keep the map contained and narrow once plugin
// manifests or package-specific schemas own these values.

@:ts.type("unknown")
abstract PluginOptionValue(Dynamic) from Dynamic to Dynamic {}

typedef PluginOptions = DynamicAccess<PluginOptionValue>;

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
