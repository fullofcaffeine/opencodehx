package opencodehx.config;

import haxe.ds.ReadOnlyArray;
import js.Syntax;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ServerConfig;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigPlugin.PluginScope;
import opencodehx.config.ConfigPlugin.PluginSpec;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;

typedef LoadOptions = {
	@:optional final env:Dynamic;
	@:optional final defaultUsername:String;
	@:optional final worktree:String;
	@:optional final pluginScope:PluginScope;
}

class ConfigLoader {
	static final ALLOWED:ReadOnlyArray<String> = [
		"$schema",
		"logLevel",
		"server",
		"command",
		"skills",
		"watcher",
		"snapshot",
		"plugin",
		"share",
		"autoshare",
		"autoupdate",
		"disabled_providers",
		"enabled_providers",
		"model",
		"small_model",
		"default_agent",
		"username",
		"mode",
		"agent",
		"provider",
		"mcp",
		"formatter",
		"lsp",
		"instructions",
		"layout",
		"permission",
		"tools",
		"enterprise",
		"compaction",
		"experimental",
	];

	static final LEGACY_TUI:ReadOnlyArray<String> = ["theme", "keybinds", "tui"];

	public static function loadProject(directory:String, ?options:LoadOptions):ConfigInfo {
		final opts:LoadOptions = options == null ? {} : options;
		final result = ConfigInfo.empty(defaultUsername(opts));
		final customPath = envValue(opts, "OPENCODE_CONFIG");
		if (customPath != null && customPath != "")
			result.merge(loadFile(customPath, opts));

		if (!projectConfigDisabled(opts)) {
			for (dir in projectDirectories(directory, opts.worktree)) {
				mergeConfigFiles(result, dir, withPluginScope(opts, PluginScopeLocal));
			}
			for (dir in opencodeDirectories(directory, opts.worktree)) {
				mergeConfigFiles(result, dir, withPluginScope(opts, PluginScopeLocal));
			}
		}

		final configDir = envValue(opts, "OPENCODE_CONFIG_DIR");
		if (configDir != null && configDir != "") {
			mergeConfigFiles(result, configDir, withPluginScope(opts, PluginScopeGlobal));
		}

		final content = envValue(opts, "OPENCODE_CONFIG_CONTENT");
		if (content != null && content != "") {
			result.merge(loadText(content, "OPENCODE_CONFIG_CONTENT", directory, withPluginScope(opts, PluginScopeLocal)));
		}
		return result;
	}

	static function mergeConfigFiles(result:ConfigInfo, directory:String, options:LoadOptions):Void {
		for (file in ["opencode.json", "opencode.jsonc"]) {
			final path = NodePath.join(directory, file);
			if (Fs.existsSync(path))
				result.merge(loadFile(path, options));
		}
	}

	static function projectDirectories(directory:String, ?worktree:String):Array<String> {
		final dirs = ancestors(directory, worktree);
		dirs.reverse();
		return dirs;
	}

	static function opencodeDirectories(directory:String, ?worktree:String):Array<String> {
		final result:Array<String> = [];
		for (dir in projectDirectories(directory, worktree)) {
			final opencodeDir = NodePath.join(dir, ".opencode");
			if (Fs.existsSync(opencodeDir))
				result.push(opencodeDir);
		}
		return result;
	}

	static function ancestors(directory:String, ?worktree:String):Array<String> {
		final result:Array<String> = [];
		var current = NodePath.resolve(directory, "");
		final stop = worktree == null || worktree == "" ? null : NodePath.resolve(worktree, "");
		while (true) {
			result.push(current);
			if (stop != null && current == stop)
				break;
			final parent = NodePath.dirname(current);
			if (parent == current)
				break;
			current = parent;
		}
		return result;
	}

	static function projectConfigDisabled(options:LoadOptions):Bool {
		final value = envValue(options, "OPENCODE_DISABLE_PROJECT_CONFIG");
		return value != null && value != "" && value != "0" && value != "false";
	}

