package opencodehx.config;

import haxe.ds.ReadOnlyArray;
import haxe.DynamicAccess;
import haxe.Json;
import genes.js.Async.await;
import genes.ts.Unknown;
import js.Syntax;
import js.lib.Promise;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.CompactionConfig;
import opencodehx.config.ConfigInfo.PermissionConfig;
import opencodehx.config.ConfigInfo.PermissionConfigValue;
import opencodehx.config.ConfigInfo.ServerConfig;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigInfo.SkillsConfig;
import opencodehx.config.ConfigManaged.ManagedConfigSource;
import opencodehx.config.ConfigPlugin.PluginScope;
import opencodehx.config.ConfigPlugin.PluginSpec;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.Fetch;
import opencodehx.externs.web.Fetch.RemoteConfigObject;
import opencodehx.externs.web.Fetch.WellKnownPayload;
import opencodehx.host.node.NodePath;

typedef LoadOptions = {
	@:optional final env:ConfigEnv;
	@:optional final defaultUsername:String;
	@:optional final includeDefaultUsername:Bool;
	@:optional final worktree:String;
	@:optional final pluginScope:PluginScope;
	@:optional final managedConfig:ManagedConfigSource;
}

@:ts.type("{[key: string]: string | null | undefined}")
abstract ConfigEnv(Dynamic) from Dynamic to Dynamic {}

typedef WellKnownAuth = {
	final url:String;
	final key:String;
	final token:String;
}

