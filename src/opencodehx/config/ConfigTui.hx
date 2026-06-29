package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.Json;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigPlugin.PluginOrigin;
import opencodehx.config.ConfigPlugin.PluginScope;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeGlobal;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeLocal;
import opencodehx.config.ConfigPlugin.PluginSpec;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

typedef TuiKeybinds = Map<String, String>;
typedef TuiPluginEnabled = Map<String, Bool>;

typedef TuiConfigInfo = {
	@:optional var theme:String;
	@:optional var scrollSpeed:Float;
	@:optional var diffStyle:String;
	var keybinds:TuiKeybinds;
	var plugin:Array<PluginSpec>;
	var pluginOrigins:Array<PluginOrigin>;
	var pluginEnabled:TuiPluginEnabled;
}

typedef TuiConfigOptions = {
	@:optional final globalConfigDir:String;
	@:optional final worktree:String;
}

private typedef TuiLayer = {
	@:optional var theme:String;
	@:optional var scrollSpeed:Float;
	@:optional var diffStyle:String;
	var keybinds:TuiKeybinds;
	final plugin:Array<PluginSpec>;
	final pluginEnabled:TuiPluginEnabled;
	var source:String;
	var scope:PluginScope;
}

/**
 * Focused TUI config loader.
 *
 * TUI config has its own files and legacy migration rules, so keep this module
 * separate from the server config loader. Parsed JSON is narrowed at the file
 * boundary into typed fields before the rest of the app sees it.
 */
class ConfigTui {
	public static function load(directory:String, ?options:TuiConfigOptions):TuiConfigInfo {
		final opts:TuiConfigOptions = options == null ? {} : options;
		migrateLegacy(directory, opts);

		final globalDir = opts.globalConfigDir == null
			|| opts.globalConfigDir == "" ? GlobalPaths.config(NodeProcess.env()) : opts.globalConfigDir;
		final result = empty();
		for (file in filesInDirectory(globalDir, "tui"))
			merge(result, loadFile(file, directory, scopeFor(directory, file), file));

		final custom = NodeProcess.envValue("OPENCODE_TUI_CONFIG");
		if (custom != null && custom != "")
			merge(result, loadFile(custom, directory, scopeFor(directory, custom), custom));

		for (dir in projectDirectories(directory, opts.worktree)) {
			for (file in filesInDirectory(dir, "tui"))
				merge(result, loadFile(file, directory, PluginScopeLocal, file));
		}
		for (dir in opencodeDirectories(directory, opts.worktree)) {
			for (file in filesInDirectory(dir, "tui"))
				merge(result, loadFile(file, directory, PluginScopeLocal, file));
		}
		return result;
	}

	static function empty():TuiConfigInfo {
		return {
			keybinds: [],
			plugin: [],
			pluginOrigins: [],
			pluginEnabled: [],
		};
	}

	static function merge(result:TuiConfigInfo, layer:TuiLayer):Void {
		if (layer.theme != null)
			result.theme = layer.theme;
		if (layer.scrollSpeed != null)
			result.scrollSpeed = layer.scrollSpeed;
		if (layer.diffStyle != null)
			result.diffStyle = layer.diffStyle;
		for (key => value in layer.keybinds)
			result.keybinds.set(key, value);
		for (key => value in layer.pluginEnabled)
			result.pluginEnabled.set(key, value);
		if (layer.plugin.length > 0) {
			final origins = result.pluginOrigins.concat([
				for (spec in layer.plugin)
					ConfigPlugin.withOrigin(spec, layer.source, layer.scope)
			]);
			result.pluginOrigins = ConfigPlugin.deduplicateOrigins(origins);
			result.plugin = [for (origin in result.pluginOrigins) origin.spec];
		}
	}

	static function loadFile(path:String, directory:String, scope:PluginScope, source:String):TuiLayer {
		try {
			final text = Fs.readFileSync(path, "utf8");
			final expanded = ConfigVariable.substitute(text, {dir: NodePath.dirname(path)});
			final record = UnknownNarrow.record(Unknown.fromBoundary(Jsonc.parse(expanded, path)));
			if (record == null)
				return emptyLayer(source, scope);
			final layer = decodeLayer(flattenNestedTui(record), path);
			layer.source = source;
			layer.scope = scope;
			return layer;
		} catch (_:ConfigException) {
			return emptyLayer(source, scope);
		} catch (_:haxe.Exception) {
			return emptyLayer(source, scope);
		}
	}

	static function emptyLayer(source:String, scope:PluginScope):TuiLayer {
		final layer:TuiLayer = {
			keybinds: [],
			plugin: [],
			pluginEnabled: [],
			source: source,
			scope: scope,
		};
		return layer;
	}

