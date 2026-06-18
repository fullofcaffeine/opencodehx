package opencodehx.config;

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
import opencodehx.host.node.NodePath;

// Boundary debt: config updates must round-trip arbitrary JSON/JSONC subtrees for
// schemas whose owning modules are not ported yet. Keep this raw tree contained
// in ConfigWriter and replace fields with precise typedefs as those slices land.

@:ts.type("unknown")
abstract WritableConfigJson(Dynamic) from Dynamic to Dynamic {}

typedef WritableConfigObject = DynamicAccess<WritableConfigJson>;

class ConfigWriter {
	public static function loadGlobal(globalDir:String, ?options:LoadOptions):ConfigInfo {
		final result = new ConfigInfo();
		for (file in ["config.json", "opencode.json", "opencode.jsonc"]) {
			final path = NodePath.join(globalDir, file);
			if (Fs.existsSync(path))
				result.merge(ConfigLoader.loadFile(path, withGlobalScope(options)));
		}
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
		return cast result;
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
		return cast out;
	}

	static function serverDynamic(server:Null<ServerConfig>):WritableConfigJson {
		if (server == null)
			return null;
		final out:WritableConfigObject = {};
		set(out, "port", server.port);
		set(out, "hostname", server.hostname);
		set(out, "mdns", server.mdns);
		set(out, "mdnsDomain", server.mdnsDomain);
		set(out, "cors", server.cors);
		return cast out;
	}

	static function pluginDynamic(spec:PluginSpec):WritableConfigJson {
		if (spec.options == null)
			return spec.specifier;
		return [spec.specifier, spec.options];
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
			case null: null;
			case AutoUpdateEnabled: true;
			case AutoUpdateDisabled: false;
			case AutoUpdateNotify: "notify";
		}
	}

	static function set(target:WritableConfigObject, field:String, value:WritableConfigJson):Void {
		if (value != null)
			target.set(field, value);
	}

	static function isRecord(value:WritableConfigJson):Bool {
		if (value == null || Std.isOfType(value, Array))
			return false;
		if (Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return false;
		return Reflect.isObject(value);
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
