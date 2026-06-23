package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.file.Ripgrep;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolValidation;

class GlobTool {
	public static function define():ToolDef {
		return {
			id: KnownToolID.Glob,
			description: "Find files by glob pattern.",
			schema: {
				parameters: [
					{
						name: "pattern",
						type: "string",
						required: true,
						description: "The glob pattern to match files against"
					},
					{
						name: "path",
						type: "string",
						required: false,
						description: "Directory to search; defaults to current directory"
					},
				],
			},
			execute: execute,
		};
	}

	static function execute(args:Dynamic, ctx:ToolContext):ToolResult {
		final issues:Array<String> = [];
		final pattern = ToolValidation.requireString(args, "pattern", issues);
		final rawPath = ToolValidation.optionalString(args, "path", issues);
		if (issues.length > 0)
			throw new ToolException(InvalidArguments(KnownToolID.Glob, issues));

		final root = ctx.directory;
		final search = rawPath == null ? root : resolvePath(root, rawPath);
		if (Fs.existsSync(search) && Fs.statSync(search).isFile())
			throw new ToolException(ExecutionFailed(KnownToolID.Glob, 'glob path must be a directory: ${search}'));
		if (!Fs.existsSync(search) || !Fs.statSync(search).isDirectory())
			throw new ToolException(ExecutionFailed(KnownToolID.Glob, 'No such directory: ${search}'));

		final limit = 100;
		final rows:Array<{path:String, mtime:Float}> = [];
		for (file in Ripgrep.files({cwd: search, glob: [pattern]})) {
			final absolute = NodePath.resolve(search, file);
			final stat:Dynamic = Fs.statSync(absolute);
			final mtime:Float = Reflect.field(stat, "mtimeMs");
			rows.push({path: absolute, mtime: mtime});
		}
		rows.sort((a, b) -> Reflect.compare(b.mtime, a.mtime));
		final truncated = rows.length > limit;
		final shown = truncated ? rows.slice(0, limit) : rows;
		final output:Array<String> = [];
		if (shown.length == 0) {
			output.push("No files found");
		} else {
			for (row in shown)
				output.push(row.path);
			if (truncated) {
				output.push("");
				output.push('(Results are truncated: showing first ${limit} results. Consider using a more specific path or pattern.)');
			}
		}
		return {
			title: NodePath.relative(worktree(ctx, root), search),
			metadata: {
				count: shown.length,
				truncated: truncated,
			},
			output: output.join("\n"),
		};
	}

	static function resolvePath(root:String, value:String):String {
		return NodePath.isAbsolute(value) ? NodePath.resolve(value, ".") : NodePath.resolve(root, value);
	}

	static function worktree(ctx:ToolContext, root:String):String {
		return ctx.worktree == null ? root : ctx.worktree;
	}
}
