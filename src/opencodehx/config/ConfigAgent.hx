package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.config.ConfigInfo.AgentMap;
import opencodehx.config.ConfigInfo.PermissionConfig;
import opencodehx.config.ConfigInfo.PermissionConfigValue;
import opencodehx.provider.ProviderOpenRecords;
import opencodehx.provider.ProviderTypes.ProviderOptions;

private typedef AgentMarkdownData = DynamicAccess<ConfigMarkdown.MarkdownValue>;

/**
 * Loads markdown-backed agent and mode definitions into typed config records.
 *
 * Markdown frontmatter remains an `Unknown` boundary in `ConfigMarkdown`; this
 * module owns the narrowing for agent fields, permission maps, and provider
 * option passthrough keys.
 */
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

	static function options(data:AgentMarkdownData):ProviderOptions {
		final result = ProviderOpenRecords.options();
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
		final text = UnknownNarrow.string(value);
		if (text != null)
			return text;
		final record = UnknownNarrow.record(value);
		if (record != null) {
			final result = new DynamicAccess<String>();
			for (field in record.keys()) {
				final child = UnknownNarrow.string(record.get(field));
				if (child != null)
					result.set(field, child);
			}
			return result;
		}
		return null;
	}

	static function stringField(data:AgentMarkdownData, field:String):Null<String> {
		return UnknownNarrow.string(valueAt(data, field));
	}

	static function boolField(data:AgentMarkdownData, field:String):Null<Bool> {
		return UnknownNarrow.bool(valueAt(data, field));
	}

	static function floatField(data:AgentMarkdownData, field:String):Null<Float> {
		return UnknownNarrow.number(valueAt(data, field));
	}

	static function intField(data:AgentMarkdownData, field:String):Null<Int> {
		final value = UnknownNarrow.number(valueAt(data, field));
		if (value != null && Math.floor(value) == value)
			return Std.int(value);
		return null;
	}

	static function boolMapField(data:AgentMarkdownData, field:String):Null<DynamicAccess<Bool>> {
		final object = objectField(data, field);
		if (object == null)
			return null;
		final result = new DynamicAccess<Bool>();
		for (key in object.keys()) {
			final value = UnknownNarrow.bool(object.get(key));
			if (value != null)
				result.set(key, value);
		}
		return result;
	}

	static function objectField(data:AgentMarkdownData, field:String):Null<AgentMarkdownData> {
		final record = UnknownNarrow.record(valueAt(data, field));
		if (record == null)
			return null;
		final result = new DynamicAccess<ConfigMarkdown.MarkdownValue>();
		for (child in record.keys())
			result.set(child, record.get(child));
		return result;
	}

	static inline function valueAt(data:AgentMarkdownData, field:String):Unknown {
		return Unknown.fromBoundary(data.get(field));
	}
}
