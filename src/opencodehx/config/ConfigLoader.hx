package opencodehx.config;

import haxe.ds.ReadOnlyArray;
import js.Syntax;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ServerConfig;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;

typedef LoadOptions = {
	@:optional final env:Dynamic;
	@:optional final defaultUsername:String;
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

		for (file in ["opencode.json", "opencode.jsonc"]) {
			final path = NodePath.join(directory, file);
			if (Fs.existsSync(path))
				result.merge(loadFile(path, opts));
		}

		final content = envValue(opts, "OPENCODE_CONFIG_CONTENT");
		if (content != null && content != "") {
			result.merge(loadText(content, "OPENCODE_CONFIG_CONTENT", directory, opts));
		}
		return result;
	}

	public static function loadFile(path:String, ?options:LoadOptions):ConfigInfo {
		try {
			return loadText(Fs.readFileSync(path, "utf8"), path, NodePath.dirname(path), options);
		} catch (configError:ConfigException) {
			throw configError;
		} catch (ioError:Dynamic) {
			throw new ConfigException(IoError(path, Std.string(ioError)));
		}
	}

	public static function loadText(text:String, source:String, directory:String, ?options:LoadOptions):ConfigInfo {
		final opts:LoadOptions = options == null ? {} : options;
		final expanded = ConfigVariable.substitute(text, {dir: directory, env: opts.env});
		final data = Jsonc.parse(expanded, source);
		return fromDynamic(normalizeLegacyTui(data), source);
	}

	static function fromDynamic(data:Dynamic, source:String):ConfigInfo {
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
		info.plugin = optionalArrayAny(data, "plugin", source, issues);
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
}