	public static function loadFile(path:String, ?options:LoadOptions):ConfigInfo {
		try {
			final text = Fs.readFileSync(path, "utf8");
			final info = loadText(text, path, NodePath.dirname(path), options);
			ensureSchema(path, text, info);
			return info;
		} catch (configError:ConfigException) {
			throw configError;
		} catch (ioError:Dynamic) {
			throw new ConfigException(IoError(path, Std.string(ioError)));
		}
	}

	static function ensureSchema(path:String, text:String, info:ConfigInfo):Void {
		if (info.schema != null)
			return;
		info.schema = ConfigInfo.DEFAULT_SCHEMA;
		try {
			Fs.writeFileSync(path, addDefaultSchema(text), "utf8");
		} catch (writeError:Dynamic) {
			// Node fs write errors are intentionally swallowed here to match upstream's
			// best-effort schema write-back while preserving successful config loading.
		}
	}

	static function addDefaultSchema(text:String):String {
		final brace = firstRootObjectBrace(text);
		if (brace == -1)
			return text;
		return text.substr(0, brace + 1) + '\n  "' + "$" + 'schema": "${ConfigInfo.DEFAULT_SCHEMA}",' + text.substr(brace + 1);
	}

	static function firstRootObjectBrace(text:String):Int {
		var index = 0;
		while (index < text.length) {
			final code = text.charCodeAt(index);
			if (!isJsonWhitespace(code))
				return text.charAt(index) == "{" ? index : -1;
			index++;
		}
		return -1;
	}

	static inline function isJsonWhitespace(code:Int):Bool {
		return code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0D;
	}

	public static function loadText(text:String, source:String, directory:String, ?options:LoadOptions):ConfigInfo {
		final opts:LoadOptions = options == null ? {} : options;
		final expanded = ConfigVariable.substitute(text, {dir: directory, env: opts.env});
		final data = Jsonc.parse(expanded, source);
		return fromDynamic(normalizeLegacyTui(data), source, pluginScope(opts));
	}

	static function fromDynamic(data:Dynamic, source:String, scope:PluginScope):ConfigInfo {
		if (!Reflect.isObject(data) || Std.isOfType(data, Array)) {
			throw new ConfigException(InvalidError(source, ["Expected config root to be an object"]));
		}

		final issues = [];
		for (field in Reflect.fields(data)) {
			if (ALLOWED.indexOf(field) == -1)
				issues.push('Unrecognized key: "${field}"');
		}
		if (issues.length > 0)
			throw new ConfigException(InvalidError(source, issues));

		final info = new ConfigInfo();
		info.schema = optionalString(data, "$schema", source, issues);
		info.logLevel = optionalString(data, "logLevel", source, issues);
		info.server = optionalServer(data, source, issues);
		info.command = optionalAny(data, "command");
		info.skills = optionalAny(data, "skills");
		info.watcher = optionalAny(data, "watcher");
		info.snapshot = optionalBool(data, "snapshot", source, issues);
		info.plugin = optionalPluginArray(data, "plugin", source, issues);
		info.pluginOrigins = [for (spec in info.plugin) ConfigPlugin.withOrigin(spec, source, scope)];
		info.share = optionalShare(data, source, issues);
		info.autoshare = optionalBool(data, "autoshare", source, issues);
		info.autoupdate = optionalAutoUpdate(data, source, issues);
		info.disabledProviders = optionalStringArray(data, "disabled_providers", source, issues);
		info.enabledProviders = optionalStringArray(data, "enabled_providers", source, issues);
		info.model = optionalString(data, "model", source, issues);
		info.smallModel = optionalString(data, "small_model", source, issues);
		info.defaultAgent = optionalString(data, "default_agent", source, issues);
		info.username = optionalString(data, "username", source, issues);
		info.mode = optionalAny(data, "mode");
		info.agent = optionalAny(data, "agent");
		info.provider = optionalObject(data, "provider", issues);
		info.mcp = optionalAny(data, "mcp");
		info.formatter = optionalAny(data, "formatter");
		info.lsp = optionalAny(data, "lsp");
		info.instructions = optionalStringArray(data, "instructions", source, issues);
		info.layout = optionalAny(data, "layout");
		info.permission = optionalObject(data, "permission", issues);
		info.tools = optionalAny(data, "tools");
		info.enterprise = optionalAny(data, "enterprise");
		info.compaction = optionalAny(data, "compaction");
		info.experimental = optionalAny(data, "experimental");

		if (issues.length > 0)
			throw new ConfigException(InvalidError(source, issues));
		return info;
	}