	static function decodeLayer(record:UnknownRecord, source:String):TuiLayer {
		return {
			theme: stringField(record, "theme"),
			scrollSpeed: numberField(record, "scroll_speed"),
			diffStyle: stringField(record, "diff_style"),
			keybinds: stringMap(recordField(record, "keybinds")),
			plugin: pluginList(arrayField(record, "plugin"), source),
			pluginEnabled: boolMap(recordField(record, "plugin_enabled")),
			source: source,
			scope: PluginScopeLocal,
		};
	}

	static function flattenNestedTui(record:UnknownRecord):UnknownRecord {
		final nested = recordField(record, "tui");
		if (nested == null)
			return record;
		final merged = new Map<String, Unknown>();
		for (key in nested.keys())
			merged.set(key, nested.get(key));
		for (key in record.keys()) {
			if (key != "tui")
				merged.set(key, record.get(key));
		}
		return requireRecord(mapToObjectJson(merged));
	}

	static function mapToObjectJson(map:Map<String, Unknown>):Unknown {
		final fields:Array<String> = [];
		final keys:Array<String> = [];
		for (key in map.keys())
			keys.push(key);
		keys.sort(Reflect.compare);
		for (key in keys)
			fields.push(Json.stringify(key) + ":" + Json.stringify(map.get(key)));
		return Unknown.fromBoundary(Json.parse("{" + fields.join(",") + "}"));
	}

	static function requireRecord(value:Unknown):UnknownRecord {
		final record = UnknownNarrow.record(value);
		if (record == null)
			throw "expected generated object";
		return record;
	}

	static function pluginList(items:Null<UnknownArray>, source:String):Array<PluginSpec> {
		final out:Array<PluginSpec> = [];
		if (items == null)
			return out;
		for (index in 0...items.length) {
			final spec = pluginSpec(items.get(index));
			if (spec != null)
				out.push(ConfigPlugin.resolveSpec(spec, source));
		}
		return out;
	}

	static function pluginSpec(value:Unknown):Null<PluginSpec> {
		final specifier = UnknownNarrow.string(value);
		if (specifier != null)
			return {specifier: specifier};

		final tuple = UnknownNarrow.array(value);
		if (tuple == null || tuple.length != 2)
			return null;
		final tupleSpecifier = UnknownNarrow.string(tuple.get(0));
		final tupleOptions = UnknownNarrow.record(tuple.get(1));
		if (tupleSpecifier == null || tupleOptions == null)
			return null;
		return {
			specifier: tupleSpecifier,
			options: ConfigPlugin.optionsFromRecord(tupleOptions),
		};
	}

	static function stringMap(record:Null<UnknownRecord>):TuiKeybinds {
		final out:TuiKeybinds = [];
		if (record == null)
			return out;
		for (key in record.keys()) {
			final value = UnknownNarrow.string(record.get(key));
			if (value != null)
				out.set(key, value);
		}
		return out;
	}

	static function boolMap(record:Null<UnknownRecord>):TuiPluginEnabled {
		final out:TuiPluginEnabled = [];
		if (record == null)
			return out;
		for (key in record.keys()) {
			final value = UnknownNarrow.bool(record.get(key));
			if (value != null)
				out.set(key, value);
		}
		return out;
	}

	static function migrateLegacy(directory:String, options:TuiConfigOptions):Void {
		for (dir in projectDirectories(directory, options.worktree)) {
			if (hasTuiFile(dir))
				continue;
			final source = existingConfigFile(dir, "opencode");
			if (source == null)
				continue;
			migrateLegacyFile(source, NodePath.join(dir, "tui.json"));
		}
	}

	static function migrateLegacyFile(source:String, target:String):Void {
		final text = try Fs.readFileSync(source, "utf8") catch (_:haxe.Exception) return;
		final record = try UnknownNarrow.record(Unknown.fromBoundary(Jsonc.parse(text, source))) catch (_:haxe.Exception) null;
		if (record == null)
			return;
		final layer = legacyLayer(record, source);
		if (!hasLegacy(layer))
			return;
		writeJson(target, tuiJson(layer));
		try {
			Fs.writeFileSync(source + ".tui-migration.bak", text);
			Fs.writeFileSync(source, strippedJson(record));
		} catch (_:haxe.Exception) {}
	}

	static function legacyLayer(record:UnknownRecord, source:String):TuiLayer {
		final tui = recordField(record, "tui");
		final layer = emptyLayer(source, PluginScopeLocal);
		if (record.hasOwn("theme"))
			layer.theme = stringField(record, "theme");
		if (record.hasOwn("keybinds"))
			layer.keybinds = stringMap(recordField(record, "keybinds"));
		if (tui != null) {
			layer.scrollSpeed = numberField(tui, "scroll_speed");
			layer.diffStyle = stringField(tui, "diff_style");
		}
		return layer;
	}

