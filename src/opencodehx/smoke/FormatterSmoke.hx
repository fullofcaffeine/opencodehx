package opencodehx.smoke;

import genes.js.Async.await;
import haxe.DynamicAccess;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.format.FormatRuntime;
import opencodehx.format.FormatRuntime.FormatterCommand;
import opencodehx.format.FormatRuntime.FormatterContext;
import opencodehx.format.FormatRuntime.FormatterInfo;
import opencodehx.host.node.NodePath;

typedef FormatterCommandCapture = {
	final command:String;
	final args:Array<String>;
	final cwd:String;
	final env:DynamicAccess<String>;
}

class FormatterSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-format-"));
		try {
			await(statusConfig(root));
			await(formatFile(root));
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	static function statusConfig(root:String):Promise<Void> {
		final none = new FormatRuntime(context(root, "none"), false);
		eq((@:await none.status()).length, 0, "formatter disabled status empty");

		final builtins = new FormatRuntime(context(root, "builtins"), true);
		final builtinsStatus = @:await builtins.status();
		eq(hasFormatter(builtinsStatus, "gofmt", ".go"), true, "formatter true includes gofmt");

		final objectConfig = new FormatRuntime(context(root, "object"), {gofmt: {}});
		final objectStatus = @:await objectConfig.status();
		eq(hasFormatter(objectStatus, "gofmt", ".go"), true, "formatter object keeps gofmt");
		eq(findFormatter(objectStatus, "mix") != null, true, "formatter object keeps mix");

		final disabled = new FormatRuntime(context(root, "disabled"), {gofmt: {disabled: true}});
		final disabledStatus = @:await disabled.status();
		eq(findFormatter(disabledStatus, "gofmt") == null, true, "formatter disabled excludes gofmt");
		eq(findFormatter(disabledStatus, "mix") != null, true, "formatter disabled keeps mix");

		final ruffDisabled = new FormatRuntime(context(root, "ruff-disabled"), {ruff: {disabled: true}});
		final ruffDisabledStatus = @:await ruffDisabled.status();
		eq(findFormatter(ruffDisabledStatus, "ruff") == null, true, "formatter disables linked ruff");
		eq(findFormatter(ruffDisabledStatus, "uv") == null, true, "formatter disables linked uv");

		final uvDisabled = new FormatRuntime(context(root, "uv-disabled"), {uv: {disabled: true}});
		final uvDisabledStatus = @:await uvDisabled.status();
		eq(findFormatter(uvDisabledStatus, "ruff") == null, true, "formatter uv disables ruff");
		eq(findFormatter(uvDisabledStatus, "uv") == null, true, "formatter uv disables uv");
	}

	@:async
	static function formatFile(root:String):Promise<Void> {
		final captures:Array<FormatterCommandCapture> = [];
		final disabled = new FormatRuntime(context(root, "file-disabled"), false, null, captureRunner(captures));
		eq(@:await disabled.file(NodePath.join(root, "plain.txt")), false, "formatter file false when disabled");
		eq(captures.length, 0, "formatter disabled runs no commands");

		var active = 0;
		var maxActive = 0;
		final parallel:Array<FormatterInfo> = [
			asyncFormatter("one", [".parallel"], () -> {
				active += 1;
				maxActive = Std.int(Math.max(maxActive, active));
				return sleepCommand(20, ["one", "$FILE"]).then(command -> {
					active -= 1;
					return command;
				});
			}),
			asyncFormatter("two", [".parallel"], () -> {
				active += 1;
				maxActive = Std.int(Math.max(maxActive, active));
				return sleepCommand(20, ["two", "$FILE"]).then(command -> {
					active -= 1;
					return command;
				});
			}),
		];
		final parallelRuntime = new FormatRuntime(context(root, "parallel"), {one: {}, two: {}}, parallel, captureRunner(captures));
		eq(@:await parallelRuntime.file(NodePath.join(root, "test.parallel")), true, "formatter parallel file formatted");
		eq(maxActive, 2, "formatter enabled checks run in parallel");

		final sequentialCaptures:Array<FormatterCommandCapture> = [];
		final sequential = new FormatRuntime(context(root, "seq"), {
			first: {command: ["first", "$FILE"], extensions: [".seq"], environment: {ONE: "1"}},
			second: {command: ["second", "$FILE"], extensions: [".seq"]},
		}, [], captureRunner(sequentialCaptures));
		final file = NodePath.join(root, "test.seq");
		eq(@:await sequential.file(file), true, "formatter sequential file formatted");
		eq(sequentialCaptures.length, 2, "formatter sequential command count");
		eq(sequentialCaptures[0].command, "first", "formatter sequential first command");
		eq(sequentialCaptures[1].command, "second", "formatter sequential second command");
		eq(sequentialCaptures[0].args[0], file, "formatter substitutes file token");
		eq(sequentialCaptures[0].cwd, NodePath.join(root, "seq"), "formatter command cwd");
		eq(sequentialCaptures[0].env.get("ONE"), "1", "formatter command environment");

		final processDir = context(root, "process");
		final processFile = NodePath.join(processDir.directory, "test.seq");
		Fs.writeFileSync(processFile, "x");
		final processRuntime = new FormatRuntime(processDir, {
			first: {
				command: [
					"node",
					"-e",
					"const fs = require('fs'); const file = process.argv[1]; fs.writeFileSync(file, fs.readFileSync(file, 'utf8') + 'A')",
					"$FILE",
				],
				extensions: [".seq"],
			},
			second: {
				command: [
					"node",
					"-e",
					"const fs = require('fs'); const file = process.argv[1]; fs.writeFileSync(file, fs.readFileSync(file, 'utf8') + 'B')",
					"$FILE",
				],
				extensions: [".seq"],
			},
		}, []);
		eq(@:await processRuntime.file(processFile), true, "formatter process file formatted");
		eq(Fs.readFileSync(processFile, "utf8"), "xAB", "formatter process commands run sequentially");
	}

	static function context(root:String, name:String):FormatterContext {
		final dir = NodePath.join(root, name);
		Fs.mkdirSync(dir, {recursive: true});
		return {directory: dir, worktree: dir};
	}

	static function captureRunner(captures:Array<FormatterCommandCapture>) {
		return (command:FormatterCommand) -> {
			captures.push({
				command: command.command,
				args: command.args,
				cwd: command.cwd,
				env: command.env,
			});
			return Promise.resolve({code: 0});
		};
	}

	static function asyncFormatter(name:String, extensions:Array<String>, enabled:Void->Promise<Array<String>>):FormatterInfo {
		return {
			name: name,
			extensions: extensions,
			enabled: _ -> enabled(),
		};
	}

	static function sleepCommand(delayMs:Int, command:Array<String>):Promise<Array<String>> {
		return new Promise<Array<String>>((resolve, _) -> {
			WebTimers.setTimeout(() -> resolve(command), delayMs);
		});
	}

	static function findFormatter(statuses:Array<opencodehx.format.FormatRuntime.FormatterStatus>,
			name:String):Null<opencodehx.format.FormatRuntime.FormatterStatus> {
		for (item in statuses) {
			if (item.name == name)
				return item;
		}
		return null;
	}

	static function hasFormatter(statuses:Array<opencodehx.format.FormatRuntime.FormatterStatus>, name:String, ext:String):Bool {
		final item = findFormatter(statuses, name);
		return item != null && item.extensions.indexOf(ext) != -1;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
