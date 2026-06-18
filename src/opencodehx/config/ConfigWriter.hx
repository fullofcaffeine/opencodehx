package opencodehx.config;

import genes.ts.Unknown;
import haxe.Json;
import haxe.DynamicAccess;
import opencodehx.config.ConfigLoader.LoadOptions;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ServerConfig;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigPlugin.PluginScope;
import opencodehx.config.ConfigPlugin.PluginSpec;
import opencodehx.externs.jsonc.JsoncParser;
import opencodehx.externs.node.Fs;
import opencodehx.externs.toml.Toml;
import opencodehx.externs.toml.TomlObject;
import opencodehx.externs.toml.TomlObject.TomlValue;
import opencodehx.host.node.NodePath;

// Boundary debt: config updates must round-trip arbitrary JSON/JSONC subtrees for
// schemas whose owning modules are not ported yet. Keep this raw tree contained
// in ConfigWriter and replace fields with precise typedefs as those slices land.

typedef WritableConfigJson = Unknown;
typedef WritableConfigObject = DynamicAccess<WritableConfigJson>;

class ConfigWriter {
	public static function loadGlobal(globalDir:String, ?options:LoadOptions):ConfigInfo {
		final result = new ConfigInfo();
		for (file in ["config.json", "opencode.json", "opencode.jsonc"]) {
			final path = NodePath.join(globalDir, file);
			if (Fs.existsSync(path))
				result.merge(ConfigLoader.loadFile(path, withGlobalScope(options)));
		}
		migrateLegacyToml(globalDir, result, options);
		return result;
	}

	public static function updateLocal(directory:String, patch:ConfigInfo, ?options:LoadOptions):ConfigInfo {
		final file = NodePath.join(directory, "config.json");
		final before = Fs.existsSync(file) ? Fs.readFileSync(file, "utf8") : "{}";
		final merged = mergeWritable(parseWritable(before, file), writableDynamic(patch));
		final updated = Json.stringify(merged, null, "  ");
		Fs.writeFileSync(file, updated);
		return ConfigLoader.loadParsedData(Jsonc.parse(updated, file), file, withLocalScope(options));
	}

	public static function updateGlobal(globalDir:String, patch:ConfigInfo, ?options:LoadOptions):ConfigInfo {
		final file = globalConfigFile(globalDir);
		final before = Fs.existsSync(file) ? Fs.readFileSync(file, "utf8") : "{}";
		final patchData = writableDynamic(patch);
		final updated = StringTools.endsWith(file,
			".jsonc") ? patchJsonc(before, patchData) : Json.stringify(mergeWritable(parseWritable(before, file), patchData), null, "  ");

		Fs.writeFileSync(file, updated);
		return ConfigLoader.loadParsedData(Jsonc.parse(updated, file), file, withGlobalScope(options));
	}

	public static function globalConfigFile(globalDir:String):String {
		final candidates = [
			NodePath.join(globalDir, "opencode.jsonc"),
			NodePath.join(globalDir, "opencode.json"),
			NodePath.join(globalDir, "config.json"),
		];
		for (file in candidates) {
			if (Fs.existsSync(file))
				return file;
		}
		return candidates[0];
	}

	static function parseWritable(text:String, file:String):WritableConfigJson {
		final existing = ConfigLoader.loadParsedData(Jsonc.parse(text, file), file);
		return writableDynamic(existing);
	}

	static function migrateLegacyToml(globalDir:String, result:ConfigInfo, ?options:LoadOptions):Void {
		final legacy = NodePath.join(globalDir, "config");
		if (!Fs.existsSync(legacy))
			return;
		try {
			// Legacy OpenCode config used extensionless TOML. The parsed object is kept
			// at this migration boundary, then normalized into ConfigInfo immediately.
			final parsed:TomlObject = Toml.parse(Fs.readFileSync(legacy, "utf8"));
			final provider = tomlString(parsed.get("provider"));
			final model = tomlString(parsed.get("model"));
			parsed.remove("provider");
			parsed.remove("model");
			parsed.set("$schema", Unknown.fromBoundary(ConfigInfo.DEFAULT_SCHEMA));
			if (provider != null && model != null)
				parsed.set("model", Unknown.fromBoundary(provider + "/" + model));

			result.merge(ConfigLoader.loadParsedData(parsed, legacy, withGlobalScope(options)));
			Fs.writeFileSync(NodePath.join(globalDir, "config.json"), Json.stringify(writableDynamic(result), null, "  "));
			Fs.unlinkSync(legacy);
		} catch (_:Dynamic) {
			// Upstream treats legacy migration as best-effort and falls back to the
			// already loaded JSON/JSONC global config if TOML parsing or writing fails.
		}
	}

	static function tomlString(value:Null<TomlValue>):Null<String> {
		if (Std.isOfType(value, String))
			return cast value;
		return null;
	}

	static function patchJsonc(input:String, patch:WritableConfigJson, ?path:Array<String>):String {
		final target = path == null ? [] : path;
		if (!isRecord(patch)) {
			final edits = JsoncParser.modify(input, target, patch, {
				formattingOptions: {
					insertSpaces: true,
					tabSize: 2,
				},
			});
			return JsoncParser.applyEdits(input, edits);
		}

		var result = input;
		for (field in Reflect.fields(patch)) {
			final nextPath = target.concat([field]);
			result = patchJsonc(result, Reflect.field(patch, field), nextPath);
		}
		return result;
	}

