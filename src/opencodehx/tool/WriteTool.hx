package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.file.FileToolEvents.FileWatcherUpdateKind;
import opencodehx.host.node.NodePath;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolExternalDirectory.ExternalDirectoryKind;
import opencodehx.tool.ToolExternalDirectory.requireExternalDirectory;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;
import opencodehx.tool.ToolTypes.ToolResultMetadata;

typedef WriteToolInput = {
	final filePath:String;
	final content:String;
}

class WriteTool {
	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Write, "Write file contents, creating parent directories when needed.", {
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
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<WriteToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final rawPath = ToolValidation.requireString(args, "filePath", issues);
		final content = ToolValidation.requireStringAllowEmpty(args, "content", issues);
		return ToolValidation.finish(issues, {filePath: rawPath, content: content});
	}

	static function execute(input:WriteToolInput, ctx:ToolContext):ToolResult {
		final absolute = resolve(KnownToolID.Write, ctx, input.filePath);
		requireExternalDirectory(KnownToolID.Write, ctx, absolute, ExternalDirectoryKind.ExternalFile);
		final existed = Fs.existsSync(absolute);
		final source = existed && Fs.statSync(absolute).isFile() ? ToolBom.split(Fs.readFileSync(absolute, "utf8")) : ToolBom.split("");
		final next = ToolBom.split(input.content);
		final desiredBom = source.bom || next.bom;
		final oldContent = source.text;
		final newContent = next.text;
		if (existed && Fs.statSync(absolute).isDirectory())
			throw new ToolException(ExecutionFailed(KnownToolID.Write, 'Path is a directory, not a file: ${absolute}'));
		final diff = TextDiff.unified(absolute, oldContent, newContent);
		final relative = ToolPaths.relative(ctx, absolute);
		ToolPermission.require(KnownToolID.Write, ctx, {
			permission: "edit",
			patterns: [relative],
			always: ["*"],
			metadata: ToolPermissionMetadata.checked({filepath: absolute, diff: diff})
		});
		Fs.mkdirSync(NodePath.dirname(absolute), {recursive: true});
		Fs.writeFileSync(absolute, ToolBom.join(newContent, desiredBom), "utf8");
		final formatFile = ctx.formatFile;
		if (formatFile != null && formatFile(absolute)) {
			ToolBom.syncFile(() -> Fs.readFileSync(absolute, "utf8"), text -> Fs.writeFileSync(absolute, text, "utf8"), desiredBom);
		}
		ToolFileNotifications.edited(ctx, absolute);
		ToolFileNotifications.watcherUpdated(ctx, absolute, existed ? Change : Add);
		return {
			title: relative,
			metadata: ToolResultMetadata.checked({
				filepath: absolute,
				exists: existed,
				diff: diff,
				filediff: {
					file: absolute,
					patch: diff,
					additions: TextDiff.countAdditions(oldContent, newContent),
					deletions: TextDiff.countDeletions(oldContent, newContent),
				},
				diagnostics: {}
			}),
			output: "Wrote file successfully.",
		};
	}

	static function resolve(id:String, ctx:ToolContext, rawPath:String):String {
		try {
			return ToolPaths.resolveAny(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}
}
