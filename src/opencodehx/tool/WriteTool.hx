package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;

class WriteTool {
	public static function define():ToolDef {
		return {
			id: "write",
			description: "Write file contents, creating parent directories when needed.",
			schema: {
				parameters: [
					{
						name: "filePath",
						type: "string",
						required: true,
						description: "Path to write"
					},
					{
						name: "content",
						type: "string",
						required: true,
						description: "New file content"
					},
				],
			},
			execute: execute,
		};
	}

	static function execute(args:Dynamic, ctx:ToolContext):ToolResult {
		final issues:Array<String> = [];
		final rawPath = ToolValidation.requireString(args, "filePath", issues);
		final content = readRequiredString(args, "content", issues);
		if (issues.length > 0)
			throw new ToolException(InvalidArguments("write", issues));

		final absolute = resolve("write", ctx, rawPath);
		final existed = Fs.existsSync(absolute);
		final oldContent = existed && Fs.statSync(absolute).isFile() ? Fs.readFileSync(absolute, "utf8") : "";
		if (existed && Fs.statSync(absolute).isDirectory())
			throw new ToolException(ExecutionFailed("write", 'Path is a directory, not a file: ${absolute}'));
		final diff = TextDiff.unified(absolute, oldContent, content);
		final relative = ToolPaths.relative(ctx, absolute);
		ToolPermission.require("write", ctx, {
			permission: "edit",
			patterns: [relative],
			always: ["*"],
			metadata: {filepath: absolute, diff: diff}
		});
		Fs.mkdirSync(NodePath.dirname(absolute), {recursive: true});
		Fs.writeFileSync(absolute, content, "utf8");
		return {
			title: relative,
			metadata: {
				filepath: absolute,
				exists: existed,
				diff: diff,
				filediff: {
					file: absolute,
					patch: diff,
					additions: TextDiff.countAdditions(oldContent, content),
					deletions: TextDiff.countDeletions(oldContent, content),
				},
				diagnostics: {}
			},
			output: "Wrote file successfully.",
		};
	}

	static function resolve(id:String, ctx:ToolContext, rawPath:String):String {
		try {
			return ToolPaths.resolve(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}

	static function readRequiredString(args:Dynamic, field:String, issues:Array<String>):String {
		if (!Reflect.hasField(args, field) || Reflect.field(args, field) == null) {
			issues.push('${field}: expected string');
			return "";
		}
		final value = Reflect.field(args, field);
		if (!Std.isOfType(value, String)) {
			issues.push('${field}: expected string');
			return "";
		}
		return value;
	}
}