	static function mergeWritable(current:WritableConfigJson, patch:WritableConfigJson):WritableConfigJson {
		if (!isRecord(current) || !isRecord(patch))
			return patch;

		final result:WritableConfigObject = {};
		for (field in Reflect.fields(current)) {
			result.set(field, cast Reflect.field(current, field));
		}
		for (field in Reflect.fields(patch)) {
			final currentValue:WritableConfigJson = result.get(field);
			final patchValue:WritableConfigJson = cast Reflect.field(patch, field);
			result.set(field, mergeWritable(currentValue, patchValue));
		}
		return Unknown.fromBoundary(result);
	}

	static function writableDynamic(info:ConfigInfo):WritableConfigJson {
		final out:WritableConfigObject = {};
		set(out, "$schema", info.schema);
		set(out, "logLevel", info.logLevel);
		set(out, "server", serverDynamic(info.server));
		set(out, "command", info.command);
		set(out, "skills", info.skills);
		set(out, "watcher", info.watcher);
		set(out, "snapshot", info.snapshot);
		if (info.plugin.length > 0) {
			final plugins:Array<WritableConfigJson> = [];
			for (spec in info.plugin)
				plugins.push(pluginDynamic(spec));
			set(out, "plugin", plugins);
		}
		set(out, "share", shareString(info.share));
		set(out, "autoshare", info.autoshare);
		set(out, "autoupdate", autoUpdateDynamic(info.autoupdate));
		set(out, "disabled_providers", info.disabledProviders);
		set(out, "enabled_providers", info.enabledProviders);
		set(out, "model", info.model);
		set(out, "small_model", info.smallModel);
		set(out, "default_agent", info.defaultAgent);
		set(out, "username", info.username);
		set(out, "mode", info.mode);
		set(out, "agent", info.agent);
		set(out, "provider", info.provider);
		set(out, "mcp", info.mcp);
		set(out, "formatter", info.formatter);
		set(out, "lsp", info.lsp);
		set(out, "instructions", info.instructions);
		set(out, "layout", info.layout);
		set(out, "permission", info.permission);
		set(out, "tools", info.tools);
		set(out, "enterprise", info.enterprise);
		set(out, "compaction", info.compaction);
		set(out, "experimental", info.experimental);
		// `out` was assembled from typed ConfigInfo fields, but config-file JSON is
		// still an open tree while not every nested section has an owner schema.
		// Unknown.fromBoundary marks the single handoff into WritableConfigJson
		// (`unknown` in generated TS) so callers must narrow again before reading.
		return Unknown.fromBoundary(out);
	}

	static function serverDynamic(server:Null<ServerConfig>):WritableConfigJson {
		if (server == null)
			return Unknown.fromBoundary(null);
		final out:WritableConfigObject = {};
		set(out, "port", server.port);
		set(out, "hostname", server.hostname);
		set(out, "mdns", server.mdns);
		set(out, "mdnsDomain", server.mdnsDomain);
		set(out, "cors", server.cors);
		return Unknown.fromBoundary(out);
	}

	static function pluginDynamic(spec:PluginSpec):WritableConfigJson {
		if (spec.options == null)
			return Unknown.fromBoundary(spec.specifier);
		final tuple:Array<WritableConfigJson> = [Unknown.fromBoundary(spec.specifier), Unknown.fromBoundary(spec.options)];
		return Unknown.fromBoundary(tuple);
	}

	static function shareString(value:Null<ShareMode>):Null<String> {
		return switch value {
			case null: null;
			case ShareManual: "manual";
			case ShareAuto: "auto";
			case ShareDisabled: "disabled";
		}
	}

	static function autoUpdateDynamic(value:Null<AutoUpdate>):WritableConfigJson {
		return switch value {
			case null: Unknown.fromBoundary(null);
			case AutoUpdateEnabled: Unknown.fromBoundary(true);
			case AutoUpdateDisabled: Unknown.fromBoundary(false);
			case AutoUpdateNotify: Unknown.fromBoundary("notify");
		}
	}

	static function set<T>(target:WritableConfigObject, field:String, value:T):Void {
		// Generic Haxe values need one null check before entering the open JSON
		// writer tree; the stored value itself is wrapped as WritableConfigJson.
		final rawValue:Dynamic = cast value;
		if (rawValue != null)
			target.set(field, Unknown.fromBoundary(value));
	}

	static function isRecord(value:WritableConfigJson):Bool {
		// WritableConfigJson is generated as TS `unknown`; runtime reflection is
		// contained here to decide whether JSONC patching should recurse.
		final rawValue:Dynamic = cast value;
		if (rawValue == null || Std.isOfType(rawValue, Array))
			return false;
		if (Std.isOfType(rawValue, String)
			|| Std.isOfType(rawValue, Bool)
			|| Std.isOfType(rawValue, Float)
			|| Std.isOfType(rawValue, Int))
			return false;
		return Reflect.isObject(rawValue);
	}

	static function withGlobalScope(?options:LoadOptions):LoadOptions {
		return withScope(options, PluginScopeGlobal);
	}

	static function withLocalScope(?options:LoadOptions):LoadOptions {
		return withScope(options, PluginScopeLocal);
	}

	static function withScope(?options:LoadOptions, scope:PluginScope):LoadOptions {
		final opts:LoadOptions = options == null ? {} : options;
		return {
			env: opts.env,
			defaultUsername: opts.defaultUsername,
			worktree: opts.worktree,
			pluginScope: scope,
		};
	}
}
