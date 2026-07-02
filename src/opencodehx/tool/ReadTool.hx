package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Fs.FsDirent;
import opencodehx.externs.node.Fs.FsStats;
import opencodehx.file.AppFileSystem;
import opencodehx.host.node.NodeBuffer;
import opencodehx.host.node.NodePath;
import opencodehx.session.SessionInstruction;
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
import opencodehx.util.Media.isPdfAttachment;
import opencodehx.util.Media.isAttachmentMedia;
import opencodehx.util.Media.sniffAttachmentMime;

typedef ReadToolInput = {
	final filePath:String;
	final offset:Null<Int>;
	final limit:Null<Int>;
}

class ReadTool {
	static inline final DEFAULT_READ_LIMIT = 2000;
	static inline final MAX_LINE_LENGTH = 2000;
	static inline final MAX_LINE_SUFFIX = "... (line truncated to 2000 chars)";
	static inline final MAX_BYTES = 50 * 1024;
	static inline final SAMPLE_BYTES = 4096;

	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Read, "Read a file or list a directory.", {
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
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<ReadToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final rawPath = ToolValidation.requireString(args, "filePath", issues);
		final offsetArg = ToolValidation.optionalInt(args, "offset", issues);
		final limitArg = ToolValidation.optionalInt(args, "limit", issues);
		return ToolValidation.finish(issues, {filePath: rawPath, offset: offsetArg, limit: limitArg});
	}