typedef AccountRemoteConfig = {
	final url:String;
	final config:RemoteConfigObject;
	@:optional final token:String;
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
		final result = includeDefaultUsername(opts) ? ConfigInfo.empty(defaultUsername(opts)) : new ConfigInfo();
		final customPath = envValue(opts, "OPENCODE_CONFIG");
		if (customPath != null && customPath != "")
			result.merge(loadFile(customPath, opts));

		if (!projectConfigDisabled(opts)) {
			final projectOpencodeDirs = opencodeDirectories(directory, opts.worktree);
			for (dir in projectDirectories(directory, opts.worktree)) {
				mergeConfigFiles(result, dir, withPluginScope(opts, PluginScopeLocal));
			}
			for (dir in projectOpencodeDirs) {
				mergeConfigFiles(result, dir, withPluginScope(opts, PluginScopeLocal));
				mergeDiscoveredEntries(result, dir, PluginScopeLocal);
			}
		}

		final configDir = envValue(opts, "OPENCODE_CONFIG_DIR");
		if (configDir != null && configDir != "") {
			mergeConfigFiles(result, configDir, withPluginScope(opts, PluginScopeGlobal));
			mergeDiscoveredEntries(result, configDir, PluginScopeGlobal);
		}

		final content = envValue(opts, "OPENCODE_CONFIG_CONTENT");
		if (content != null && content != "") {
			result.merge(loadText(content, "OPENCODE_CONFIG_CONTENT", directory, withPluginScope(opts, PluginScopeLocal)));
		}
		mergeManagedConfig(result, opts);
		finalizeConfig(result, opts);
		return result;
	}

	@:async
	public static function loadProjectWithRemoteWellKnown(directory:String, auths:Array<WellKnownAuth>, ?options:LoadOptions):Promise<ConfigInfo> {
		return loadProjectWithRemoteSources(directory, auths, [], options);
	}

	@:async
	public static function loadProjectWithRemoteSources(directory:String, auths:Array<WellKnownAuth>, accountConfigs:Array<AccountRemoteConfig>,
			?options:LoadOptions):Promise<ConfigInfo> {
		final opts:LoadOptions = options == null ? {} : options;
		final result = new ConfigInfo();
		final env = ensureEnv(opts);
		for (auth in auths) {
			final url = normalizeBaseUrl(auth.url);
			setEnvValue(env, auth.key, auth.token);
			final response = @:await Fetch.fetch(url + "/.well-known/opencode");
			if (!response.ok)
				throw 'failed to fetch remote config from ${url}: ${response.status}';
			final payload:WellKnownPayload = @:await response.json();
			final remote = payload.config;
			if (remote == null)
				continue;
			if (!remote.exists("$schema"))
				remote.set("$schema", Unknown.fromBoundary(ConfigInfo.DEFAULT_SCHEMA));
			final source = url + "/.well-known/opencode";
			result.merge(loadText(Json.stringify(remote), source, source, withPluginScope(withEnv(opts, env), PluginScopeGlobal)));
		}
		result.merge(loadProject(directory, withoutDefaultUsername(withEnv(opts, env))));
		for (accountConfig in accountConfigs) {
			final url = normalizeBaseUrl(accountConfig.url);
			final token = accountConfig.token;
			if (token != null)
				setEnvValue(env, "OPENCODE_CONSOLE_TOKEN", token);
			final source = url + "/api/config";
			result.merge(loadText(Json.stringify(accountConfig.config), source, source, withPluginScope(withEnv(opts, env), PluginScopeGlobal)));
		}
		mergeManagedConfig(result, withEnv(opts, env));
		finalizeConfig(result, withEnv(opts, env));
		if (result.username == null)
			result.username = defaultUsername(opts);
		return result;
	}

	static function mergeManagedConfig(result:ConfigInfo, options:LoadOptions):Void {
		final managed = options.managedConfig;
		if (managed == null)
			return;
		result.merge(loadText(managed.text, managed.source, managed.source, withPluginScope(options, PluginScopeGlobal)));
	}

	static function mergeConfigFiles(result:ConfigInfo, directory:String, options:LoadOptions):Void {
		for (file in ["opencode.json", "opencode.jsonc"]) {
			final path = NodePath.join(directory, file);
			if (Fs.existsSync(path))
				result.merge(loadFile(path, options));
		}
	}

	static function mergeDiscoveredEntries(result:ConfigInfo, directory:String, scope:PluginScope):Void {
		final discovered = new ConfigInfo();
		discovered.command = ConfigCommand.load(directory);
		discovered.agent = ConfigAgent.load(directory);
		discovered.mode = ConfigAgent.loadMode(directory);
		discovered.plugin = ConfigPlugin.load(directory);
		discovered.pluginOrigins = [
			for (spec in discovered.plugin)
				ConfigPlugin.withOrigin(spec, directory, scope)
		];
		result.merge(discovered);
	}

	static function finalizeConfig(result:ConfigInfo, options:LoadOptions):Void {
		promoteModes(result);
		applyEnvPermission(result, options);
		migrateLegacyTools(result);
		applyAutoshare(result);
		applyCompactionFlags(result, options);
	}

	static function promoteModes(result:ConfigInfo):Void {
		if (result.mode == null)
			return;
		if (result.agent == null)
			result.agent = new DynamicAccess();
		for (name in result.mode.keys()) {
			final mode = result.mode.get(name);
			result.agent.set(name, mergeAgent(result.agent.get(name), mode));
		}
	}

	static function mergeAgent(current:Null<ConfigInfo.AgentInfo>, mode:ConfigInfo.AgentInfo):ConfigInfo.AgentInfo {
		if (current == null)
			return mode;
		return {
			name: mode.name,
			model: mode.model != null ? mode.model : current.model,
			variant: mode.variant != null ? mode.variant : current.variant,
			temperature: mode.temperature != null ? mode.temperature : current.temperature,
			top_p: mode.top_p != null ? mode.top_p : current.top_p,
			prompt: mode.prompt != null ? mode.prompt : current.prompt,
			tools: mode.tools != null ? mode.tools : current.tools,
			disable: mode.disable != null ? mode.disable : current.disable,
			description: mode.description != null ? mode.description : current.description,
			mode: "primary",
			hidden: mode.hidden != null ? mode.hidden : current.hidden,
			options: mode.options != null ? mode.options : current.options,
			color: mode.color != null ? mode.color : current.color,
			steps: mode.steps != null ? mode.steps : current.steps,
			maxSteps: mode.maxSteps != null ? mode.maxSteps : current.maxSteps,
			permission: mode.permission != null ? mode.permission : current.permission,
		};
	}

	static function migrateLegacyTools(result:ConfigInfo):Void {
		if (result.tools == null)
			return;
		final migrated = new DynamicAccess<PermissionConfigValue>();
		for (tool in result.tools.keys()) {
			final action = result.tools.get(tool) ? "allow" : "deny";
			final permission = tool == "write" || tool == "edit" || tool == "patch" ? "edit" : tool;
			migrated.set(permission, action);
		}
		if (result.permission == null) {
			result.permission = migrated;
			return;
		}
		final merged:PermissionConfig = cast ConfigInfo.mergeObject(migrated, result.permission);
		result.permission = merged;
	}

	static function applyEnvPermission(result:ConfigInfo, options:LoadOptions):Void {
		final raw = envValue(options, "OPENCODE_PERMISSION");
		if (raw == null || raw == "")
			return;
		final parsed = Json.parse(raw);
		if (parsed == null || !Reflect.isObject(parsed) || Std.isOfType(parsed, Array))
			throw new ConfigException(InvalidError("OPENCODE_PERMISSION", ["Expected permission override to be an object"]));
		final next:PermissionConfig = cast parsed;
		result.permission = cast ConfigInfo.mergeObject(result.permission, next);
	}

	static function applyAutoshare(result:ConfigInfo):Void {
		if (result.autoshare == true && result.share == null)
			result.share = ShareAuto;
	}

	static function applyCompactionFlags(result:ConfigInfo, options:LoadOptions):Void {
		final disableAuto = envFlag(options, "OPENCODE_DISABLE_AUTOCOMPACT");
		final disablePrune = envFlag(options, "OPENCODE_DISABLE_PRUNE");
		if (!disableAuto && !disablePrune)
			return;
		final next = copyCompaction(result.compaction);
		if (disableAuto)
			next.auto = false;
		if (disablePrune)
			next.prune = false;
		result.compaction = next;
	}

	static function copyCompaction(current:Null<CompactionConfig>):CompactionConfig {
		if (current == null)
			return {};
		return {
			auto: current.auto,
			prune: current.prune,
			tail_turns: current.tail_turns,
			preserve_recent_tokens: current.preserve_recent_tokens,
			reserved: current.reserved,
		};
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

	static function normalizeBaseUrl(url:String):String {
		var result = url;
		while (StringTools.endsWith(result, "/"))
			result = result.substr(0, result.length - 1);
		return result;
	}

	public static function loadFile(path:String, ?options:LoadOptions):ConfigInfo {
		try {
			final text = Fs.readFileSync(path, "utf8");
			final info = loadText(text, path, NodePath.dirname(path), options, path);
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

	public static function loadText(text:String, source:String, directory:String, ?options:LoadOptions, ?pluginConfigFile:String):ConfigInfo {
		final opts:LoadOptions = options == null ? {} : options;
		final expanded = ConfigVariable.substitute(text, {dir: directory, env: opts.env});
		final data = Jsonc.parse(expanded, source);
		return loadParsedData(data, source, opts, pluginConfigFile);
	}

	public static function loadParsedData(data:Dynamic, source:String, ?options:LoadOptions, ?pluginConfigFile:String):ConfigInfo {
		final opts:LoadOptions = options == null ? {} : options;
		return fromDynamic(normalizeLegacyTui(data), source, pluginScope(opts), pluginConfigFile);
	}

	static function fromDynamic(data:Dynamic, source:String, scope:PluginScope, ?pluginConfigFile:String):ConfigInfo {
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
		info.skills = optionalSkills(data, source, issues);
		info.watcher = optionalAny(data, "watcher");
		info.snapshot = optionalBool(data, "snapshot", source, issues);
		info.plugin = optionalPluginArray(data, "plugin", source, issues, pluginConfigFile);
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
		info.tools = optionalBoolMap(data, "tools", issues);
		info.enterprise = optionalAny(data, "enterprise");
		info.compaction = optionalCompaction(data, source, issues);
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

	static function optionalPluginArray(data:Dynamic, field:String, source:String, issues:Array<String>, ?pluginConfigFile:String):Array<PluginSpec> {
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
			if (spec != null) {
				final resolved = pluginConfigFile == null ? spec : ConfigPlugin.resolveSpec(spec, pluginConfigFile);
				result.push(resolved);
			}
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

	static function optionalBoolMap(data:Dynamic, field:String, issues:Array<String>):Null<DynamicAccess<Bool>> {
		if (!Reflect.hasField(data, field))
			return null;
		final value = Reflect.field(data, field);
		if (value == null || !Reflect.isObject(value) || Std.isOfType(value, Array)) {
			issues.push('${field}: expected object');
			return null;
		}
		final result = new DynamicAccess<Bool>();
		for (key in Reflect.fields(value)) {
			final item = Reflect.field(value, key);
			if (Std.isOfType(item, Bool)) {
				result.set(key, item);
			} else {
				issues.push('${field}.${key}: expected boolean');
			}
		}
		return result;
	}

	static function optionalCompaction(data:Dynamic, source:String, issues:Array<String>):Null<CompactionConfig> {
		if (!Reflect.hasField(data, "compaction"))
			return null;
		final value = Reflect.field(data, "compaction");
		if (value == null || !Reflect.isObject(value) || Std.isOfType(value, Array)) {
			issues.push("compaction: expected object");
			return null;
		}
		final compactionIssues:Array<String> = [];
		for (field in Reflect.fields(value)) {
			if (["auto", "prune", "tail_turns", "preserve_recent_tokens", "reserved"].indexOf(field) == -1)
				compactionIssues.push('compaction.${field}: unrecognized key');
		}
		final auto = optionalBool(value, "auto", source, compactionIssues);
		final prune = optionalBool(value, "prune", source, compactionIssues);
		final tailTurns = optionalNonNegativeInt(value, "tail_turns", compactionIssues);
		final preserveRecentTokens = optionalNonNegativeInt(value, "preserve_recent_tokens", compactionIssues);
		final reserved = optionalNonNegativeInt(value, "reserved", compactionIssues);
		for (issue in compactionIssues)
			issues.push(issue);
		return {
			auto: auto,
			prune: prune,
			tail_turns: tailTurns,
			preserve_recent_tokens: preserveRecentTokens,
			reserved: reserved,
		};
	}

	static function optionalNonNegativeInt(data:Dynamic, field:String, issues:Array<String>):Null<Int> {
		final value = optionalInt(data, field, issues);
		if (value != null && value < 0)
			issues.push('${field}: expected non-negative integer');
		return value;
	}

	static function optionalSkills(data:Dynamic, source:String, issues:Array<String>):Null<SkillsConfig> {
		if (!Reflect.hasField(data, "skills"))
			return null;
		final value = Reflect.field(data, "skills");
		if (value == null || !Reflect.isObject(value) || Std.isOfType(value, Array)) {
			issues.push("skills: expected object");
			return null;
		}
		final skillIssues:Array<String> = [];
		for (field in Reflect.fields(value)) {
			if (["paths", "urls"].indexOf(field) == -1)
				skillIssues.push('skills.${field}: unrecognized key');
		}
		final paths = optionalStringArray(value, "paths", source, skillIssues);
		final urls = optionalStringArray(value, "urls", source, skillIssues);
		for (issue in skillIssues)
			issues.push(issue);
		return {paths: paths, urls: urls};
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

	static function includeDefaultUsername(options:LoadOptions):Bool {
		return options.includeDefaultUsername != false;
	}

	static function envValue(options:LoadOptions, key:String):Null<String> {
		if (options.env != null && Reflect.hasField(options.env, key)) {
			final value = Reflect.field(options.env, key);
			return value == null ? null : Std.string(value);
		}
		return Syntax.code("process.env[{0}] ?? null", key);
	}

	static function envFlag(options:LoadOptions, key:String):Bool {
		final value = envValue(options, key);
		return value != null && value != "" && value != "0" && value != "false";
	}

	static function ensureEnv(options:LoadOptions):ConfigEnv {
		if (options.env != null)
			return options.env;
		return Syntax.code("process.env");
	}

	static function setEnvValue(env:ConfigEnv, key:String, value:String):Void {
		Reflect.setField(env, key, value);
	}

	static function withEnv(options:LoadOptions, env:ConfigEnv):LoadOptions {
		return {
			env: env,
			defaultUsername: options.defaultUsername,
			includeDefaultUsername: options.includeDefaultUsername,
			worktree: options.worktree,
			pluginScope: options.pluginScope,
			managedConfig: options.managedConfig,
		};
	}

	static function withoutDefaultUsername(options:LoadOptions):LoadOptions {
		return {
			env: options.env,
			defaultUsername: options.defaultUsername,
			includeDefaultUsername: false,
			worktree: options.worktree,
			pluginScope: options.pluginScope,
			managedConfig: options.managedConfig,
		};
	}

	static function withPluginScope(options:LoadOptions, scope:PluginScope):LoadOptions {
		return {
			env: options.env,
			defaultUsername: options.defaultUsername,
			includeDefaultUsername: options.includeDefaultUsername,
			worktree: options.worktree,
			pluginScope: scope,
			managedConfig: options.managedConfig,
		};
	}

	static function pluginScope(options:LoadOptions):PluginScope {
		final scope = options.pluginScope;
		return scope == PluginScopeGlobal ? PluginScopeGlobal : PluginScopeLocal;
	}
}
