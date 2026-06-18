package opencodehx.tool;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolResult;

typedef BashScan = {
	final pattern:String;
	final always:String;
	final externalDirs:Array<String>;
}

class BashTool {
	static inline final DEFAULT_TIMEOUT = 120000;
	static inline final MAX_OUTPUT_BYTES = 30000;
	static inline final MAX_OUTPUT_LINES = 200;
	static inline final MAX_BUFFER = 1024 * 1024;

	public static function define():ToolDef {
		return {
			id: "bash",
			description: "Execute a shell command through the Node host seam.",
			schema: {
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
			},
			execute: execute,
		};
	}

	static function execute(args:Dynamic, ctx:ToolContext):ToolResult {
		final issues:Array<String> = [];
		final command = ToolValidation.requireString(args, "command", issues);
		final description = ToolValidation.requireString(args, "description", issues);
		final timeoutArg = ToolValidation.optionalInt(args, "timeout", issues);
		final workdirArg = ToolValidation.optionalString(args, "workdir", issues);
		if (issues.length > 0)
			throw new ToolException(InvalidArguments("bash", issues));

		final timeout = timeoutArg == null ? DEFAULT_TIMEOUT : timeoutArg;
		if (timeout < 0)
			throw new ToolException(ExecutionFailed("bash", 'Invalid timeout value: ${timeout}. Timeout must be a positive number.'));
		final cwd = resolveWorkdir(ctx, workdirArg);
		final scan = scanCommand(ctx, command, cwd);
		if (scan.externalDirs.length > 0) {
			final externalPatterns:Array<String> = [];
			for (dir in scan.externalDirs)
				externalPatterns.push(ToolPaths.normalize(NodePath.join(dir, "*")));
			ToolPermission.require("bash", ctx, {
				permission: "external_directory",
				patterns: externalPatterns,
				always: externalPatterns,
				metadata: {}
			});
		}
		ToolPermission.require("bash", ctx, {
			permission: "bash",
			patterns: [scan.pattern],
			always: [scan.always],
			metadata: {}
		});

		final shellRun = NodeProcess.runShell({
			command: command,
			cwd: cwd,
			env: NodeProcess.env(),
			timeout: timeout,
			maxBuffer: MAX_BUFFER
		});
		return formatResult(description, shellRun.stdout, shellRun.stderr, shellRun.status, shellRun.signal, shellRun.error, timeout);
	}

	static function resolveWorkdir(ctx:ToolContext, value:Null<String>):String {
		final raw = value == null || value == "" ? ctx.directory : value;
		final absolute = NodePath.isAbsolute(raw) ? NodePath.resolve(raw, ".") : NodePath.resolve(ctx.directory, raw);
		if (!Fs.existsSync(absolute))
			throw new ToolException(ExecutionFailed("bash", 'No such workdir: ${absolute}'));
		if (!Fs.statSync(absolute).isDirectory())
			throw new ToolException(ExecutionFailed("bash", 'workdir must be a directory: ${absolute}'));
		return absolute;
	}

	static function scanCommand(ctx:ToolContext, command:String, cwd:String):BashScan {
		final first = firstToken(command);
		final always = first == "" ? command : first + " *";
		final externalDirs:Array<String> = [];
		if (!opencodehx.file.FileSystem.contains(ctx.directory, cwd))
			externalDirs.push(cwd);
		for (path in likelyPathArgs(command)) {
			final absolute = NodePath.isAbsolute(path) ? NodePath.resolve(path, ".") : NodePath.resolve(cwd, path);
			if (!opencodehx.file.FileSystem.contains(ctx.directory, absolute)) {
				final dir = Fs.existsSync(absolute) && Fs.statSync(absolute).isDirectory() ? absolute : NodePath.dirname(absolute);
				if (externalDirs.indexOf(dir) == -1)
					externalDirs.push(dir);
			}
		}
		return {pattern: command, always: always, externalDirs: externalDirs};
	}

	static function likelyPathArgs(command:String):Array<String> {
		final tokens = shellWords(command);
		if (tokens.length == 0)
			return [];
		final fileCommands = ["cat", "cp", "mv", "rm", "mkdir", "touch", "chmod", "chown", "ls"];
		if (fileCommands.indexOf(tokens[0]) == -1)
			return [];
		final paths:Array<String> = [];
		for (i in 1...tokens.length) {
			final token = tokens[i];
			if (StringTools.startsWith(token, "-"))
				continue;
			if (tokens[0] == "chmod" && StringTools.startsWith(token, "+"))
				continue;
			paths.push(token);
		}
		return paths;
	}

	static function shellWords(command:String):Array<String> {
		final words:Array<String> = [];
		var current = "";
		var quote = "";
		var i = 0;
		while (i < command.length) {
			final char = command.charAt(i);
			if (quote != "") {
				if (char == quote) {
					quote = "";
				} else {
					current += char;
				}
			} else if (char == "'" || char == '"') {
				quote = char;
			} else if (char == " " || char == "\t" || char == "\n") {
				if (current != "") {
					words.push(current);
					current = "";
				}
			} else {
				current += char;
			}
			i++;
		}
		if (current != "")
			words.push(current);
		return words;
	}

	static function firstToken(command:String):String {
		final words = shellWords(command);
		return words.length == 0 ? "" : words[0];
	}

	static function formatResult(description:String, stdout:String, stderr:String, status:Null<Int>, signal:Null<String>, error:Dynamic,
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
			metadata: {
				output: preview(raw),
				exit: exit,
				description: description,
				truncated: truncated,
				signal: signal,
			},
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