	static function normalizeLegacyTui(data:Dynamic):Dynamic {
		if (!Reflect.isObject(data))
			return data;
		for (field in LEGACY_TUI) {
			if (Reflect.hasField(data, field))
				Reflect.deleteField(data, field);
		}
		return data;
	}

	static function optionalAny(data:Dynamic, field:String):Dynamic {
		return Reflect.hasField(data, field) ? Reflect.field(data, field) : null;
	}

	static function optionalObject<T>(data:Dynamic, field:String, issues:Array<String>):Null<haxe.DynamicAccess<T>> {
		if (!Reflect.hasField(data, field))
			return null;
		final value = Reflect.field(data, field);
		if (value != null && Reflect.isObject(value) && !Std.isOfType(value, Array))
			return cast value;
		issues.push('${field}: expected object');
		return null;
	}

	static function optionalString(data:Dynamic, field:String, source:String, issues:Array<String>):Null<String> {
		if (!Reflect.hasField(data, field))
			return null;
		final value = Reflect.field(data, field);
		if (Std.isOfType(value, String))
			return value;
		issues.push('${field}: expected string');
		return null;
	}

	static function optionalBool(data:Dynamic, field:String, source:String, issues:Array<String>):Null<Bool> {
		if (!Reflect.hasField(data, field))
			return null;
		final value = Reflect.field(data, field);
		if (Std.isOfType(value, Bool))
			return value;
		issues.push('${field}: expected boolean');
		return null;
	}

	static function optionalArrayAny(data:Dynamic, field:String, source:String, issues:Array<String>):Array<Dynamic> {
		if (!Reflect.hasField(data, field))
			return [];
		final value = Reflect.field(data, field);
		if (Std.isOfType(value, Array))
			return cast value;
		issues.push('${field}: expected array');
		return [];
	}

	static function optionalPluginArray(data:Dynamic, field:String, source:String, issues:Array<String>):Array<PluginSpec> {
		if (!Reflect.hasField(data, field))
			return [];
		final value = Reflect.field(data, field);
		if (!Std.isOfType(value, Array)) {
			issues.push('${field}: expected array');
			return [];
		}
		final result:Array<PluginSpec> = [];
		final items:Array<Dynamic> = cast value;
		for (index in 0...items.length) {
			final spec = pluginSpec(items[index], '${field}[${index}]', issues);
			if (spec != null)
				result.push(spec);
		}
		return result;
	}

	static function pluginSpec(value:Dynamic, label:String, issues:Array<String>):Null<PluginSpec> {
		if (Std.isOfType(value, String))
			return {specifier: value};
		if (Std.isOfType(value, Array)) {
			final tuple:Array<Dynamic> = cast value;
			if (tuple.length != 2) {
				issues.push('${label}: expected [specifier, options]');
				return null;
			}
			if (!Std.isOfType(tuple[0], String)) {
				issues.push('${label}[0]: expected string');
				return null;
			}
			if (tuple[1] == null || !Reflect.isObject(tuple[1]) || Std.isOfType(tuple[1], Array)) {
				issues.push('${label}[1]: expected object');
				return null;
			}
			return {specifier: tuple[0], options: cast tuple[1]};
		}
		issues.push('${label}: expected string or [specifier, options]');
		return null;
	}

	static function optionalStringArray(data:Dynamic, field:String, source:String, issues:Array<String>):Null<Array<String>> {
		if (!Reflect.hasField(data, field))
			return null;
		final value = Reflect.field(data, field);
		if (!Std.isOfType(value, Array)) {
			issues.push('${field}: expected array');
			return null;
		}
		final result:Array<String> = [];
		for (item in (cast value : Array<Dynamic>)) {
			if (Std.isOfType(item, String)) {
				result.push(item);
			} else {
				issues.push('${field}: expected string entries');
			}
		}
		return result;
	}

