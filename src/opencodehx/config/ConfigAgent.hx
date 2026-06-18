package opencodehx.config;

import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.config.ConfigInfo.AgentMap;
import opencodehx.config.ConfigInfo.OpenConfigValue;
import opencodehx.config.ConfigInfo.PermissionConfig;
import opencodehx.config.ConfigInfo.PermissionConfigValue;

class ConfigAgent {
	static final KNOWN_KEYS = [
		"name",
		"model",
		"variant",
		"prompt",
		"description",
		"temperature",
		"top_p",
		"mode",
		"hidden",
		"color",
		"steps",
		"maxSteps",
		"options",
		"permission",
		"disable",
		"tools",
	];

	public static function load(dir:String):AgentMap {
		final result = new DynamicAccess<AgentInfo>();
		for (item in ConfigMarkdownFiles.scan(dir, ["agent", "agents"])) {
			final md = ConfigMarkdown.parse(item);
			final name = ConfigEntryName.fromPath(item, ["/.opencode/agent/", "/.opencode/agents/", "/agent/", "/agents/"]);
			result.set(name, info(name, md, false));
		}
		return result;
	}

	public static function loadMode(dir:String):AgentMap {
		final result = new DynamicAccess<AgentInfo>();
		for (item in ConfigMarkdownFiles.scan(dir, ["mode", "modes"], false)) {
			final md = ConfigMarkdown.parse(item);
			final name = ConfigEntryName.fromPath(item, []);
			result.set(name, info(name, md, true));
		}
		return result;
	}

	static function info(name:String, md:ConfigMarkdown.MarkdownDocument, primary:Bool):AgentInfo {
		final data = md.data;
		final tools = boolMapField(data, "tools");
		final permission = permissionFromTools(tools);
		final explicitPermission = objectField(data, "permission");
		if (explicitPermission != null) {
			for (key in explicitPermission.keys()) {
				final value = permissionValue(explicitPermission.get(key));
				if (value != null)
					permission.set(key, value);
			}
		}
		final maxSteps = intField(data, "maxSteps");
		final steps = intField(data, "steps");
		return {
			name: name,
			model: stringField(data, "model"),
			variant: stringField(data, "variant"),
			temperature: floatField(data, "temperature"),
			top_p: floatField(data, "top_p"),
			prompt: StringTools.trim(md.content),
			tools: tools,
			disable: boolField(data, "disable"),
			description: stringField(data, "description"),
			mode: primary ? "primary" : stringField(data, "mode"),
			hidden: boolField(data, "hidden"),
			options: options(data),
			color: stringField(data, "color"),
			steps: steps != null ? steps : maxSteps,
			maxSteps: maxSteps,
			permission: permission,
		};
	}

	static function options(data:DynamicAccess<ConfigMarkdown.MarkdownValue>):DynamicAccess<OpenConfigValue> {
		final result = new DynamicAccess<OpenConfigValue>();
		final explicit = objectField(data, "options");
		if (explicit != null) {
			for (key in explicit.keys())
				result.set(key, explicit.get(key));
		}
		for (key in data.keys()) {
			if (KNOWN_KEYS.indexOf(key) == -1)
				result.set(key, data.get(key));
		}
		return result;
	}

	static function permissionFromTools(tools:Null<DynamicAccess<Bool>>):PermissionConfig {
		final result = new DynamicAccess<PermissionConfigValue>();
		if (tools == null)
			return result;
		for (tool in tools.keys()) {
			final action = tools.get(tool) ? "allow" : "deny";
			if (tool == "write" || tool == "edit" || tool == "patch")
				result.set("edit", action);
			else
				result.set(tool, action);
		}
		return result;
	}

	static function permissionValue(value:ConfigMarkdown.MarkdownValue):Null<PermissionConfigValue> {
		if (Std.isOfType(value, String))
			return cast value;
		if (value != null && Reflect.isObject(value) && !Std.isOfType(value, Array)) {
			final result = new DynamicAccess<String>();
			for (field in Reflect.fields(value)) {
				final child:ConfigMarkdown.MarkdownValue = cast Reflect.field(value, field);
				if (Std.isOfType(child, String))
					result.set(field, cast child);
			}
			return result;
		}
		return null;
	}

	static function stringField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<String> {
		final value = data.get(field);
		return Std.isOfType(value, String) ? cast value : null;
	}

	static function boolField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<Bool> {
		final value = data.get(field);
		return Std.isOfType(value, Bool) ? cast value : null;
	}

	static function floatField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<Float> {
		final value = data.get(field);
		return Std.isOfType(value, Float) || Std.isOfType(value, Int) ? cast value : null;
	}

	static function intField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<Int> {
		final value = data.get(field);
		if (Std.isOfType(value, Int))
			return cast value;
		if (Std.isOfType(value, Float) && Math.floor(cast value) == value)
			return Std.int(cast value);
		return null;
	}

	static function boolMapField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<DynamicAccess<Bool>> {
		final raw = objectField(data, field);
		if (raw == null)
			return null;
		final result = new DynamicAccess<Bool>();
		for (key in raw.keys()) {
			final value = raw.get(key);
			if (Std.isOfType(value, Bool))
				result.set(key, cast value);
		}
		return result;
	}

	static function objectField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<DynamicAccess<ConfigMarkdown.MarkdownValue>> {
		final value = data.get(field);
		if (value != null && Reflect.isObject(value) && !Std.isOfType(value, Array)) {
			final result = new DynamicAccess<ConfigMarkdown.MarkdownValue>();
			for (child in Reflect.fields(value))
				result.set(child, Reflect.field(value, child));
			return result;
		}
		return null;
	}
}
