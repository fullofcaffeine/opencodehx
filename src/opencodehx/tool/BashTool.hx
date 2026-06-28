package opencodehx.tool;

import js.lib.Error;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.KnownToolID;
import opencodehx.tool.ToolTypes.ToolCallInput;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolInputDecode;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolPermissionMetadata;
import opencodehx.tool.ToolTypes.ToolResultMetadata;

typedef BashToolInput = {
	final command:String;
	final description:String;
	final timeout:Null<Int>;
	final workdir:Null<String>;
}

class BashTool {
	static inline final DEFAULT_TIMEOUT = 120000;
	static inline final MAX_OUTPUT_BYTES = 30000;
	static inline final MAX_OUTPUT_LINES = 200;
	static inline final MAX_BUFFER = 1024 * 1024;

	public static function define():ToolDef {
		return ToolDefinition.typed(KnownToolID.Bash, "Execute a shell command through the Node host seam.", {
			parameters: [
				{
					name: "command",
					type: "string",
					required: true,
					description: "Command to execute"
				},
				{
					name: "description",
					type: "string",
					required: true,
					description: "Short description of the command"
				},
				{
					name: "timeout",
					type: "integer",
					required: false,
					description: "Timeout in milliseconds"
				},
				{
					name: "workdir",
					type: "string",
					required: false,
					description: "Working directory"
				},
			],
		}, decode, execute);
	}

	static function decode(raw:ToolCallInput):ToolInputDecode<BashToolInput> {
		final issues:Array<String> = [];
		final args = ToolValidation.record(raw.unknown(), issues);
		if (args == null)
			return Invalid(issues);
		final command = ToolValidation.requireString(args, "command", issues);
		final description = ToolValidation.requireString(args, "description", issues);
		final timeoutArg = ToolValidation.optionalInt(args, "timeout", issues);
		final workdirArg = ToolValidation.optionalString(args, "workdir", issues);
		return ToolValidation.finish(issues, {
			command: command,
			description: description,
			timeout: timeoutArg,
			workdir: workdirArg
		});
	}

	static function execute(input:BashToolInput, ctx:ToolContext):ToolResult {
		final timeout = input.timeout == null ? DEFAULT_TIMEOUT : input.timeout;
		if (timeout < 0)
			throw new ToolException(ExecutionFailed(KnownToolID.Bash, 'Invalid timeout value: ${timeout}. Timeout must be a positive number.'));
		final cwd = resolveWorkdir(ctx, input.workdir);
		final shell = NodeProcess.acceptableShell();
		final scan = BashCommandScanner.scan(ctx.directory, input.command, cwd, shell);
		final externalDirs = scan.externalDirs.copy();
		if (!opencodehx.file.FileSystem.contains(ctx.directory, cwd) && externalDirs.indexOf(cwd) == -1)
			externalDirs.push(cwd);
		if (externalDirs.length > 0) {
			final externalPatterns:Array<String> = [];
			for (dir in externalDirs)
				externalPatterns.push(ToolPaths.normalize(NodePath.join(dir, "*")));
			ToolPermission.require(KnownToolID.Bash, ctx, {
				permission: "external_directory",
				patterns: externalPatterns,
				always: externalPatterns,
				metadata: ToolPermissionMetadata.checked({})
			});
		}
		if (scan.patterns.length > 0) {
			ToolPermission.require(KnownToolID.Bash, ctx, {
				permission: "bash",
				patterns: scan.patterns,
				always: scan.always,
				metadata: ToolPermissionMetadata.checked({})
			});
		}

		final shellRun = NodeProcess.runShell({
			command: input.command,
			cwd: cwd,
			env: NodeProcess.env(),
			timeout: timeout,
			maxBuffer: MAX_BUFFER
		});
		return formatResult(input.description, shellRun.stdout, shellRun.stderr, shellRun.status, shellRun.signal, shellRun.error, timeout);
	}

	static function resolveWorkdir(ctx:ToolContext, value:Null<String>):String {
		final raw = value == null || value == "" ? ctx.directory : value;
		final absolute = NodePath.isAbsolute(raw) ? NodePath.resolve(raw, ".") : NodePath.resolve(ctx.directory, raw);
		if (!Fs.existsSync(absolute))
			throw new ToolException(ExecutionFailed(KnownToolID.Bash, 'No such workdir: ${absolute}'));
		if (!Fs.statSync(absolute).isDirectory())
			throw new ToolException(ExecutionFailed(KnownToolID.Bash, 'workdir must be a directory: ${absolute}'));
		return absolute;
	}

	static function formatResult(description:String, stdout:String, stderr:String, status:Null<Int>, signal:Null<String>, error:Null<Error>,
			timeout:Int):ToolResult {
		final raw = joinOutput(stdout, stderr);
		var output = raw == "" ? "(no output)" : raw;
		var truncated = false;
		final tailed = tail(output, MAX_OUTPUT_LINES, MAX_OUTPUT_BYTES);
		output = tailed.text;
		truncated = tailed.cut;
		if (truncated)
			output = "...output truncated...\n\n" + output;
		final meta:Array<String> = [];
		if (error != null && Std.string(Reflect.field(error, "code")) == "ETIMEDOUT") {
			meta.push('bash tool terminated command after exceeding timeout ${timeout} ms.');
		}
		if (signal != null && signal != "")
			meta.push('signal: ${signal}');
		if (meta.length > 0)
			output += "\n\n<bash_metadata>\n" + meta.join("\n") + "\n</bash_metadata>";
		final exit:Null<Int> = status == null ? null : status;
		return {
			title: description,
			output: output,
			metadata: ToolResultMetadata.checked({
				output: preview(raw),
				exit: exit,
				description: description,
				truncated: truncated,
				signal: signal,
			}),
		};
	}

	static function joinOutput(stdout:String, stderr:String):String {
		if (stdout == null)
			stdout = "";
		if (stderr == null)
			stderr = "";
		if (stdout == "")
			return stderr;
		if (stderr == "")
			return stdout;
		return stdout + stderr;
	}

	static function preview(text:String):String {
		if (text.length <= MAX_OUTPUT_BYTES)
			return text;
		return "...\n\n" + text.substr(text.length - MAX_OUTPUT_BYTES);
	}

	static function tail(text:String, maxLines:Int, maxBytes:Int):{text:String, cut:Bool} {
		final lines = text.split("\n");
		var start = lines.length - maxLines;
		if (start < 0)
			start = 0;
		var out = lines.slice(start).join("\n");
		var cut = start > 0;
		if (out.length > maxBytes) {
			out = out.substr(out.length - maxBytes);
			cut = true;
		}
		return {text: out, cut: cut};
	}
}
