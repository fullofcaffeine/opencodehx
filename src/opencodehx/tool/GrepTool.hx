package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.file.Ripgrep;
import opencodehx.file.Ripgrep.SearchMatch;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultMetadata;
import opencodehx.tool.ToolValidation;

typedef GrepToolInput = {
	final pattern:String;
	final path:Null<String>;
	final include:Null<String>;
}

class GrepTool {
	static inline final MAX_LINE_LENGTH = 2000;

	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Grep, "Search file contents by regex pattern.", {
			parameters: [
				{
					name: "pattern",
					type: "string",
					required: true,
					description: "Regex pattern to search for"
				},
				{
					name: "path",
					type: "string",
					required: false,
					description: "Directory or file path to search"
				},
				{
					name: "include",
					type: "string",
					required: false,
					description: "File glob to include"
				},
			],
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<GrepToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final pattern = ToolValidation.requireString(args, "pattern", issues);
		final rawPath = ToolValidation.optionalString(args, "path", issues);
		final include = ToolValidation.optionalString(args, "include", issues);
		return ToolValidation.finish(issues, {pattern: pattern, path: rawPath, include: include});
	}

	static function execute(input:GrepToolInput, ctx:ToolContext):ToolResult {
		final root = ctx.directory;
		final search = input.path == null ? root : resolvePath(root, input.path);
		if (!Fs.existsSync(search))
			throw new ToolException(ExecutionFailed(KnownToolID.Grep, 'No such file or directory: ${search}'));
		final stat:Dynamic = Fs.statSync(search);
		final cwd = stat.isDirectory() ? search : NodePath.dirname(search);
		final files:Null<Array<String>> = stat.isDirectory() ? null : [NodePath.relative(cwd, search)];
		final result = Ripgrep.search({
			cwd: cwd,
			pattern: input.pattern,
			glob: singleton(input.include),
			file: files
		});
		if (result.items.length == 0) {
			return {
				title: input.pattern,
				metadata: ToolResultMetadata.checked({matches: 0, truncated: false}),
				output: "No files found",
			};
		}

		final rows:Array<{
			path:String,
			line:Int,
			text:String,
			mtime:Float
		}> = [];
		for (item in result.items) {
			final absolute = NodePath.isAbsolute(item.path) ? item.path : NodePath.resolve(cwd, item.path);
			final mtime:Float = Reflect.field(Fs.statSync(absolute), "mtimeMs");
			rows.push({
				path: absolute,
				line: item.lineNumber,
				text: item.line,
				mtime: mtime
			});
		}
		rows.sort((a, b) -> {
			final byTime = Reflect.compare(b.mtime, a.mtime);
			return byTime != 0 ? byTime : Reflect.compare(a.path + ":" + a.line, b.path + ":" + b.line);
		});

		final limit = 100;
		final truncated = rows.length > limit;
		final shown = truncated ? rows.slice(0, limit) : rows;
		final output = [
			'Found ${rows.length} matches${truncated ? " (showing first " + limit + ")" : ""}'
		];
		var current = "";
		for (row in shown) {
			if (current != row.path) {
				if (current != "")
					output.push("");
				current = row.path;
				output.push('${row.path}:');
			}
			final text = row.text.length > MAX_LINE_LENGTH ? row.text.substr(0, MAX_LINE_LENGTH) + "..." : row.text;
			output.push('  Line ${row.line}: ${text}');
		}
		if (truncated) {
			output.push("");
			output.push('(Results truncated: showing ${limit} of ${rows.length} matches (${rows.length - limit} hidden). Consider using a more specific path or pattern.)');
		}
		if (result.partial) {
			output.push("");
			output.push("(Some paths were inaccessible and skipped)");
		}

		return {
			title: input.pattern,
			metadata: ToolResultMetadata.checked({
				matches: rows.length,
				truncated: truncated,
			}),
			output: output.join("\n"),
		};
	}

	static function resolvePath(root:String, value:String):String {
		return NodePath.isAbsolute(value) ? NodePath.resolve(value, ".") : NodePath.resolve(root, value);
	}

	static function singleton(value:Null<String>):Null<Array<String>> {
		if (value == null)
			return null;
		final text:String = value;
		return [text];
	}
}
