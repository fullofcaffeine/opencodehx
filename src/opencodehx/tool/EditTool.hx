package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;

class EditTool {
	public static function define():ToolDef {
		return {
			id: "edit",
			description: "Replace text in a file or create a file when oldString is empty.",
			schema: {
				parameters: [
					{
						name: "filePath",
						type: "string",
						required: true,
						description: "File path to modify"
					},
					{
						name: "oldString",
						type: "string",
						required: true,
						description: "Text to replace"
					},
					{
						name: "newString",
						type: "string",
						required: true,
						description: "Replacement text"
					},
					{
						name: "replaceAll",
						type: "boolean",
						required: false,
						description: "Replace every occurrence"
					},
				],
			},
			execute: execute,
		};
	}

	static function execute(args:Dynamic, ctx:ToolContext):ToolResult {
		final issues:Array<String> = [];
		final rawPath = ToolValidation.requireString(args, "filePath", issues);
		final oldString = readRequiredString(args, "oldString", issues);
		final newString = readRequiredString(args, "newString", issues);
		final replaceAllArg = ToolValidation.optionalBool(args, "replaceAll", issues);
		if (issues.length > 0)
			throw new ToolException(InvalidArguments("edit", issues));
		if (oldString == newString)
			throw new ToolException(ExecutionFailed("edit", "No changes to apply: oldString and newString are identical."));

		final absolute = resolve("edit", ctx, rawPath);
		final existed = Fs.existsSync(absolute);
		if (existed && Fs.statSync(absolute).isDirectory())
			throw new ToolException(ExecutionFailed("edit", 'Path is a directory, not a file: ${absolute}'));
		if (!existed && oldString != "")
			throw new ToolException(ExecutionFailed("edit", 'File ${absolute} not found'));

		final oldContent = existed ? Fs.readFileSync(absolute, "utf8") : "";
		final ending = detectLineEnding(oldContent);
		final normalizedOld = convertToLineEnding(normalizeLineEndings(oldString), ending);
		final normalizedNew = convertToLineEnding(normalizeLineEndings(newString), ending);
		final replaceAll = replaceAllArg == null ? false : replaceAllArg;
		final nextContent = oldString == "" ? normalizedNew : replace(oldContent, normalizedOld, normalizedNew, replaceAll);
		final diff = TextDiff.unified(absolute, oldContent, nextContent);
		final relative = ToolPaths.relative(ctx, absolute);
		ToolPermission.require("edit", ctx, {
			permission: "edit",
			patterns: [relative],
			always: ["*"],
			metadata: {filepath: absolute, diff: diff}
		});
		Fs.mkdirSync(NodePath.dirname(absolute), {recursive: true});
		Fs.writeFileSync(absolute, nextContent, "utf8");
		return {
			title: relative,
			metadata: {
				diff: diff,
				filediff: {
					file: absolute,
					patch: diff,
					additions: TextDiff.countAdditions(oldContent, nextContent),
					deletions: TextDiff.countDeletions(oldContent, nextContent),
				},
				diagnostics: {}
			},
			output: "Edit applied successfully.",
		};
	}

	static function replace(content:String, oldString:String, newString:String, replaceAll:Bool):String {
		final first = content.indexOf(oldString);
		if (first == -1)
			throw new ToolException(ExecutionFailed("edit",
				"Could not find oldString in the file. It must match exactly, including whitespace, indentation, and line endings."));
		if (replaceAll)
			return StringTools.replace(content, oldString, newString);
		final last = content.lastIndexOf(oldString);
		if (first != last)
			throw new ToolException(ExecutionFailed("edit",
				"Found multiple matches for oldString. Provide more surrounding context to make the match unique."));
		return content.substr(0, first) + newString + content.substr(first + oldString.length);
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

	static function normalizeLineEndings(text:String):String {
		return StringTools.replace(text, "\r\n", "\n");
	}

	static function detectLineEnding(text:String):String {
		return text.indexOf("\r\n") == -1 ? "\n" : "\r\n";
	}

	static function convertToLineEnding(text:String, ending:String):String {
		if (ending == "\n")
			return text;
		return StringTools.replace(text, "\n", "\r\n");
	}

	static function resolve(id:String, ctx:ToolContext, rawPath:String):String {
		try {
			return ToolPaths.resolve(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}
}