	static function optionalShare(data:Dynamic, source:String, issues:Array<String>):Null<ShareMode> {
		if (!Reflect.hasField(data, "share"))
			return null;
		return switch Reflect.field(data, "share") {
			case "manual": ShareManual;
			case "auto": ShareAuto;
			case "disabled": ShareDisabled;
			case value:
				issues.push('share: expected "manual", "auto", or "disabled"; got ${Std.string(value)}');
				null;
		}
	}

	static function optionalAutoUpdate(data:Dynamic, source:String, issues:Array<String>):Null<AutoUpdate> {
		if (!Reflect.hasField(data, "autoupdate"))
			return null;
		final value = Reflect.field(data, "autoupdate");
		if (Std.isOfType(value, Bool))
			return value ? AutoUpdateEnabled : AutoUpdateDisabled;
		final text = Std.string(value);
		if (text == "notify")
			return AutoUpdateNotify;
		issues.push('autoupdate: expected boolean or "notify"; got ${text}');
		return null;
	}

	static function optionalServer(data:Dynamic, source:String, issues:Array<String>):Null<ServerConfig> {
		if (!Reflect.hasField(data, "server"))
			return null;
		final value = Reflect.field(data, "server");
		if (!Reflect.isObject(value) || Std.isOfType(value, Array)) {
			issues.push("server: expected object");
			return null;
		}
		final serverIssues = [];
		for (field in Reflect.fields(value)) {
			if (["port", "hostname", "mdns", "mdnsDomain", "cors"].indexOf(field) == -1) {
				serverIssues.push('server.${field}: unrecognized key');
			}
		}
		final port = optionalInt(value, "port", serverIssues);
		if (port != null && port <= 0)
			serverIssues.push("server.port: expected positive integer");
		final hostname = optionalString(value, "hostname", source, serverIssues);
		final mdns = optionalBool(value, "mdns", source, serverIssues);
		final mdnsDomain = optionalString(value, "mdnsDomain", source, serverIssues);
		final cors = optionalStringArray(value, "cors", source, serverIssues);
		for (issue in serverIssues)
			issues.push(issue);
		return {
			port: port,
			hostname: hostname,
			mdns: mdns,
			mdnsDomain: mdnsDomain,
			cors: cors,
		};
	}

	static function optionalInt(data:Dynamic, field:String, issues:Array<String>):Null<Int> {
		if (!Reflect.hasField(data, field))
			return null;
		final value = Reflect.field(data, field);
		if (Std.isOfType(value, Int))
			return value;
		if (Std.isOfType(value, Float) && Math.floor(value) == value)
			return Std.int(value);
		issues.push('${field}: expected integer');
		return null;
	}

	static function defaultUsername(options:LoadOptions):String {
		if (options.defaultUsername != null)
			return options.defaultUsername;
		try {
			return Os.userInfo().username;
		} catch (_:Dynamic) {
			final fromEnv = envValue(options, "USER");
			return fromEnv == null || fromEnv == "" ? "user" : fromEnv;
		}
	}

	static function envValue(options:LoadOptions, key:String):Null<String> {
		if (options.env != null && Reflect.hasField(options.env, key)) {
			final value = Reflect.field(options.env, key);
			return value == null ? null : Std.string(value);
		}
		return Syntax.code("process.env[{0}] ?? null", key);
	}

	static function withPluginScope(options:LoadOptions, scope:PluginScope):LoadOptions {
		return {
			env: options.env,
			defaultUsername: options.defaultUsername,
			worktree: options.worktree,
			pluginScope: scope,
		};
	}

	static function pluginScope(options:LoadOptions):PluginScope {
		final scope = options.pluginScope;
		return scope == PluginScopeGlobal ? PluginScopeGlobal : PluginScopeLocal;
	}
}