	static function execute(input:ReadToolInput, ctx:ToolContext):ToolResult {
		final absolute = resolve(KnownToolID.Read, ctx, input.filePath);
		final exists = Fs.existsSync(absolute);
		final stat:Null<FsStats> = exists ? Fs.statSync(absolute) : null;
		requireExternalDirectory(KnownToolID.Read, ctx,
			absolute, stat != null && stat.isDirectory() ? ExternalDirectoryKind.ExternalDirectory : ExternalDirectoryKind.ExternalFile);
		final relative = ToolPaths.relative(ctx, absolute);
		ToolPermission.require(KnownToolID.Read, ctx, {
			permission: "read",
			patterns: [absolute],
			always: ["*"],
			metadata: ToolPermissionMetadata.checked({filepath: absolute})
		});

		if (!exists)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, missingMessage(ctx, absolute)));

		if (stat.isDirectory())
			return readDirectory(ctx, absolute, input.offset, input.limit);
		if (!stat.isFile())
			throw new ToolException(ExecutionFailed(KnownToolID.Read, 'Path is not a file: ${absolute}'));

		return readFile(ctx, absolute, input.offset, input.limit);
	}

	static function readDirectory(ctx:ToolContext, absolute:String, offsetArg:Null<Int>, limitArg:Null<Int>):ToolResult {
		final entries:Array<FsDirent> = Fs.readdirDirentsSync(absolute, {withFileTypes: true});
		final rows:Array<String> = [];
		for (entry in entries) {
			final name = entry.name;
			if (name == ".git" || name == ".DS_Store")
				continue;
			final isDirectory = entry.isDirectory();
			rows.push(name + (isDirectory ? "/" : ""));
		}
		rows.sort(compareStrings);
		final offset = intOr(offsetArg, 1);
		final limit = intOr(limitArg, DEFAULT_READ_LIMIT);
		if (offset < 1)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, "offset must be greater than or equal to 1"));
		if (limit < 1)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, "limit must be greater than 0"));
		final start = offset - 1;
		final end = start + limit > rows.length ? rows.length : start + limit;
		final shown = start < rows.length ? rows.slice(start, end) : [];
		final truncated = start + shown.length < rows.length;
		final output = [
			'<path>${absolute}</path>',
			"<type>directory</type>",
			"<entries>",
			shown.join("\n"),
			truncated ? '(Showing ${shown.length} of ${rows.length} entries. Use \'offset\' parameter to read beyond entry ${offset + shown.length})' : '(${rows.length} entries)',
			"</entries>"
		];
		return {
			title: ToolPaths.relative(ctx, absolute),
			metadata: ToolResultMetadata.checked({preview: shown, truncated: truncated, loaded: []}),
			output: output.join("\n"),
		};
	}

	static function readFile(ctx:ToolContext, absolute:String, offsetArg:Null<Int>, limitArg:Null<Int>):ToolResult {
		final loaded = SessionInstruction.nearbyForFile({
			directory: ctx.directory,
			worktree: ctx.worktree == null ? ctx.directory : ctx.worktree,
			filepath: absolute,
			messageID: ctx.messageID,
			claims: ctx.instructionClaims,
			previouslyLoaded: ctx.loadedInstructions,
		});
		final bytes = Fs.readFileBufferSync(absolute);
		final mime = sniffAttachmentMime(NodeBuffer.prefixBytes(bytes, SAMPLE_BYTES), AppFileSystem.mimeType(absolute));
		if (isAttachmentMedia(mime)) {
			final message = isPdfAttachment(mime) ? "PDF read successfully" : "Image read successfully";
			return {
				title: ToolPaths.relative(ctx, absolute),
				metadata: ToolResultMetadata.checked({
					preview: message,
					truncated: false,
					loaded: [for (item in loaded) item.filepath]
				}),
				output: message,
				attachments: [
					{
						type: "file",
						mime: mime,
						url: 'data:${mime};base64,${bytes.toString("base64")}'
					}
				],
			};
		}
		if (knownBinaryExtension(absolute))
			throw new ToolException(ExecutionFailed(KnownToolID.Read, 'Cannot read binary file: ${absolute}'));

		final content = Fs.readFileSync(absolute, "utf8");
		if (looksBinary(content))
			throw new ToolException(ExecutionFailed(KnownToolID.Read, 'Cannot read binary file: ${absolute}'));

		final lines = StringTools.replace(content, "\r\n", "\n").split("\n");
		if (lines.length > 0 && lines[lines.length - 1] == "")
			lines.pop();
		final offset = intOr(offsetArg, 1);
		final limit = intOr(limitArg, DEFAULT_READ_LIMIT);
		if (offset < 1)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, "offset must be greater than or equal to 1"));
		if (limit < 1)
			throw new ToolException(ExecutionFailed(KnownToolID.Read, "limit must be greater than 0"));
		if (lines.length < offset && !(lines.length == 0 && offset == 1))
			throw new ToolException(ExecutionFailed(KnownToolID.Read, 'Offset ${offset} is out of range for this file (${lines.length} lines)'));

		final start = offset - 1;
		final end = start + limit > lines.length ? lines.length : start + limit;
		final body:Array<String> = [];
		var bytes = 0;
		var byteTruncated = false;
		if (start < lines.length) {
			for (i in start...end) {
				var line = lines[i];
				if (line.length > MAX_LINE_LENGTH)
					line = line.substr(0, MAX_LINE_LENGTH) + MAX_LINE_SUFFIX;
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
		if (loaded.length > 0)
			output.push('<system-reminder>\n${loaded.map(item -> item.content).join("\n\n")}\n</system-reminder>');
		return {
			title: ToolPaths.relative(ctx, absolute),
			metadata: ToolResultMetadata.checked({
				preview: body,
				truncated: byteTruncated || lineTruncated,
				loaded: [for (item in loaded) item.filepath]
			}),
			output: output.join("\n"),
		};
	}

	static function missingMessage(ctx:ToolContext, absolute:String):String {
		final parent = NodePath.dirname(absolute);
		if (!Fs.existsSync(parent) || !Fs.statSync(parent).isDirectory())
			return 'File not found: ${absolute}';
		final wanted = NodePath.basename(absolute).toLowerCase();
		final suggestions:Array<String> = [];
		for (entry in Fs.readdirDirentsSync(parent, {withFileTypes: true})) {
			final name = entry.name;
			if (name.toLowerCase().indexOf(wanted) != -1 || wanted.indexOf(name.toLowerCase()) != -1)
				suggestions.push(name);
		}
		if (suggestions.length == 0)
			return 'File not found: ${absolute}';
		suggestions.sort(compareStrings);
		return 'File not found: ${absolute}. Did you mean ${suggestions.join(", ")}?';
	}

	static function knownBinaryExtension(path:String):Bool {
		return switch NodePath.extname(path).toLowerCase() {
			case ".zip" | ".tar" | ".gz" | ".exe" | ".dll" | ".so" | ".class" | ".jar" | ".war" | ".7z" | ".doc" | ".docx" | ".xls" | ".xlsx" | ".ppt" |
				".pptx" | ".odt" | ".ods" | ".odp" | ".bin" | ".dat" | ".obj" | ".o" | ".a" | ".lib" | ".wasm" | ".pyc" | ".pyo":
				true;
			case _:
				false;
		}
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
			return ToolPaths.resolveAny(ctx, rawPath);
		} catch (error:Dynamic) {
			throw new ToolException(ExecutionFailed(id, Std.string(error)));
		}
	}

	static function compareStrings(left:String, right:String):Int {
		if (left < right)
			return -1;
		if (left > right)
			return 1;
		return 0;
	}

	static function intOr(value:Null<Int>, fallback:Int):Int {
		if (value == null)
			return fallback;
		return value;
	}
}
