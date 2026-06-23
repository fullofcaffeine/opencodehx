package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;

class ReadTool {
	static inline final DEFAULT_READ_LIMIT = 2000;
	static inline final MAX_LINE_LENGTH = 2000;
	static inline final MAX_BYTES = 50 * 1024;

	public static function define():ToolDef {
		return {
			id: KnownToolID.Read,
			description: "Read a file or list a directory.",
			schema: {
				parameters: [
					{
						name: "filePath",
						type: "string",
						required: true,
						description: "File or directory path to read"
					},
					{
						name: "offset",
						type: "integer",
						required: false,
						description: "1-based line offset"
					},
					{
						name: "limit",
						type: "integer",
						required: false,
						description: "Maximum lines to read"
					},
				],
			},
			execute: execute,
		};
	}

	static function execute(args:Dynamic, ctx:ToolContext):ToolResult {
		final issues:Array<String> = [];
		final rawPath = ToolValidation.requireString(args, "filePath", issues);
		final offsetArg = ToolValidation.optionalInt(args, "offset", issues);
		final limitArg = ToolValidation.optionalInt(args, "limit", issues);
		if (issues.length > 0)
			throw new ToolException(InvalidArguments(KnownToolID.Read, issues));

		final absolute = resolve(KnownToolID.Read, ctx, rawPath);
		final relative = ToolPaths.relative(ctx, absolute);
		ToolPermission.require(KnownToolID.Read, ctx, {
			permission: "read",
			patterns: [relative],
			always: ["*"],
			metadata: {filepath: absolute}
		});

		if (!Fs.existsSync(absolute))
			throw new ToolException(ExecutionFailed(KnownToolID.Read, missingMessage(ctx, absolute)));

		final stat:Dynamic = Fs.statSync(absolute);
		if (stat.isDirectory())
			return readDirectory(ctx, absolute);
		if (!stat.isFile())
			throw new ToolException(ExecutionFailed(KnownToolID.Read, 'Path is not a file: ${absolute}'));

		return readFile(ctx, absolute, offsetArg, limitArg);
	}

	static function readDirectory(ctx:ToolContext, absolute:String):ToolResult {
		final entries:Array<Dynamic> = Fs.readdirSync(absolute, {withFileTypes: true});
		final rows:Array<String> = [];
		for (entry in entries) {
			final name = Std.string(Reflect.field(entry, "name"));
			if (name == ".git" || name == ".DS_Store")
				continue;
			final isDirectory:Bool = Reflect.callMethod(entry, Reflect.field(entry, "isDirectory"), []);
			rows.push(name + (isDirectory ? "/" : ""));
		}
		rows.sort(Reflect.compare);
		final limit = 200;
		final truncated = rows.length > limit;
		final shown = truncated ? rows.slice(0, limit) : rows;
		final output = [
			'<path>${absolute}</path>',
			"<type>directory</type>",
			"<entries>",
			shown.join("\n"),
			truncated ? 'showing ${shown.length} of ${rows.length} entries' : '(${rows.length} entries)',
			"</entries>"
		];
		return {
			title: ToolPaths.relative(ctx, absolute),
			metadata: {preview: shown, truncated: truncated, loaded: []},
			output: output.join("\n"),
		};
	}

	static function readFile(ctx:ToolContext, absolute:String, offsetArg:Null<Int>, limitArg:Null<Int>):ToolResult {
		final content = Fs.readFileSync(absolute, "utf8");
		if (looksBinary(content))
			throw new ToolException(ExecutionFailed(KnownToolID.Read, 'Cannot read binary file: ${absolute}'));

		final lines = StringTools.replace(content, "\r\n", "\n").split("\n");
		if (lines.length > 0 && lines[lines.length - 1] == "")
			lines.pop();
		final offset = offsetArg == null ? 1 : offsetArg;
		final limit = limitArg == null ? DEFAULT_READ_LIMIT : limitArg;
		if (offset < 1)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, "offset must be greater than 0"));
		if (limit < 1)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, "limit must be greater than 0"));

		final start = offset - 1;
		final end = start + limit > lines.length ? lines.length : start + limit;
		final body:Array<String> = [];
		var bytes = 0;
		var byteTruncated = false;
		if (start < lines.length) {
			for (i in start...end) {
				var line = lines[i];
				if (line.length > MAX_LINE_LENGTH)
					line = line.substr(0, MAX_LINE_LENGTH) + "...";
				final row = '${i + 1}: ${line}';
				bytes += row.length;
				if (bytes > MAX_BYTES) {
					byteTruncated = true;
					break;
				}
				body.push(row);
			}
		}
		final lineTruncated = end < lines.length;
		final footer = byteTruncated
			|| lineTruncated ? '(Read truncated. Use offset ${offset + body.length} to continue.)' : '(End of file - total ${lines.length} lines)';
		final output = [
			'<path>${absolute}</path>',
			"<type>file</type>",
			"<content>",
			"",
			body.join("\n"),
			footer,
			"</content>"
		];
		return {
			title: ToolPaths.relative(ctx, absolute),
			metadata: {
				preview: body,
				truncated: byteTruncated || lineTruncated,
				loaded: [{start: offset, end: offset + body.length - 1}]
			},
			output: output.join("\n"),
		};
	}

	static function missingMessage(ctx:ToolContext, absolute:String):String {
		final parent = NodePath.dirname(absolute);
		if (!Fs.existsSync(parent) || !Fs.statSync(parent).isDirectory())
			return 'File not found: ${absolute}';
		final wanted = NodePath.basename(absolute).toLowerCase();
		final suggestions:Array<String> = [];
		for (entry in Fs.readdirSync(parent, {withFileTypes: true})) {
			final name = Std.string(Reflect.field(entry, "name"));
			if (name.toLowerCase().indexOf(wanted) != -1 || wanted.indexOf(name.toLowerCase()) != -1)
				suggestions.push(name);
		}
		if (suggestions.length == 0)
			return 'File not found: ${absolute}';
		suggestions.sort(Reflect.compare);
		return 'File not found: ${absolute}. Did you mean ${suggestions.join(", ")}?';
	}

	static function looksBinary(content:String):Bool {
		final sample = content.length > 8192 ? content.substr(0, 8192) : content;
		for (i in 0...sample.length) {
			final code = sample.charCodeAt(i);
			if (code == 0)
				return true;
		}
		return false;
	}

	static function resolve(id:String, ctx:ToolContext, rawPath:String):String {
		try {
			return ToolPaths.resolve(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}
}
