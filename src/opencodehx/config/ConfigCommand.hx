package opencodehx.config;

import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo.CommandInfo;
import opencodehx.config.ConfigInfo.CommandMap;

class ConfigCommand {
	public static function load(dir:String):CommandMap {
		final result = new DynamicAccess<CommandInfo>();
		for (item in ConfigMarkdownFiles.scan(dir, ["command", "commands"])) {
			final md = ConfigMarkdown.parse(item);
			final name = ConfigEntryName.fromPath(item, ["/.opencode/command/", "/.opencode/commands/", "/command/", "/commands/"]);
			result.set(name, {
				template: StringTools.trim(md.content),
				description: stringField(md.data, "description"),
				agent: stringField(md.data, "agent"),
				model: stringField(md.data, "model"),
				subtask: boolField(md.data, "subtask"),
			});
		}
		return result;
	}

	static function stringField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<String> {
		final value = data.get(field);
		return Std.isOfType(value, String) ? cast value : null;
	}

	static function boolField(data:DynamicAccess<ConfigMarkdown.MarkdownValue>, field:String):Null<Bool> {
		final value = data.get(field);
		return Std.isOfType(value, Bool) ? cast value : null;
	}
}
