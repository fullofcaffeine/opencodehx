package opencodehx.permission;

import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo.PermissionConfig;
import opencodehx.externs.node.Os;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.util.Wildcard;

class PermissionRules {
	static final EDIT_TOOLS = ["edit", "write", "apply_patch"];

	public static function evaluate(permission:String, pattern:String, rulesets:Array<Array<PermissionRule>>):PermissionRule {
		final rules:Array<PermissionRule> = [];
		for (ruleset in rulesets) {
			for (rule in ruleset)
				rules.push(rule);
		}
		var found:Null<PermissionRule> = null;
		for (rule in rules) {
			if (Wildcard.match(permission, rule.permission) && Wildcard.match(pattern, rule.pattern))
				found = rule;
		}
		if (found != null)
			return found;
		return {permission: permission, pattern: "*", action: "ask"};
	}

	public static function merge(rulesets:Array<Array<PermissionRule>>):Array<PermissionRule> {
		final result:Array<PermissionRule> = [];
		for (ruleset in rulesets) {
			for (rule in ruleset)
				result.push(rule);
		}
		return result;
	}

	public static function disabled(tools:Array<String>, ruleset:Array<PermissionRule>):Array<String> {
		final result:Array<String> = [];
		for (tool in tools) {
			final permission = EDIT_TOOLS.indexOf(tool) == -1 ? tool : "edit";
			var found:Null<PermissionRule> = null;
			for (rule in ruleset) {
				if (Wildcard.match(permission, rule.permission))
					found = rule;
			}
			if (found != null && found.pattern == "*" && found.action == "deny")
				result.push(tool);
		}
		return result;
	}

	public static function fromConfig(config:Null<PermissionConfig>):Array<PermissionRule> {
		if (config == null)
			return [];
		final keys = Reflect.fields(config);
		keys.sort((a, b) -> {
			final aWild = a.indexOf("*") != -1;
			final bWild = b.indexOf("*") != -1;
			if (aWild == bWild)
				return 0;
			return aWild ? -1 : 1;
		});
		final result:Array<PermissionRule> = [];
		for (key in keys) {
			// Runtime JSON can hold either a direct action string or a pattern map.
			// This localized Dynamic read is the narrowing point for that union.
			final value:Dynamic = config.get(key);
			if (Std.isOfType(value, String)) {
				result.push({permission: key, pattern: "*", action: Std.string(value)});
				continue;
			}
			if (value == null || !Reflect.isObject(value))
				continue;
			final patterns:DynamicAccess<String> = cast value;
			for (pattern in patterns.keys()) {
				result.push({
					permission: key,
					pattern: expand(pattern),
					action: Std.string(patterns.get(pattern)),
				});
			}
		}
		return result;
	}

	static function expand(pattern:String):String {
		if (pattern == "~")
			return homedir();
		if (StringTools.startsWith(pattern, "~/"))
			return homedir() + pattern.substr(1);
		if (pattern == "$HOME")
			return homedir();
		if (StringTools.startsWith(pattern, "$HOME/"))
			return homedir() + pattern.substr(5);
		return pattern;
	}

	static function homedir():String {
		return Os.homedir();
	}
}
