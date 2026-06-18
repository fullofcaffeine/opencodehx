package opencodehx.config;

import haxe.DynamicAccess;
import haxe.extern.EitherType;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderInterleaved;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTypes.ProviderVariants;

enum ShareMode {
	ShareManual;
	ShareAuto;
	ShareDisabled;
}

enum AutoUpdate {
	AutoUpdateEnabled;
	AutoUpdateDisabled;
	AutoUpdateNotify;
}

typedef ServerConfig = {
	@:optional final port:Int;
	@:optional final hostname:String;
	@:optional final mdns:Bool;
	@:optional final mdnsDomain:String;
	@:optional final cors:Array<String>;
}

typedef ConfigProviderMap = DynamicAccess<ConfigProviderConfig>;

typedef ConfigProviderConfig = {
	@:optional final name:String;
	@:optional final env:Array<String>;
	@:optional final api:String;
	@:optional final npm:String;
	@:optional final options:ProviderOptions;
	@:optional final models:DynamicAccess<ConfigProviderModelConfig>;
	@:optional final whitelist:Array<String>;
	@:optional final blacklist:Array<String>;
}

typedef ConfigProviderModelConfig = {
	@:optional final id:String;
	@:optional final name:String;
	@:optional final family:String;
	@:optional final status:String;
	@:optional final provider:ConfigProviderModelApiConfig;
	@:optional final temperature:Bool;
	@:optional final reasoning:Bool;
	@:optional final attachment:Bool;
	@:optional final tool_call:Bool;
	@:optional final modalities:ConfigProviderModalitiesConfig;
	@:optional final interleaved:ProviderInterleaved;
	@:optional final cost:ConfigProviderModelCostConfig;
	@:optional final limit:ConfigProviderModelLimitConfig;
	@:optional final release_date:String;
	@:optional final options:ProviderOptions;
	@:optional final headers:ProviderHeaders;
	@:optional final variants:ProviderVariants;
}

typedef ConfigProviderModelApiConfig = {
	@:optional final api:String;
	@:optional final npm:String;
}

typedef ConfigProviderModalitiesConfig = {
	@:optional final input:Array<String>;
	@:optional final output:Array<String>;
}

typedef ConfigProviderModelCostConfig = {
	@:optional final input:Float;
	@:optional final output:Float;
	@:optional final cache_read:Float;
	@:optional final cache_write:Float;
}

typedef ConfigProviderModelLimitConfig = {
	@:optional final context:Float;
	@:optional final output:Float;
	@:optional final input:Float;
}

typedef PermissionConfig = DynamicAccess<PermissionConfigValue>;
typedef PermissionConfigValue = EitherType<String, DynamicAccess<String>>;

class ConfigInfo {
	public static inline final DEFAULT_SCHEMA = "https://opencode.ai/config.json";

	public var schema:Null<String>;
	public var logLevel:Null<String>;
	public var server:Null<ServerConfig>;
	// Boundary debt: these nested schemas are owned by later command/skill/file-watch/plugin slices.
	public var command:Dynamic;
	public var skills:Dynamic;
	public var watcher:Dynamic;
	public var snapshot:Null<Bool>;
	// Boundary debt: plugin entries are external module/path descriptors until plugin loading is ported.
	public var plugin:Array<Dynamic>;
	public var share:Null<ShareMode>;
	public var autoshare:Null<Bool>;
	public var autoupdate:Null<AutoUpdate>;
	public var disabledProviders:Null<Array<String>>;
	public var enabledProviders:Null<Array<String>>;
	public var model:Null<String>;
	public var smallModel:Null<String>;
	public var defaultAgent:Null<String>;
	public var username:Null<String>;
	// Boundary debt: mode/agent schemas become precise with the agent/session orchestration slice.
	public var mode:Dynamic;
	public var agent:Dynamic;
	public var provider:Null<ConfigProviderMap>;
	// Boundary debt: MCP/formatter/LSP/layout/tool/enterprise/compaction/experimental owners are not ported yet.
	public var mcp:Dynamic;
	public var formatter:Dynamic;
	public var lsp:Dynamic;
	public var instructions:Null<Array<String>>;
	public var layout:Dynamic;
	public var permission:Null<PermissionConfig>;
	public var tools:Dynamic;
	public var enterprise:Dynamic;
	public var compaction:Dynamic;
	public var experimental:Dynamic;

	public function new() {
		plugin = [];
	}

	public static function empty(username:String):ConfigInfo {
		final info = new ConfigInfo();
		info.username = username;
		return info;
	}

	public function merge(next:ConfigInfo):ConfigInfo {
		if (next.schema != null)
			schema = next.schema;
		if (next.logLevel != null)
			logLevel = next.logLevel;
		if (next.server != null)
			server = next.server;
		if (next.command != null)
			command = mergeObject(command, next.command);
		if (next.skills != null)
			skills = next.skills;
		if (next.watcher != null)
			watcher = next.watcher;
		if (next.snapshot != null)
			snapshot = next.snapshot;
		if (next.plugin.length > 0)
			plugin = next.plugin.copy();
		if (next.share != null)
			share = next.share;
		if (next.autoshare != null)
			autoshare = next.autoshare;
		if (next.autoupdate != null)
			autoupdate = next.autoupdate;
		if (next.disabledProviders != null)
			disabledProviders = next.disabledProviders;
		if (next.enabledProviders != null)
			enabledProviders = next.enabledProviders;
		if (next.model != null)
			model = next.model;
		if (next.smallModel != null)
			smallModel = next.smallModel;
		if (next.defaultAgent != null)
			defaultAgent = next.defaultAgent;
		if (next.username != null)
			username = next.username;
		if (next.mode != null)
			mode = mergeObject(mode, next.mode);
		if (next.agent != null)
			agent = mergeObject(agent, next.agent);
		if (next.provider != null)
			provider = mergeObject(provider, next.provider);
		if (next.mcp != null)
			mcp = mergeObject(mcp, next.mcp);
		if (next.formatter != null)
			formatter = next.formatter;
		if (next.lsp != null)
			lsp = next.lsp;
		if (next.instructions != null)
			instructions = concatUnique(instructions, next.instructions);
		if (next.layout != null)
			layout = next.layout;
		if (next.permission != null)
			permission = next.permission;
		if (next.tools != null)
			tools = mergeObject(tools, next.tools);
		if (next.enterprise != null)
			enterprise = mergeObject(enterprise, next.enterprise);
		if (next.compaction != null)
			compaction = mergeObject(compaction, next.compaction);
		if (next.experimental != null)
			experimental = mergeObject(experimental, next.experimental);
		return this;
	}

	static function concatUnique(current:Null<Array<String>>, next:Array<String>):Array<String> {
		final result = current == null ? [] : current.copy();
		for (item in next) {
			if (result.indexOf(item) == -1)
				result.push(item);
		}
		return result;
	}

	static function mergeObject(current:Dynamic, next:Dynamic):Dynamic {
		if (current == null)
			return next;
		if (!isObjectRecord(current) || !isObjectRecord(next))
			return next;

		final result:Dynamic = {};
		for (field in Reflect.fields(current)) {
			Reflect.setField(result, field, Reflect.field(current, field));
		}
		for (field in Reflect.fields(next)) {
			final currentValue = Reflect.field(result, field);
			final nextValue = Reflect.field(next, field);
			Reflect.setField(result, field, mergeObject(currentValue, nextValue));
		}
		return result;
	}

	static function isObjectRecord(value:Dynamic):Bool {
		if (value == null)
			return false;
		if (Std.isOfType(value, Array))
			return false;
		if (Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return false;
		return Reflect.isObject(value);
	}
}
