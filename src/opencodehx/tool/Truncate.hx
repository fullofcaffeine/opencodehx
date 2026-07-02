package opencodehx.tool;

import opencodehx.externs.node.Buffer;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionTypes.PermissionRule;

enum abstract TruncateDirection(String) from String to String {
	var Head = "head";
	var Tail = "tail";
}

typedef TruncateOptions = {
	@:optional final maxLines:Int;
	@:optional final maxBytes:Int;
	@:optional final direction:TruncateDirection;
}

typedef TruncateAgentInfo = {
	@:optional final permission:Array<PermissionRule>;
}

typedef TruncateResult = {
	final content:String;
	final truncated:Bool;
	@:optional final outputPath:String;
}

class Truncate {
	public static inline final MAX_LINES = 2000;
	public static inline final MAX_BYTES = 50 * 1024;
	public static final DIR:String = NodePath.join(GlobalPaths.data(NodeProcess.env()), "tool-output");
	public static final GLOB:String = NodePath.join(DIR, "*");

	static inline final RETENTION_MS:Float = 7 * 24 * 60 * 60 * 1000;
	static var nextID:Int = 0;

	public final dir:String;

	public function new(?dir:String) {
		this.dir = dir == null ? DIR : dir;
	}

	public function cleanup(?nowMs:Float):Void {
		final timestamp = nowMs == null ? Date.now().getTime() : nowMs;
		final cutoff = timestamp - RETENTION_MS;
		if (!Fs.existsSync(dir))
			return;
		for (entry in Fs.readdirNamesSync(dir)) {
			if (!StringTools.startsWith(entry, "tool_"))
				continue;
			final created = createdAt(entry);
			if (created == null || created >= cutoff)
				continue;
			Fs.rmSync(NodePath.join(dir, entry), {recursive: true, force: true});
		}
	}

	public function write(text:String, ?nowMs:Float):String {
		final timestamp = nowMs == null ? Date.now().getTime() : nowMs;
		Fs.mkdirSync(dir, {recursive: true});
		final file = NodePath.join(dir, 'tool_${timestampName(timestamp)}_${nextID++}.txt');
		Fs.writeFileSync(file, text, "utf8");
		return file;
	}

	public function output(text:String, ?options:TruncateOptions, ?agent:TruncateAgentInfo):TruncateResult {
		final maxLines = options == null || options.maxLines == null ? MAX_LINES : options.maxLines;
		final maxBytes = options == null || options.maxBytes == null ? MAX_BYTES : options.maxBytes;
		final direction = options == null || options.direction == null ? Head : options.direction;
		final lines = text.split("\n");
		final totalBytes = byteLength(text);

		if (lines.length <= maxLines && totalBytes <= maxBytes) {
			return {
				content: text,
				truncated: false,
			};
		}

		final out:Array<String> = [];
		var bytes = 0;
		var hitBytes = false;
		if (direction == Tail) {
			var i = lines.length - 1;
			while (i >= 0 && out.length < maxLines) {
				final size = byteLength(lines[i]) + (out.length > 0 ? 1 : 0);
				if (bytes + size > maxBytes) {
					hitBytes = true;
					break;
				}
				out.unshift(lines[i]);
				bytes += size;
				i--;
			}
		} else {
			var i = 0;
			while (i < lines.length && i < maxLines) {
				final size = byteLength(lines[i]) + (i > 0 ? 1 : 0);
				if (bytes + size > maxBytes) {
					hitBytes = true;
					break;
				}
				out.push(lines[i]);
				bytes += size;
				i++;
			}
		}

		final removed = hitBytes ? totalBytes - bytes : lines.length - out.length;
		final unit = hitBytes ? "bytes" : "lines";
		final preview = out.join("\n");
		final file = write(text);
		final hint = hasTaskTool(agent) ? taskHint(file) : grepReadHint(file);

		return {
			content: direction == Tail ? '...${removed} ${unit} truncated...\n\n${hint}\n\n${preview}' : '${preview}\n\n...${removed} ${unit} truncated...\n\n${hint}',
			truncated: true,
			outputPath: file,
		};
	}

	static function byteLength(text:String):Int {
		return Buffer.from(text, "utf8").byteLength;
	}

	static function hasTaskTool(agent:Null<TruncateAgentInfo>):Bool {
		if (agent == null || agent.permission == null)
			return false;
		return PermissionRules.evaluate("task", "*", [agent.permission]).action != "deny";
	}

	static function taskHint(file:String):String {
		return
			'The tool call succeeded but the output was truncated. Full output saved to: ${file}\nUse the Task tool to have explore agent process this file with Grep and Read (with offset/limit). Do NOT read the full file yourself - delegate to save context.';
	}

	static function grepReadHint(file:String):String {
		return
			'The tool call succeeded but the output was truncated. Full output saved to: ${file}\nUse Grep to search the full content or Read with offset/limit to view specific sections.';
	}

	static function createdAt(name:String):Null<Float> {
		final rest = name.substr("tool_".length);
		final marker = rest.indexOf("_");
		final raw = marker == -1 ? rest : rest.substr(0, marker);
		if (raw == "")
			return null;
		final value = Std.parseFloat(raw);
		return Math.isNaN(value) ? null : value;
	}

	static function timestampName(timestamp:Float):String {
		return Std.string(Math.floor(timestamp));
	}
}
