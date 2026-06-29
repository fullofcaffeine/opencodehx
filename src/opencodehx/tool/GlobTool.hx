package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Fs.FsStats;
import opencodehx.file.Ripgrep;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultMetadata;
import opencodehx.tool.ToolValidation;
import opencodehx.tool.ToolSearchPaths.ToolSearchPath;
import opencodehx.tool.ToolSearchPaths.fromNullable;
import opencodehx.tool.ToolSearchPaths.resolve;
import opencodehx.tool.ToolSearchPaths.toNullable;
import opencodehx.tool.ToolExternalDirectory.ExternalDirectoryKind;
import opencodehx.tool.ToolExternalDirectory.requireExternalDirectory;

typedef GlobToolInput = {
	final pattern:String;
	final path:ToolSearchPath;
}

class GlobTool {
	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Glob, "Find files by glob pattern.", {
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
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<GlobToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final pattern = ToolValidation.requireString(args, "pattern", issues);
		final rawPath = ToolValidation.optionalString(args, "path", issues);
		return ToolValidation.finish(issues, {pattern: pattern, path: fromNullable(rawPath)});
	}

	static function execute(input:GlobToolInput, ctx:ToolContext):ToolResult {
		ToolPermission.require(KnownToolID.Glob, ctx, {
			permission: KnownToolID.Glob,
			patterns: [input.pattern],
			always: ["*"],
			metadata: ToolPermissionMetadata.checked({
				pattern: input.pattern,
				path: toNullable(input.path),
			})
		});

		final root = ctx.directory;
		final search = resolve(root, input.path);
		if (Fs.existsSync(search) && Fs.statSync(search).isFile())
			throw new ToolException(ExecutionFailed(KnownToolID.Glob, 'glob path must be a directory: ${search}'));
		requireExternalDirectory(KnownToolID.Glob, ctx, search, ExternalDirectoryKind.ExternalDirectory);
		if (!Fs.existsSync(search) || !Fs.statSync(search).isDirectory())
			throw new ToolException(ExecutionFailed(KnownToolID.Glob, 'No such directory: ${search}'));

		final limit = 100;
		final rows:Array<{path:String, mtime:Float}> = [];
		for (file in Ripgrep.files({cwd: search, glob: [input.pattern]})) {
			final absolute = NodePath.resolve(search, file);
			final mtime = mtimeMs(Fs.statSync(absolute));
			rows.push({path: absolute, mtime: mtime});
		}
		rows.sort((a, b) -> compareFloat(b.mtime, a.mtime));
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
			metadata: ToolResultMetadata.checked({
				count: shown.length,
				truncated: truncated,
			}),
			output: output.join("\n"),
		};
	}

	static function mtimeMs(stat:FsStats):Float {
		return stat.mtimeMs == null ? 0 : stat.mtimeMs;
	}

	static function compareFloat(left:Float, right:Float):Int {
		if (left < right)
			return -1;
		return left > right ? 1 : 0;
	}

	static function worktree(ctx:ToolContext, root:String):String {
		return ctx.worktree == null ? root : ctx.worktree;
	}
}