	static function hasLegacy(layer:TuiLayer):Bool {
		return layer.theme != null || layer.scrollSpeed != null || layer.diffStyle != null || hasStringEntries(layer.keybinds);
	}

	static function tuiJson(layer:TuiLayer):String {
		final fields:Array<String> = [];
		if (layer.theme != null)
			fields.push('"theme": ' + Json.stringify(layer.theme));
		if (layer.scrollSpeed != null)
			fields.push('"scroll_speed": ' + Std.string(layer.scrollSpeed));
		if (layer.diffStyle != null)
			fields.push('"diff_style": ' + Json.stringify(layer.diffStyle));
		if (hasStringEntries(layer.keybinds))
			fields.push('"keybinds": ' + stringMapJson(layer.keybinds));
		return "{\n  " + fields.join(",\n  ") + "\n}\n";
	}

	static function strippedJson(record:UnknownRecord):String {
		final fields:Array<String> = [];
		final keys = record.keys();
		keys.sort(Reflect.compare);
		for (key in keys) {
			if (key == "theme" || key == "keybinds" || key == "tui")
				continue;
			fields.push(Json.stringify(key) + ": " + Json.stringify(record.get(key)));
		}
		return fields.length == 0 ? "{}\n" : "{\n  " + fields.join(",\n  ") + "\n}\n";
	}

	static function stringMapJson(map:TuiKeybinds):String {
		final fields:Array<String> = [];
		final keys:Array<String> = [];
		for (key in map.keys())
			keys.push(key);
		keys.sort(Reflect.compare);
		for (key in keys)
			fields.push(Json.stringify(key) + ": " + Json.stringify(map.get(key)));
		return "{" + fields.join(", ") + "}";
	}

	static function hasStringEntries(map:TuiKeybinds):Bool {
		for (_ in map.keys())
			return true;
		return false;
	}

	static function writeJson(path:String, text:String):Void {
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, text);
	}

	static function stringField(record:UnknownRecord, field:String):Null<String> {
		if (!record.hasOwn(field))
			return null;
		return UnknownNarrow.string(record.get(field));
	}

	static function numberField(record:UnknownRecord, field:String):Null<Float> {
		if (!record.hasOwn(field))
			return null;
		return UnknownNarrow.number(record.get(field));
	}

	static function recordField(record:UnknownRecord, field:String):Null<UnknownRecord> {
		return record.hasOwn(field) ? UnknownNarrow.record(record.get(field)) : null;
	}

	static function arrayField(record:UnknownRecord, field:String):Null<UnknownArray> {
		return record.hasOwn(field) ? UnknownNarrow.array(record.get(field)) : null;
	}

	static function hasTuiFile(dir:String):Bool {
		return existingConfigFile(dir, "tui") != null;
	}

	static function existingConfigFile(dir:String, name:String):Null<String> {
		for (ext in ["json", "jsonc"]) {
			final path = NodePath.join(dir, name + "." + ext);
			if (Fs.existsSync(path))
				return path;
		}
		return null;
	}

	static function filesInDirectory(dir:String, name:String):Array<String> {
		final out:Array<String> = [];
		for (ext in ["json", "jsonc"]) {
			final path = NodePath.join(dir, name + "." + ext);
			if (Fs.existsSync(path))
				out.push(path);
		}
		return out;
	}

	static function projectDirectories(directory:String, ?worktree:String):Array<String> {
		final dirs = ancestors(directory, worktree);
		dirs.reverse();
		return dirs;
	}

	static function opencodeDirectories(directory:String, ?worktree:String):Array<String> {
		final out:Array<String> = [];
		for (dir in projectDirectories(directory, worktree)) {
			final opencode = NodePath.join(dir, ".opencode");
			if (Fs.existsSync(opencode))
				out.push(opencode);
		}
		return out;
	}

	static function ancestors(directory:String, ?worktree:String):Array<String> {
		final out:Array<String> = [];
		var current = NodePath.resolve(directory, "");
		final stop = worktree == null || worktree == "" ? null : NodePath.resolve(worktree, "");
		while (true) {
			out.push(current);
			if (stop != null && current == stop)
				break;
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		return out;
	}

	static function scopeFor(directory:String, file:String):PluginScope {
		final normalizedDir = NodePath.resolve(directory, "");
		final normalizedFile = NodePath.resolve(file, "");
		return normalizedFile == normalizedDir
			|| StringTools.startsWith(normalizedFile, normalizedDir + "/") ? PluginScopeLocal : PluginScopeGlobal;
	}
}
