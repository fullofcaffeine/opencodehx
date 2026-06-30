package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import opencodehx.config.ConfigInfo.CommandInfo;
import opencodehx.config.ConfigInfo.CommandMap;

private typedef CommandMarkdownData = DynamicAccess<ConfigMarkdown.MarkdownValue>;

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

	static function stringField(data:CommandMarkdownData, field:String):Null<String> {
		return UnknownNarrow.string(valueAt(data, field));
	}

	static function boolField(data:CommandMarkdownData, field:String):Null<Bool> {
		return UnknownNarrow.bool(valueAt(data, field));
	}

	static inline function valueAt(data:CommandMarkdownData, field:String):Unknown {
		return Unknown.fromBoundary(data.get(field));
	}
}
