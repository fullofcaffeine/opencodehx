package opencodehx.smoke;

import genes.js.Async.await;
import haxe.Json;
import js.lib.Promise;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.ChildProcessHandle;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.tool.BashCommandScanner;
import opencodehx.tool.BashCommandScanner.BashScan;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolPaths;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolPermissionDecision;
import opencodehx.tool.ToolTypes.ToolPermissionRequest;

class ToolSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-tool-"));
		try {
			await(BashCommandScanner.preload());
			fixture(root);
			final registry = new ToolRegistry();
			registrySurface(registry);
			shellSelectionParity();
			await(killTreeParity(root));
			errorShapes(registry, context(root));
			permissionShapes(registry, root);
			bashExec(registry, context(root));
			readExec(registry, context(root));
			globExec(registry, context(root));
			grepExec(registry, context(root));
			writeExec(registry, context(root));
			editExec(registry, context(root));
			applyPatchExec(registry, context(root));
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup must run for arbitrary Haxe/JS thrown values, then
			// rethrow the original failure so the runner preserves the cause.
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function fixture(root:String):Void {
		write(root, "src/a.ts", "export const needle = 1;\n");
		write(root, "src/b.txt", "needle text\n");
		write(root, "src/c.ts", "export const other = 2;\n");
	}

	static function registrySurface(registry:ToolRegistry):Void {
		eq(registry.ids().join(","), "apply_patch,bash,edit,glob,grep,invalid,read,write", "builtin ids");
		eq(registry.all().length, 8, "builtin count");
		eq(registry.all({disabled: ["grep"]}).length, 7, "filtered count");
		eq(registry.get("glob").schema.parameters[0].name, "pattern", "glob schema");
	}

	static function shellSelectionParity():Void {
		eq(NodeProcess.shellNameForPlatform("/bin/bash", "linux"), "bash", "shell name posix");
		eq(NodeProcess.shellNameForPlatform("C:/tools/NU.EXE", "win32"), "nu", "shell name windows extension");
		eq(NodeProcess.windowsPathForPlatform("/cygdrive/c/Users/test", "win32"), "C:/Users/test", "cygwin path conversion");
		eq(NodeProcess.windowsPathForPlatform("/mnt/z/dev/project", "win32"), "Z:/dev/project", "wsl path conversion");
		eq(NodeProcess.selectPreferred({
			platform: "win32",
			shell: "/usr/bin/bash",
			gitBash: "C:/Program Files/Git/bin/bash.exe",
			pwsh: "C:/Program Files/PowerShell/7/pwsh.exe",
			comspec: "C:/Windows/System32/cmd.exe",
		}), "C:/Program Files/Git/bin/bash.exe",
			"windows preferred resolves posix bash to git bash");
		eq(NodeProcess.selectAcceptable({
			platform: "win32",
			shell: "NU.EXE",
			pwsh: "C:/Program Files/PowerShell/7/pwsh.exe",
			comspec: "C:/Windows/System32/cmd.exe",
		}), "C:/Program Files/PowerShell/7/pwsh.exe", "windows acceptable rejects nu");
		eq(NodeProcess.selectPreferred({
			platform: "win32",
			shell: "pwsh.exe",
			pwsh: "C:/Program Files/PowerShell/7/pwsh.exe",
		}), "C:/Program Files/PowerShell/7/pwsh.exe",
			"windows preferred resolves bare powershell");
		eq(NodeProcess.selectPreferred({
			platform: "win32",
			comspec: "C:/Windows/System32/cmd.exe",
		}), "C:/Windows/System32/cmd.exe", "windows fallback uses comspec");
		eq(NodeProcess.selectPreferred({
			platform: "darwin",
			bash: "/usr/local/bin/bash",
		}), "/bin/zsh", "darwin fallback uses zsh");
		eq(NodeProcess.selectAcceptable({
			platform: "linux",
			shell: "fish",
			bash: "/usr/bin/bash",
		}), "/usr/bin/bash", "linux acceptable rejects fish");
	}

	@:async
	static function killTreeParity(root:String):Promise<Void> {
		if (NodeProcess.platform() == "win32")
			return;
		final ticks = NodePath.join(root, "kill-tree-ticks.txt");
		Fs.writeFileSync(ticks, "");
		final script = 'const {spawn}=require("node:child_process");'
			+ 'const file=process.argv[1];'
			+ 'const child=spawn(process.execPath,["-e",'
			+ Json.stringify('const fs=require("node:fs");const file=process.argv[1];setInterval(()=>fs.appendFileSync(file,"tick"),25);')
			+ ',file],{stdio:"ignore"});'
			+ 'child.unref();'
			+ 'setInterval(()=>{},1000);';
		final proc = ChildProcess.spawn("node", ["-e", script, ticks], {
			detached: true,
			stdio: "ignore",
			windowsHide: true,
		});
		var exited = false;
		proc.once("exit", _ -> exited = true);
		try {
			await(waitForFileGrowth(ticks, "killTree child tick"));
			await(NodeProcess.killTree(proc, {exited: () -> exited}));
			await(sleep(250));
			final afterKill = Fs.readFileSync(ticks, "utf8");
			await(sleep(150));
			eq(Fs.readFileSync(ticks, "utf8"), afterKill, "killTree stops descendant output");
		} catch (error:Dynamic) {
			cleanupProcess(proc);
			throw error;
		}
	}

	static function errorShapes(registry:ToolRegistry, ctx:ToolContext):Void {
		expectToolFailure(() -> registry.get("missing"), function(failure) {
			return switch failure {
				case UnknownTool(id): id == "missing";
				case _: false;
			}
		}, "unknown tool");

		expectToolFailure(() -> registry.get("grep", {disabled: ["grep"]}), function(failure) {
			return switch failure {
				case DisabledTool(id): id == "grep";
				case _: false;
			}
		}, "disabled tool");

		expectToolFailure(() -> registry.execute("grep", {}, ctx), function(failure) {
			return switch failure {
				case InvalidArguments(id, issues): id == "grep" && issues.join("\n").indexOf("pattern") != -1;
				case _: false;
			}
		}, "invalid args");

		final invalid = registry.execute("invalid", {tool: "grep", error: "bad pattern"}, ctx);
		eq(invalid.title, "Invalid Tool", "invalid title");
		eq(invalid.output.indexOf("bad pattern") != -1, true, "invalid output");
	}

	static function permissionShapes(registry:ToolRegistry, root:String):Void {
		final seen:Array<String> = [];
		final ctx = context(root, request -> {
			seen.push(request.permission + ":" + request.patterns.join(","));
			return {allowed: false, reason: "blocked by smoke"};
		});
		expectToolFailure(() -> registry.execute("read", {filePath: "src/a.ts"}, ctx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "read" && message.indexOf("blocked") != -1;
				case _: false;
			}
		}, "read permission denied");
		eq(seen[0], "read:src/a.ts", "permission request shape");

		final deniedBash = context(root, request -> {
			return {allowed: false, reason: "no shell"};
		});
		expectToolFailure(() -> registry.execute("bash", {
			command: "echo denied",
			description: "Denied command"
		}, deniedBash), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "bash" && message.indexOf("no shell") != -1;
				case _: false;
			}
		}, "bash permission denied");
	}

	static function bashExec(registry:ToolRegistry, ctx:ToolContext):Void {
		treeSitterScanner(ctx);

		final hello = registry.execute("bash", {
			command: "printf hello",
			description: "Print hello"
		}, ctx);
		eq(hello.title, "Print hello", "bash title");
		eq(hello.output, "hello", "bash output");
		eq(Reflect.field(hello.metadata, "exit"), 0, "bash exit");

		final cwd = registry.execute("bash", {
			command: "node -e \"process.stdout.write(process.cwd())\"",
			workdir: "src",
			description: "Show cwd"
		}, ctx);
		eq(StringTools.endsWith(ToolPaths.normalize(cwd.output), ToolPaths.normalize(NodePath.join(NodePath.basename(ctx.directory), "src"))), true,
			"bash cwd");

		final env = registry.execute("bash", {
			command: "node -e \"process.stdout.write(process.env.PATH ? 'env-ok' : 'missing')\"",
			description: "Show env"
		}, ctx);
		eq(env.output, "env-ok", "bash env");

		final truncated = registry.execute("bash", {
			command: "node -e \"process.stdout.write('x'.repeat(31000))\"",
			description: "Large output"
		}, ctx);
		eq(Reflect.field(truncated.metadata, "truncated"), true, "bash truncated metadata");
		eq(truncated.output.indexOf("...output truncated...") == 0, true, "bash truncation output");

		final timeout = registry.execute("bash", {
			command: "node -e \"setTimeout(()=>{}, 200)\"",
			timeout: 20,
			description: "Timeout command"
		}, ctx);
		eq(timeout.output.indexOf("exceeding timeout 20 ms") != -1, true, "bash timeout metadata");

		final externalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "external blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute("bash", {
			command: "pwd",
			workdir: Os.tmpdir(),
			description: "External pwd"
		}, externalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "bash" && message.indexOf("external blocked") != -1;
				case _: false;
			}
		}, "bash external directory denied");
	}

	static function treeSitterScanner(ctx:ToolContext):Void {
		eq(BashCommandScanner.isPreloaded(), true, "bash scanner preloaded");
		final multi = BashCommandScanner.scan(ctx.directory, "echo foo && echo bar", ctx.directory, "/bin/bash");
		eq(multi.usedTreeSitter, true, "bash scanner tree-sitter path");
		eq(multi.patterns.indexOf("echo foo") != -1, true, "bash scanner first command");
		eq(multi.patterns.indexOf("echo bar") != -1, true, "bash scanner second command");

		if (NodeProcess.platform() != "win32") {
			final outside = NodePath.join(Os.tmpdir(), "opencodehx-tree-sitter-outside.txt");
			final nested = BashCommandScanner.scan(ctx.directory, 'echo $(cat "${outside}")', ctx.directory, "/bin/bash");
			eq(nested.patterns.indexOf('cat "${outside}"') != -1, true, "bash scanner nested command");
			eq(nested.externalDirs.indexOf(Os.tmpdir()) != -1, true, "bash scanner nested external path");
		}
		powerShellScannerParity();
	}

	static function powerShellScannerParity():Void {
		final project = "C:/work/project";
		final shell = "C:/Program Files/PowerShell/7/pwsh.exe";
		expectExternalDir(BashCommandScanner.scan(project, 'Get-Content "C:../outside.txt"', project, shell, "win32"),
			NodePath.windowsDirname(NodePath.windowsResolve(project, "C:../outside.txt")), "powershell drive-relative path");
		expectExternalDir(BashCommandScanner.scan(project, "Get-Content \"$" + "PWD/../outside.txt\"", project, shell, "win32"),
			NodePath.windowsDirname(NodePath.windowsResolve(project, "../outside.txt")), "powershell pwd path");
		expectExternalDir(BashCommandScanner.scan(project, "Get-Content \"$" + "PSHOME/outside.txt\"", project, shell, "win32"),
			"C:\\Program Files\\PowerShell\\7", "powershell pshome path");
		expectExternalDir(BashCommandScanner.scan(project, "Get-Content FileSystem::C:/Windows/win.ini", project, shell, "win32"), "C:\\Windows",
			"powershell filesystem provider path");
		final conditional = BashCommandScanner.scan(project, "Write-Host foo; if ($?) { Write-Host bar }", project, shell, "win32");
		eq(conditional.patterns.indexOf("Write-Host foo") != -1, true, "powershell conditional first command");
		eq(conditional.patterns.indexOf("Write-Host bar") != -1, true, "powershell conditional nested command");
		eq(conditional.always.indexOf("Write-Host *") != -1, true, "powershell conditional arity");
	}

	static function expectExternalDir(scan:BashScan, expected:String, label:String):Void {
		eq(scan.usedTreeSitter, true, label + " used parser");
		eq(scan.externalDirs.indexOf(expected) != -1, true, label + " external dir");
	}

	static function waitForFileGrowth(file:String, label:String):Promise<Void> {
		return new Promise<Void>((resolve, reject) -> {
			final resolveVoid:Void->Void = cast resolve;
			waitForFileGrowthTick(file, label, 0, resolveVoid, reject);
		});
	}

	static function waitForFileGrowthTick(file:String, label:String, elapsed:Int, resolve:Void->Void, reject:Dynamic->Void):Void {
		try {
			if (Fs.readFileSync(file, "utf8").length > 0) {
				resolve();
				return;
			}
			if (elapsed > 2000) {
				reject('timeout waiting for ${label}');
				return;
			}
			WebTimers.setTimeout(() -> waitForFileGrowthTick(file, label, elapsed + 25, resolve, reject), 25);
		} catch (error:Dynamic) {
			reject(error);
		}
	}

	static function sleep(ms:Int):Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			final resolveVoid:Void->Void = cast resolve;
			WebTimers.setTimeout(resolveVoid, ms);
		});
	}

	static function cleanupProcess(proc:ChildProcessHandle):Void {
		try {
			proc.kill("SIGKILL");
		} catch (_:Dynamic) {}
	}

	static function readExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final file = registry.execute("read", {filePath: "src/a.ts", limit: 1}, ctx);
		eq(Reflect.field(file.metadata, "truncated"), false, "read file not truncated");
		eq(file.output.indexOf("<type>file</type>") != -1, true, "read file type");
		eq(file.output.indexOf("1: export const needle = 1;") != -1, true, "read line");

		final dir = registry.execute("read", {filePath: "src"}, ctx);
		eq(dir.output.indexOf("<type>directory</type>") != -1, true, "read directory type");
		eq(dir.output.indexOf("a.ts") != -1, true, "read directory entry");

		expectToolFailure(() -> registry.execute("read", {filePath: "../outside.ts"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "read" && message.indexOf("escapes project") != -1;
				case _: false;
			}
		}, "read escape failure");
	}

	static function globExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final result = registry.execute("glob", {pattern: "*.ts", path: "src"}, ctx);
		eq(Reflect.field(result.metadata, "count"), 2, "glob count");
		eq(result.output.indexOf("a.ts") != -1, true, "glob output a");
		eq(result.output.indexOf("b.txt") == -1, true, "glob excludes txt");

		expectToolFailure(() -> registry.execute("glob", {pattern: "*.ts", path: "src/a.ts"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "glob" && message.indexOf("glob path must be a directory") != -1;
				case _: false;
			}
		}, "glob file path failure");
	}

	static function grepExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final result = registry.execute("grep", {pattern: "needle", path: "src", include: "*.ts"}, ctx);
		eq(Reflect.field(result.metadata, "matches"), 1, "grep matches");
		eq(result.output.indexOf("Found 1 matches") != -1, true, "grep found");
		eq(result.output.indexOf("Line 1:") != -1, true, "grep line");

		final exact = registry.execute("grep", {pattern: "needle", path: "src/b.txt"}, ctx);
		eq(Reflect.field(exact.metadata, "matches"), 1, "grep exact file");

		final none = registry.execute("grep", {pattern: "definitely-not-here", path: "src"}, ctx);
		eq(none.output, "No files found", "grep no matches");
	}

	static function writeExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final result = registry.execute("write", {filePath: "src/new.txt", content: "fresh\n"}, ctx);
		eq(result.output, "Wrote file successfully.", "write output");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/new.txt"), "utf8"), "fresh\n", "write content");
		eq(Reflect.field(result.metadata, "exists"), false, "write existed metadata");
	}

	static function editExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final single = registry.execute("edit", {filePath: "src/a.ts", oldString: "needle", newString: "pin"}, ctx);
		eq(single.output, "Edit applied successfully.", "edit output");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/a.ts"), "utf8").indexOf("pin") != -1, true, "edit content");

		write(ctx.directory, "src/repeat.txt", "x\nx\n");
		registry.execute("edit", {
			filePath: "src/repeat.txt",
			oldString: "x",
			newString: "y",
			replaceAll: true
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/repeat.txt"), "utf8"), "y\ny\n", "edit replace all");

		expectToolFailure(() -> registry.execute("edit", {filePath: "src/repeat.txt", oldString: "y", newString: "z"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "edit" && message.indexOf("multiple matches") != -1;
				case _: false;
			}
		}, "edit multiple failure");

		write(ctx.directory, "src/line-trimmed.txt", "function run() {\n  return 1;\n}\n");
		registry.execute("edit", {
			filePath: "src/line-trimmed.txt",
			oldString: "function run() {\nreturn 1;\n}",
			newString: "function run() {\n  return 2;\n}"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/line-trimmed.txt"), "utf8"), "function run() {\n  return 2;\n}\n", "edit line-trimmed");

		write(ctx.directory, "src/block-anchor.txt", "start\nactual middle\nfinish\n");
		registry.execute("edit", {
			filePath: "src/block-anchor.txt",
			oldString: "start\nstale middle\nfinish",
			newString: "start\nfresh middle\nfinish"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/block-anchor.txt"), "utf8"), "start\nfresh middle\nfinish\n", "edit block anchor");

		write(ctx.directory, "src/whitespace.txt", "const pair = alpha   +\t beta;\n");
		registry.execute("edit", {
			filePath: "src/whitespace.txt",
			oldString: "const pair = alpha + beta;",
			newString: "const pair = gamma;"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/whitespace.txt"), "utf8"), "const pair = gamma;\n", "edit whitespace-normalized");

		write(ctx.directory, "src/indent.txt", "    alpha\n      beta\n    gamma\n");
		registry.execute("edit", {
			filePath: "src/indent.txt",
			oldString: "alpha\n  beta\ngamma",
			newString: "delta"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/indent.txt"), "utf8"), "delta\n", "edit indentation-flexible");

		write(ctx.directory, "src/escaped.txt", "const value = \"a\\nb\";\n");
		registry.execute("edit", {
			filePath: "src/escaped.txt",
			oldString: "const value = \"a\\\\nb\";",
			newString: "const value = \"c\";"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/escaped.txt"), "utf8"), "const value = \"c\";\n", "edit escape-normalized");
	}

	static function applyPatchExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final patch = [
			"*** Begin Patch",
			"*** Add File: src/patch-added.txt",
			"+one",
			"+two",
			"*** Update File: src/c.ts",
			"@@",
			"-export const other = 2;",
			"+export const other = 3;",
			"*** Delete File: src/b.txt",
			"*** End Patch",
		].join("\n");
		final result = registry.execute("apply_patch", {patchText: patch}, ctx);
		eq(result.output.indexOf("A src/patch-added.txt") != -1, true, "patch add summary");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/patch-added.txt"), "utf8"), "one\ntwo\n", "patch add content");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/c.ts"), "utf8").indexOf("other = 3") != -1, true, "patch update content");
		eq(Fs.existsSync(NodePath.join(ctx.directory, "src/b.txt")), false, "patch delete content");
		final files = cast Reflect.field(result.metadata, "files");
		eq(Reflect.field(files[0], "type"), "add", "patch metadata type");

		write(ctx.directory, "src/move-from.txt", "move me\n");
		registry.execute("apply_patch", {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/move-from.txt",
				"*** Move to: src/moved/move-to.txt",
				"@@",
				"-move me",
				"+moved",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.existsSync(NodePath.join(ctx.directory, "src/move-from.txt")), false, "patch move removes source");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/moved/move-to.txt"), "utf8"), "moved\n", "patch move writes target");

		write(ctx.directory, "src/eof.txt", "start\nmarker\nmiddle\nmarker\nend\n");
		registry.execute("apply_patch", {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/eof.txt",
				"@@",
				"-marker",
				"-end",
				"+marker-changed",
				"+end",
				"*** End of File",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/eof.txt"), "utf8"), "start\nmarker\nmiddle\nmarker-changed\nend\n", "patch EOF anchor");

		registry.execute("apply_patch", {
			patchText: "cat <<'EOF'\n*** Begin Patch\n*** Add File: src/heredoc.txt\n+wrapped\n*** End Patch\nEOF"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/heredoc.txt"), "utf8"), "wrapped\n", "patch heredoc");

		write(ctx.directory, "src/unicode.txt", "He said \u201Chello\u201D\nsome\u2014dash\nend\n");
		registry.execute("apply_patch", {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/unicode.txt",
				"@@",
				"-He said \"hello\"",
				"+He said \"hi\"",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/unicode.txt"), "utf8"), "He said \"hi\"\nsome\u2014dash\nend\n", "patch unicode-normalized");

		expectToolFailure(() -> registry.execute("apply_patch", {patchText: "*** Begin Patch\n*** Frobnicate File: foo\n*** End Patch"}, ctx),
			function(failure) {
				return switch failure {
					case ExecutionFailed(id, message): id == "apply_patch" && message.indexOf("no hunks found") != -1;
					case _: false;
				}
			}, "patch malformed header");

		expectToolFailure(() -> registry.execute("apply_patch", {
			patchText: "*** Begin Patch\n*** Add File: src/should-not-exist.txt\n+hello\n*** Update File: src/missing.txt\n@@\n-old\n+new\n*** End Patch"
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "apply_patch" && message.indexOf("Failed to read file to update") != -1;
				case _: false;
			}
		}, "patch verification no side effects");
		eq(Fs.existsSync(NodePath.join(ctx.directory, "src/should-not-exist.txt")), false, "patch no side effects");
	}

	static function context(root:String, ?ask:(ToolPermissionRequest) -> ToolPermissionDecision):ToolContext {
		return {
			directory: root,
			worktree: root,
			sessionID: "ses_tool",
			messageID: "msg_tool",
			agent: "build",
			ask: ask,
		};
	}

	static function write(root:String, relative:String, content:String):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function expectToolFailure(run:() -> Void, matches:ToolFailure->Bool, label:String):Void {
		try {
			run();
		} catch (error:ToolException) {
			if (matches(error.failure))
				return;
			throw '${label}: unexpected failure ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
