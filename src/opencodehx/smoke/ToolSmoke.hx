package opencodehx.smoke;

import genes.js.Async.await;
import haxe.Json;
import js.lib.Promise;
import opencodehx.bus.BusRuntime;
import opencodehx.externs.node.Buffer;
import opencodehx.externs.node.Buffer.NodeBufferData;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.ChildProcessHandle;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.externs.node.Url;
import opencodehx.file.FileToolEvents;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.session.SessionInstructionClaims;
import opencodehx.tool.BashCommandScanner;
import opencodehx.tool.BashCommandScanner.BashScan;
import opencodehx.tool.SkillTool;
import opencodehx.tool.ToolDefinition;
import opencodehx.tool.ToolBom;
import opencodehx.tool.ToolError.ToolException;
import opencodehx.tool.ToolError.ToolFailure;
import opencodehx.tool.ToolPaths;
import opencodehx.tool.ToolRegistry;
import opencodehx.tool.ToolTypes.ToolContext;
import opencodehx.tool.ToolTypes.ToolDef;
import opencodehx.tool.ToolTypes.ToolIDs;
import opencodehx.tool.ToolTypes.ToolPermissionDecision;
import opencodehx.tool.ToolTypes.ToolPermissionRequest;
import opencodehx.tool.ToolTypes.ToolResult;
import opencodehx.tool.ToolTypes.ToolResultAttachment;
import opencodehx.tool.ToolTypes.ToolResultMetadata;
import opencodehx.tool.QuestionTool;
import opencodehx.tool.Truncate;
import opencodehx.tool.WebFetchTool;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.question.QuestionRuntime.QuestionRequest;
import opencodehx.question.QuestionRuntime.QuestionService;
import opencodehx.smoke.SmokeCleanup.withCleanupAsync;

class ToolSmoke {
	@:async
	public static function run():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-tool-"));
		await(withCleanupAsync(() -> runAll(root), () -> Fs.rmSync(root, {recursive: true, force: true})));
	}

	@:async
	static function runAll(root:String):Promise<Void> {
		await(BashCommandScanner.preload());
		fixture(root);
		final registry = new ToolRegistry();
		toolDefinitionFresh();
		registrySurface(registry);
		registryCustomTools(root);
		truncateRuntime(root);
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
		await(webFetchExec(context(root)));
		await(questionExec(context(root)));
		await(skillExec(context(root)));
	}

	static function fixture(root:String):Void {
		write(root, "src/a.ts", "export const needle = 1;\n");
		write(root, "src/b.txt", "needle text\n");
		write(root, "src/c.ts", "export const other = 2;\n");
	}

	static function registrySurface(registry:ToolRegistry):Void {
		eq(registry.ids().join(","), "apply_patch,bash,edit,glob,grep,invalid,read,write", "builtin ids");
		eq(registry.all().length, 8, "builtin count");
		eq(registry.all({disabled: [ToolIDs.known("grep")]}).length, 7, "filtered count");
		eq(registry.get(ToolIDs.known("glob")).schema.parameters[0].name, "pattern", "glob schema");
	}

	static function registryCustomTools(root:String):Void {
		final singular = NodePath.join(root, "custom-singular");
		write(singular, ".opencode/tool/hello.ts", "export default {description:'hello',args:{},execute(){return 'hello'}};\n");
		final singularRegistry = ToolRegistry.withProjectCustomTools(singular);
		eq(singularRegistry.ids().indexOf("hello") != -1, true, "singular custom tool id");
		eq(singularRegistry.get("hello").schema.parameters.length, 0, "singular custom tool schema");

		final plural = NodePath.join(root, "custom-plural");
		write(plural, ".opencode/tools/hello.ts", "export default {description:'hello',args:{},execute(){return 'hello'}};\n");
		final pluralRegistry = ToolRegistry.withProjectCustomTools(plural);
		eq(pluralRegistry.ids().indexOf("hello") != -1, true, "plural custom tool id");

		final dependency = NodePath.join(root, "custom-dependency");
		write(dependency, ".opencode/package.json", "{\"dependencies\":{\"cowsay\":\"latest\"}}\n");
		write(dependency, ".opencode/package-lock.json", "{\"packages\":{}}\n");
		write(dependency, ".opencode/node_modules/cowsay/package.json", "{\"type\":\"module\"}\n");
		write(dependency, ".opencode/node_modules/cowsay/index.js", "export function say(){return 'moo'};\n");
		write(dependency, ".opencode/tools/cowsay.ts", "import {say} from 'cowsay';\nexport default {description:'cow',args:{},execute(){return say()}};\n");
		final dependencyRegistry = ToolRegistry.withProjectCustomTools(dependency);
		eq(dependencyRegistry.ids().indexOf("cowsay") != -1, true, "dependency custom tool id");
		expectToolFailure(() -> dependencyRegistry.execute("cowsay", {}, context(dependency)), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "cowsay" && message.indexOf("dynamic loading") != -1;
				case _: false;
			}
		}, "custom tool execution deferred");
	}

	static function toolDefinitionFresh():Void {
		final original = simpleTool("source");
		final originalExecute = original.execute;
		final objectInfo = ToolDefinition.fromObject("object-tool", original);
		final first = objectInfo.init();
		final second = objectInfo.init();
		eq(objectInfo.id, "object-tool", "object-defined tool info id");
		eq(first.id, "object-tool", "object-defined tool clone id");
		eq(original.id, "source", "object-defined source id preserved");
		eq(original.execute == originalExecute, true, "object-defined source execute preserved");
		eq(first == second, false, "object-defined fresh tool objects");
		eq(first.schema == second.schema, false, "object-defined fresh schemas");
		eq(first.schema.parameters == second.schema.parameters, false, "object-defined fresh parameter arrays");

		var factoryCalls = 0;
		final factoryInfo = ToolDefinition.fromFactory("factory-tool", () -> {
			factoryCalls++;
			return simpleTool('factory-${factoryCalls}');
		});
		final factoryFirst = factoryInfo.init();
		final factorySecond = factoryInfo.init();
		eq(factoryInfo.id, "factory-tool", "factory-defined tool info id");
		eq(factoryFirst == factorySecond, false, "factory-defined fresh tool objects");
		eq(factoryFirst.id, "factory-1", "factory-defined first id");
		eq(factorySecond.id, "factory-2", "factory-defined second id");
	}

	static function truncateRuntime(root:String):Void {
		final dir = NodePath.join(root, "tool-output");
		final truncate = new Truncate(dir);
		eq(Truncate.MAX_LINES, 2000, "truncate default max lines");
		eq(Truncate.MAX_BYTES, 50 * 1024, "truncate default max bytes");
		eq(StringTools.endsWith(Truncate.DIR, NodePath.join("opencode", "tool-output")), true, "truncate default dir");
		eq(Truncate.GLOB, NodePath.join(Truncate.DIR, "*"), "truncate glob path");

		final unchanged = truncate.output("line1\nline2\nline3");
		eq(unchanged.truncated, false, "truncate unchanged flag");
		eq(unchanged.content, "line1\nline2\nline3", "truncate unchanged content");
		eq(unchanged.outputPath == null, true, "truncate unchanged no output path");

		final lines = numberedLines(100);
		final byLines = truncate.output(lines, {maxLines: 10});
		eq(byLines.truncated, true, "truncate line flag");
		eq(byLines.content.indexOf("line0") != -1, true, "truncate head includes first line");
		eq(byLines.content.indexOf("line9") != -1, true, "truncate head includes limit line");
		eq(byLines.content.indexOf("line99") == -1, true, "truncate head omits tail line");
		eq(byLines.content.indexOf("...90 lines truncated...") != -1, true, "truncate line message");
		final byLinesPath = present(byLines.outputPath, "truncate line output path");
		eq(NodePath.basename(byLinesPath).indexOf("tool_") == 0, true, "truncate line output file name");
		eq(Fs.readFileSync(byLinesPath, "utf8"), lines, "truncate writes full line output");
		eq(byLines.content.indexOf("Use Grep to search") != -1, true, "truncate grep hint");
		eq(byLines.content.indexOf("Task tool") == -1, true, "truncate no task hint by default");

		final byBytes = truncate.output(repeat("a", 1000), {maxBytes: 100});
		eq(byBytes.truncated, true, "truncate byte flag");
		eq(byBytes.content.indexOf("bytes truncated...") != -1, true, "truncate byte message");

		final tail = truncate.output(numberedLines(10), {maxLines: 3, direction: "tail"});
		eq(tail.content.indexOf("line7") != -1, true, "truncate tail includes line7");
		eq(tail.content.indexOf("line9") != -1, true, "truncate tail includes line9");
		eq(tail.content.indexOf("line0") == -1, true, "truncate tail omits line0");
		eq(StringTools.startsWith(tail.content, "...7 lines truncated..."), true, "truncate tail prefix");

		final taskRules:Array<PermissionRule> = [{permission: "task", pattern: "*", action: "allow"}];
		final taskHint = truncate.output(lines, {maxLines: 10}, {permission: taskRules});
		eq(taskHint.content.indexOf("Task tool") != -1, true, "truncate task hint");
		eq(taskHint.content.indexOf("Do NOT read the full file yourself") != -1, true, "truncate task delegation hint");

		final taskDenied:Array<PermissionRule> = [{permission: "task", pattern: "*", action: "deny"}];
		final noTaskHint = truncate.output(lines, {maxLines: 10}, {permission: taskDenied});
		eq(noTaskHint.content.indexOf("Task tool") == -1, true, "truncate denied task hint omitted");
		eq(noTaskHint.content.indexOf("Use Grep to search") != -1, true, "truncate denied grep hint");

		final now = 2000000000000.0;
		Fs.mkdirSync(dir, {recursive: true});
		final old = NodePath.join(dir, 'tool_${Math.floor(now - 10 * 24 * 60 * 60 * 1000)}_old.txt');
		final recent = NodePath.join(dir, 'tool_${Math.floor(now - 3 * 24 * 60 * 60 * 1000)}_recent.txt');
		final ignored = NodePath.join(dir, "note.txt");
		Fs.writeFileSync(old, "old");
		Fs.writeFileSync(recent, "recent");
		Fs.writeFileSync(ignored, "ignored");
		truncate.cleanup(now);
		eq(Fs.existsSync(old), false, "truncate cleanup removes old tool file");
		eq(Fs.existsSync(recent), true, "truncate cleanup keeps recent tool file");
		eq(Fs.existsSync(ignored), true, "truncate cleanup ignores non-tool file");
	}

	static function simpleTool(id:String):ToolDef {
		return {
			id: id,
			description: "test tool",
			schema: {
				parameters: [
					{
						name: "input",
						type: "string",
						required: true,
						description: "Test input",
					}
				],
			},
			execute: (_, _) -> {
				title: "test",
				output: "ok",
				metadata: ToolResultMetadata.checked({}),
			},
		};
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

		expectToolFailure(() -> registry.get(ToolIDs.known("grep"), {disabled: [ToolIDs.known("grep")]}), function(failure) {
			return switch failure {
				case DisabledTool(id): id == "grep";
				case _: false;
			}
		}, "disabled tool");

		expectToolFailure(() -> registry.execute(ToolIDs.known("grep"), {}, ctx), function(failure) {
			return switch failure {
				case InvalidArguments(id, issues): id == "grep" && issues.join("\n").indexOf("pattern") != -1;
				case _: false;
			}
		}, "invalid args");

		expectToolFailure(() -> registry.execute(ToolIDs.known("grep"), "not an object", ctx), function(failure) {
			return switch failure {
				case InvalidArguments(id, issues): id == "grep" && issues.join("\n").indexOf("arguments: expected object") != -1;
				case _: false;
			}
		}, "non-object args");

		final invalid = registry.execute(ToolIDs.known("invalid"), {tool: ToolIDs.known("grep"), error: "bad pattern"}, ctx);
		eq(invalid.title, "Invalid Tool", "invalid title");
		eq(invalid.output.indexOf("bad pattern") != -1, true, "invalid output");
	}

	static function permissionShapes(registry:ToolRegistry, root:String):Void {
		final seen:Array<String> = [];
		final ctx = context(root, request -> {
			seen.push(request.permission + ":" + request.patterns.join(","));
			return {allowed: false, reason: "blocked by smoke"};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("read"), {filePath: "src/a.ts"}, ctx), function(failure) {
			return switch failure {
				case PermissionDenied(id, _): id == "read";
				case _: false;
			}
		}, "read permission denied");
		eq(seen[0], "read:" + NodePath.join(root, "src/a.ts"), "permission request shape");

		final deniedBash = context(root, request -> {
			return {allowed: false, reason: "no shell"};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("bash"), {
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

		final hello = registry.execute(ToolIDs.known("bash"), {
			command: "printf hello",
			description: "Print hello"
		}, ctx);
		eq(hello.title, "Print hello", "bash title");
		eq(hello.output, "hello", "bash output");
		eq(metadataText(hello).indexOf('"exit":0') != -1, true, "bash exit");
		eq(metadataText(hello).indexOf('"outputPath"') == -1, true, "bash untruncated omits output path");

		final cwd = registry.execute(ToolIDs.known("bash"), {
			command: "node -e \"process.stdout.write(process.cwd())\"",
			workdir: "src",
			description: "Show cwd"
		}, ctx);
		eq(StringTools.endsWith(ToolPaths.normalize(cwd.output), ToolPaths.normalize(NodePath.join(NodePath.basename(ctx.directory), "src"))), true,
			"bash cwd");

		final env = registry.execute(ToolIDs.known("bash"), {
			command: "node -e \"process.stdout.write(process.env.PATH ? 'env-ok' : 'missing')\"",
			description: "Show env"
		}, ctx);
		eq(env.output, "env-ok", "bash env");

		final truncatedBytes = registry.execute(ToolIDs.known("bash"), {
			command: 'node -e "process.stdout.write(\'x\'.repeat(${Truncate.MAX_BYTES + 1000}))"',
			description: "Large byte output"
		}, ctx);
		eq(metadataText(truncatedBytes).indexOf('"truncated":true') != -1, true, "bash byte truncated metadata");
		eq(truncatedBytes.output.indexOf("...output truncated...") == 0, true, "bash byte truncation output");
		eq(truncatedBytes.output.indexOf("Full output saved to:") != -1, true, "bash byte truncation saved hint");
		final byteOutputPath = savedOutputPath(truncatedBytes.output, "bash byte output path");
		eq(metadataText(truncatedBytes).indexOf('"outputPath":"' + jsonPath(byteOutputPath) + '"') != -1, true, "bash byte metadata output path");
		eq(Fs.readFileSync(byteOutputPath, "utf8").length, Truncate.MAX_BYTES + 1000, "bash byte saved full output");

		final lineCount = Truncate.MAX_LINES + 100;
		final truncatedLines = registry.execute(ToolIDs.known("bash"), {
			command: 'node -e "console.log(Array.from({length:${lineCount}},(_,i)=>i+1).join(String.fromCharCode(10)))"',
			description: "Large line output"
		}, ctx);
		eq(metadataText(truncatedLines).indexOf('"truncated":true') != -1, true, "bash line truncated metadata");
		final lineOutputPath = savedOutputPath(truncatedLines.output, "bash line output path");
		eq(metadataText(truncatedLines).indexOf('"outputPath":"' + jsonPath(lineOutputPath) + '"') != -1, true, "bash line metadata output path");
		final savedLines = Fs.readFileSync(lineOutputPath, "utf8").split("\n");
		if (savedLines.length > 0 && savedLines[savedLines.length - 1] == "")
			savedLines.pop();
		eq(savedLines.length, lineCount, "bash line saved full output line count");
		eq(savedLines[0], "1", "bash line saved first line");
		eq(savedLines[savedLines.length - 1], Std.string(lineCount), "bash line saved last line");

		final timeout = registry.execute(ToolIDs.known("bash"), {
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
		expectToolFailure(() -> registry.execute(ToolIDs.known("bash"), {
			command: "pwd",
			workdir: Os.tmpdir(),
			description: "External pwd"
		}, externalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "bash" && message.indexOf("external blocked") != -1;
				case _: false;
			}
		}, "bash external directory denied");

		final wildcardDir = NodeProcess.platform() == "win32" ? NodeProcess.envValue("WINDIR") : "/etc";
		if (wildcardDir != null && wildcardDir != "") {
			final wildcardRequests:Array<ToolPermissionRequest> = [];
			final wildcardCtx = context(ctx.directory, request -> {
				wildcardRequests.push(request);
				if (request.permission == "external_directory")
					return {allowed: false, reason: "wildcard external blocked"};
				return {allowed: true};
			});
			expectToolFailure(() -> registry.execute(ToolIDs.known("bash"), {
				command: 'cat ${ToolPaths.normalize(NodePath.join(wildcardDir, "*"))}',
				description: "Read wildcard path"
			}, wildcardCtx), function(failure) {
				return switch failure {
					case PermissionDenied(id, message): id == "bash" && message.indexOf("wildcard external blocked") != -1;
					case _: false;
				}
			}, "bash wildcard external denied");
			final wildcardPattern = ToolPaths.normalize(NodePath.join(wildcardDir, "*"));
			eq(wildcardRequests.length > 0, true, "bash wildcard external request count");
			eq(wildcardRequests[0].permission, "external_directory", "bash wildcard external permission kind");
			eq(wildcardRequests[0].patterns.indexOf(wildcardPattern) != -1, true, "bash wildcard external permission pattern");
			eq(wildcardRequests[0].always.indexOf(wildcardPattern) != -1, true, "bash wildcard external permission always");
		}
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
		final file = registry.execute(ToolIDs.known("read"), {filePath: "src/a.ts", limit: 1}, ctx);
		eq(metadataText(file).indexOf('"truncated":false') != -1, true, "read file not truncated");
		eq(file.output.indexOf("<type>file</type>") != -1, true, "read file type");
		eq(file.output.indexOf("1: export const needle = 1;") != -1, true, "read line");

		write(ctx.directory, "src/long-line.txt", repeat("x", 3000));
		final longLine = registry.execute(ToolIDs.known("read"), {filePath: "src/long-line.txt"}, ctx);
		eq(longLine.output.indexOf("(line truncated to 2000 chars)") != -1, true, "read long-line truncation suffix");
		eq(longLine.output.length < 3000, true, "read long-line output shortened");

		write(ctx.directory, "feature/AGENTS.md", "# Feature Instructions\nUse feature rules.");
		write(ctx.directory, "feature/nested/file.ts", "export const feature = true;\n");
		final instructed = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/file.ts"}, ctx);
		eq(instructed.output.indexOf("<system-reminder>") != -1, true, "read nearby instruction reminder");
		eq(instructed.output.indexOf("Use feature rules.") != -1, true, "read nearby instruction content");
		final instructedMetadata = Json.stringify(instructed.metadata);
		eq(instructedMetadata.indexOf('"loaded":["' + jsonPath(NodePath.join(ctx.directory, "feature/AGENTS.md")) + '"]') != -1, true,
			"read nearby instruction metadata");

		write(ctx.directory, "feature/nested/second.ts", "export const second = true;\n");
		final claims = new SessionInstructionClaims();
		final firstClaimed = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/file.ts"},
			contextWithInstructionClaims(ctx.directory, "msg_claim_one", claims));
		eq(firstClaimed.output.indexOf("<system-reminder>") != -1, true, "read claimed first reminder");
		final secondClaimed = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/second.ts"},
			contextWithInstructionClaims(ctx.directory, "msg_claim_one", claims));
		eq(secondClaimed.output.indexOf("<system-reminder>") == -1, true, "read claimed same-message dedupe");
		eq(Json.stringify(secondClaimed.metadata).indexOf('"loaded":[]') != -1, true, "read claimed same-message metadata");
		final differentMessage = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/second.ts"},
			contextWithInstructionClaims(ctx.directory, "msg_claim_two", claims));
		eq(differentMessage.output.indexOf("<system-reminder>") != -1, true, "read claimed different-message reload");
		claims.clear("msg_claim_one");
		final afterClear = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/file.ts"},
			contextWithInstructionClaims(ctx.directory, "msg_claim_one", claims));
		eq(afterClear.output.indexOf("<system-reminder>") != -1, true, "read claimed clear reload");

		write(ctx.directory, "feature/nested/manual.pdf", "%PDF-1.4\n% smoke pdf\n");
		final pdf = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/manual.pdf"}, ctx);
		eq(pdf.output, "PDF read successfully", "read pdf output");
		eq(Json.stringify(pdf.metadata).indexOf('"truncated":false') != -1, true, "read pdf not truncated");
		eq(Json.stringify(pdf.metadata).indexOf('"loaded":["' + jsonPath(NodePath.join(ctx.directory, "feature/AGENTS.md")) + '"]') != -1, true,
			"read pdf instruction metadata");
		final pdfAttachment = onlyAttachment(pdf, "read pdf");
		eq(pdfAttachment.type, "file", "read pdf attachment type");
		eq(pdfAttachment.mime, "application/pdf", "read pdf attachment mime");
		eq(StringTools.startsWith(pdfAttachment.url, "data:application/pdf;base64,"), true, "read pdf attachment data url");

		writeBytes(ctx.directory, "feature/nested/image.bin", Buffer.from("/9j/4AAQSkZJRgAB", "base64"));
		final image = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/image.bin"}, ctx);
		eq(image.output, "Image read successfully", "read sniffed image output");
		final imageAttachment = onlyAttachment(image, "read sniffed image");
		eq(imageAttachment.mime, "image/jpeg", "read sniffed image attachment mime");
		eq(StringTools.startsWith(imageAttachment.url, "data:image/jpeg;base64,"), true, "read sniffed image data url");

		write(ctx.directory, "feature/nested/schema.fbs", "namespace MyGame;\n\ntable Monster {\n  name:string;\n}\n\nroot_type Monster;");
		final fbs = registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/schema.fbs"}, ctx);
		eq(fbs.attachments == null, true, "read fbs has no attachments");
		eq(fbs.output.indexOf("namespace MyGame") != -1, true, "read fbs namespace text");
		eq(fbs.output.indexOf("table Monster") != -1, true, "read fbs table text");

		write(ctx.directory, "feature/nested/module.wasm", "not really wasm");
		expectToolFailure(() -> registry.execute(ToolIDs.known("read"), {filePath: "feature/nested/module.wasm"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "read" && message.indexOf("Cannot read binary file") != -1;
				case _: false;
			}
		}, "read known binary extension failure");

		final dir = registry.execute(ToolIDs.known("read"), {filePath: "src"}, ctx);
		eq(dir.output.indexOf("<type>directory</type>") != -1, true, "read directory type");
		eq(dir.output.indexOf("a.ts") != -1, true, "read directory entry");

		write(ctx.directory, "links/target/file.txt", "linked\n");
		var symlinkCreated = true;
		try {
			Fs.symlinkSync(NodePath.join(ctx.directory, "links/target"), NodePath.join(ctx.directory, "links/linked"));
		} catch (_:haxe.Exception) {
			symlinkCreated = false;
		}
		if (symlinkCreated) {
			final symlinkDir = registry.execute(ToolIDs.known("read"), {filePath: "links"}, ctx);
			eq(symlinkDir.output.indexOf("linked/") != -1, true, "read symlink directory suffix");
		}

		write(ctx.directory, "src/page-1.txt", "one\n");
		write(ctx.directory, "src/page-2.txt", "two\n");
		write(ctx.directory, "src/page-3.txt", "three\n");
		final pagedDir = registry.execute(ToolIDs.known("read"), {filePath: "src", offset: 2, limit: 2}, ctx);
		eq(pagedDir.output.indexOf("b.txt") != -1, true, "read directory offset includes second entry");
		eq(pagedDir.output.indexOf("c.ts") != -1, true, "read directory limit includes third entry");
		eq(pagedDir.output.indexOf("a.ts") == -1, true, "read directory offset skips first entry");
		eq(pagedDir.output.indexOf("Use 'offset' parameter") != -1, true, "read directory truncation hint");
		final finalDirPage = registry.execute(ToolIDs.known("read"), {filePath: "src", offset: 6, limit: 20}, ctx);
		eq(finalDirPage.output.indexOf("Showing 20") == -1, true, "read directory final page not truncated");

		write(ctx.directory, "src/many-lines.txt", numberedLines(100));
		final lineLimited = registry.execute(ToolIDs.known("read"), {filePath: "src/many-lines.txt", limit: 10}, ctx);
		eq(metadataText(lineLimited).indexOf('"truncated":true') != -1, true, "read line-limited metadata");
		eq(lineLimited.output.indexOf("Showing lines 1-10 of 100") != -1, true, "read line-limited footer range");
		eq(lineLimited.output.indexOf("Use offset=11") != -1, true, "read line-limited footer offset");
		eq(lineLimited.output.indexOf("line10") == -1, true, "read line-limited excludes next line");

		write(ctx.directory, "src/byte-cap.txt", numberedLinesWithPayload(2000, repeat("x", 48)));
		final byteCapped = registry.execute(ToolIDs.known("read"), {filePath: "src/byte-cap.txt"}, ctx);
		eq(metadataText(byteCapped).indexOf('"truncated":true') != -1, true, "read byte-capped metadata");
		eq(byteCapped.output.indexOf("Output capped at 50 KB") != -1, true, "read byte-capped footer");
		eq(byteCapped.output.indexOf("Use offset=") != -1, true, "read byte-capped offset hint");

		write(ctx.directory, "src/empty-read.txt", "");
		final emptyRead = registry.execute(ToolIDs.known("read"), {filePath: "src/empty-read.txt"}, ctx);
		eq(metadataText(emptyRead).indexOf('"truncated":false') != -1, true, "read empty file metadata");
		eq(emptyRead.output.indexOf("End of file - total 0 lines") != -1, true, "read empty file footer");
		expectToolFailure(() -> registry.execute(ToolIDs.known("read"), {filePath: "src/empty-read.txt", offset: 2}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "read" && message.indexOf("Offset 2 is out of range for this file (0 lines)") != -1;
				case _: false;
			}
		}, "read empty file offset failure");

		expectToolFailure(() -> registry.execute(ToolIDs.known("read"), {filePath: "src/a.ts", offset: 5, limit: 1}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "read" && message.indexOf("Offset 5 is out of range") != -1;
				case _: false;
			}
		}, "read out-of-range offset failure");

		write(ctx.directory, "suggestions/alpha.txt", "alpha\n");
		write(ctx.directory, "suggestions/alpine.txt", "alpine\n");
		expectToolFailure(() -> registry.execute(ToolIDs.known("read"), {filePath: "suggestions/alp"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message):
					id == "read"
					&& message.indexOf("Did you mean one of these?\n") != -1
					&& message.indexOf(NodePath.join(ctx.directory, "suggestions/alpha.txt")) != -1
					&& message.indexOf(NodePath.join(ctx.directory, "suggestions/alpine.txt")) != -1;
				case _: false;
			}
		}, "read missing file suggestions");

		final outsideDir = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-read-outside-"));
		final outsideFile = NodePath.join(outsideDir, "outside.ts");
		Fs.writeFileSync(outsideFile, "external read\n", "utf8");
		final outsideRequests:Array<ToolPermissionRequest> = [];
		final outside = registry.execute(ToolIDs.known("read"), {filePath: outsideFile, limit: 1}, context(ctx.directory, request -> {
			outsideRequests.push(request);
			return {allowed: true};
		}));
		eq(outside.output.indexOf("external read") != -1, true, "read external file output");
		eq(outsideRequests.length, 2, "read external permission count");
		eq(outsideRequests[0].permission, "external_directory", "read external permission kind");
		final outsidePattern = ToolPaths.normalize(NodePath.join(outsideDir, "*"));
		eq(outsideRequests[0].patterns.join(","), outsidePattern, "read external permission pattern");
		eq(outsideRequests[0].always.join(","), outsidePattern, "read external permission always");
		final outsideMetadata = Json.stringify(outsideRequests[0].metadata);
		eq(outsideMetadata.indexOf('"filepath":"' + jsonPath(outsideFile) + '"') != -1, true, "read external metadata filepath");
		eq(outsideMetadata.indexOf('"parentDir":"' + jsonPath(outsideDir) + '"') != -1, true, "read external metadata parent");
		eq(outsideRequests[1].permission, "read", "read external read permission kind");
		eq(outsideRequests[1].patterns.join(","), outsideFile, "read external read permission pattern");

		final deniedExternalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "read outside blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("read"), {filePath: outsideFile}, deniedExternalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "read" && message.indexOf("read outside blocked") != -1;
				case _: false;
			}
		}, "read external directory denied");
		Fs.rmSync(outsideDir, {recursive: true, force: true});
	}

	static function globExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final globRequests:Array<ToolPermissionRequest> = [];
		final allowedCtx = context(ctx.directory, request -> {
			globRequests.push(request);
			return {allowed: true};
		});

		final allowed = registry.execute(ToolIDs.known("glob"), {pattern: "*.ts", path: "src"}, allowedCtx);
		final allowedMetadata = Json.stringify(allowed.metadata);
		eq(allowedMetadata.indexOf('"count":2') != -1, true, "glob permission count");
		eq(globRequests.length, 1, "glob permission requested once");
		eq(globRequests[0].permission, "glob", "glob permission kind");
		eq(globRequests[0].patterns.join(","), "*.ts", "glob permission pattern");
		final globMetadata = Json.stringify(globRequests[0].metadata);
		eq(globMetadata.indexOf('"pattern":"*.ts"') != -1, true, "glob permission metadata pattern");
		eq(globMetadata.indexOf('"path":"src"') != -1, true, "glob permission metadata path");

		final outsideDir = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-glob-outside-"));
		write(outsideDir, "external.ts", "export const outside = 1;\n");
		final outsideRequests:Array<ToolPermissionRequest> = [];
		final outside = registry.execute(ToolIDs.known("glob"), {pattern: "*.ts", path: outsideDir}, context(ctx.directory, request -> {
			outsideRequests.push(request);
			return {allowed: true};
		}));
		eq(outside.output.indexOf("external.ts") != -1, true, "glob external directory output");
		eq(outsideRequests.length, 2, "glob external permission count");
		eq(outsideRequests[1].permission, "external_directory", "glob external permission kind");
		final outsidePattern = ToolPaths.normalize(NodePath.join(outsideDir, "*"));
		eq(outsideRequests[1].patterns.join(","), outsidePattern, "glob external permission pattern");
		eq(outsideRequests[1].always.join(","), outsidePattern, "glob external permission always");
		final outsideMetadata = Json.stringify(outsideRequests[1].metadata);
		eq(outsideMetadata.indexOf('"filepath":"' + jsonPath(outsideDir) + '"') != -1, true, "glob external metadata filepath");
		eq(outsideMetadata.indexOf('"parentDir":"' + jsonPath(outsideDir) + '"') != -1, true, "glob external metadata parent");

		final deniedExternalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "glob outside blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("glob"), {pattern: "*.ts", path: outsideDir}, deniedExternalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "glob" && message.indexOf("glob outside blocked") != -1;
				case _: false;
			}
		}, "glob external directory denied");
		Fs.rmSync(outsideDir, {recursive: true, force: true});

		final deniedCtx = context(ctx.directory, request -> {
			if (request.permission == "glob")
				return {allowed: false, reason: "glob blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("glob"), {pattern: "*.ts", path: "src"}, deniedCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "glob" && message.indexOf("glob blocked") != -1;
				case _: false;
			}
		}, "glob permission denied");

		final result = registry.execute(ToolIDs.known("glob"), {pattern: "*.ts", path: "src"}, ctx);
		final resultMetadata = Json.stringify(result.metadata);
		eq(resultMetadata.indexOf('"count":2') != -1, true, "glob count");
		eq(result.output.indexOf("a.ts") != -1, true, "glob output a");
		eq(result.output.indexOf("b.txt") == -1, true, "glob excludes txt");

		expectToolFailure(() -> registry.execute(ToolIDs.known("glob"), {pattern: "*.ts", path: "src/a.ts"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "glob" && message.indexOf("glob path must be a directory") != -1;
				case _: false;
			}
		}, "glob file path failure");
	}

	static function grepExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final grepRequests:Array<ToolPermissionRequest> = [];
		final allowedCtx = context(ctx.directory, request -> {
			grepRequests.push(request);
			return {allowed: true};
		});

		final allowed = registry.execute(ToolIDs.known("grep"), {pattern: "needle", path: "src", include: "*.ts"}, allowedCtx);
		final allowedMetadata = Json.stringify(allowed.metadata);
		eq(allowedMetadata.indexOf('"matches":1') != -1, true, "grep permission matches");
		eq(grepRequests.length, 1, "grep permission requested once");
		eq(grepRequests[0].permission, "grep", "grep permission kind");
		eq(grepRequests[0].patterns.join(","), "needle", "grep permission pattern");
		final grepMetadata = Json.stringify(grepRequests[0].metadata);
		eq(grepMetadata.indexOf('"pattern":"needle"') != -1, true, "grep permission metadata pattern");
		eq(grepMetadata.indexOf('"path":"src"') != -1, true, "grep permission metadata path");
		eq(grepMetadata.indexOf('"include":"*.ts"') != -1, true, "grep permission metadata include");

		final outsideDir = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-grep-outside-"));
		final outsideFile = NodePath.join(outsideDir, "external.txt");
		Fs.writeFileSync(outsideFile, "needle outside\n", "utf8");
		final outsideRequests:Array<ToolPermissionRequest> = [];
		final outside = registry.execute(ToolIDs.known("grep"), {pattern: "needle", path: outsideFile}, context(ctx.directory, request -> {
			outsideRequests.push(request);
			return {allowed: true};
		}));
		eq(outside.output.indexOf("needle outside") != -1, true, "grep external file output");
		eq(outsideRequests.length, 2, "grep external permission count");
		eq(outsideRequests[1].permission, "external_directory", "grep external permission kind");
		final outsidePattern = ToolPaths.normalize(NodePath.join(outsideDir, "*"));
		eq(outsideRequests[1].patterns.join(","), outsidePattern, "grep external permission pattern");
		eq(outsideRequests[1].always.join(","), outsidePattern, "grep external permission always");
		final outsideMetadata = Json.stringify(outsideRequests[1].metadata);
		eq(outsideMetadata.indexOf('"filepath":"' + jsonPath(outsideFile) + '"') != -1, true, "grep external metadata filepath");
		eq(outsideMetadata.indexOf('"parentDir":"' + jsonPath(outsideDir) + '"') != -1, true, "grep external metadata parent");

		final deniedExternalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "grep outside blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("grep"), {pattern: "needle", path: outsideFile}, deniedExternalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "grep" && message.indexOf("grep outside blocked") != -1;
				case _: false;
			}
		}, "grep external file denied");
		Fs.rmSync(outsideDir, {recursive: true, force: true});

		final deniedCtx = context(ctx.directory, request -> {
			if (request.permission == "grep")
				return {allowed: false, reason: "grep blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("grep"), {pattern: "needle", path: "src", include: "*.ts"}, deniedCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "grep" && message.indexOf("grep blocked") != -1;
				case _: false;
			}
		}, "grep permission denied");

		final result = registry.execute(ToolIDs.known("grep"), {pattern: "needle", path: "src", include: "*.ts"}, ctx);
		final resultMetadata = Json.stringify(result.metadata);
		eq(resultMetadata.indexOf('"matches":1') != -1, true, "grep matches");
		eq(result.output.indexOf("Found 1 matches") != -1, true, "grep found");
		eq(result.output.indexOf("Line 1:") != -1, true, "grep line");

		final exact = registry.execute(ToolIDs.known("grep"), {pattern: "needle", path: "src/b.txt"}, ctx);
		final exactMetadata = Json.stringify(exact.metadata);
		eq(exactMetadata.indexOf('"matches":1') != -1, true, "grep exact file");

		final none = registry.execute(ToolIDs.known("grep"), {pattern: "definitely-not-here", path: "src"}, ctx);
		eq(none.output, "No files found", "grep no matches");
	}

	static function writeExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final result = registry.execute(ToolIDs.known("write"), {filePath: "src/new.txt", content: "fresh\n"}, ctx);
		eq(result.output, "Wrote file successfully.", "write output");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/new.txt"), "utf8"), "fresh\n", "write content");
		eq(metadataText(result).indexOf('"exists":false') != -1, true, "write existed metadata");

		final existing = NodePath.join(ctx.directory, "src/existing.txt");
		Fs.writeFileSync(existing, "old\n", "utf8");
		final overwrite = registry.execute(ToolIDs.known("write"), {filePath: "src/existing.txt", content: "new\n"}, ctx);
		eq(Fs.readFileSync(existing, "utf8"), "new\n", "write overwrites existing content");
		final overwriteMetadata = Json.stringify(overwrite.metadata);
		eq(overwriteMetadata.indexOf('"exists":true') != -1, true, "write overwrite existed metadata");
		eq(overwriteMetadata.indexOf('"additions":1') != -1, true, "write overwrite additions metadata");
		eq(overwriteMetadata.indexOf('"deletions":1') != -1, true, "write overwrite deletions metadata");

		final bom = String.fromCharCode(0xfeff);
		final bomFile = NodePath.join(ctx.directory, "src/bom.cs");
		Fs.writeFileSync(bomFile, bom + "using System;\n", "utf8");
		final bomResult = registry.execute(ToolIDs.known("write"), {filePath: "src/bom.cs", content: "using Up;\n"}, ctx);
		final bomContent = Fs.readFileSync(bomFile, "utf8");
		eq(bomContent.charCodeAt(0), 0xfeff, "write preserves existing BOM");
		eq(bomContent.substr(1), "using Up;\n", "write replaces content after BOM");
		eq(Json.stringify(bomResult.metadata).indexOf('"exists":true') != -1, true, "write BOM existed metadata");

		final formattedBom = NodePath.join(ctx.directory, "src/formatted-bom.cs");
		Fs.writeFileSync(formattedBom, bom + "using System;\n", "utf8");
		var formattedPath = "";
		final formattedCtx:ToolContext = {
			directory: ctx.directory,
			worktree: ctx.worktree,
			sessionID: ctx.sessionID,
			messageID: ctx.messageID,
			callID: ctx.callID,
			agent: ctx.agent,
			toolOutputDir: ctx.toolOutputDir,
			formatFile: file -> {
				formattedPath = file;
				final formatted = ToolBom.split(Fs.readFileSync(file, "utf8")).text;
				Fs.writeFileSync(file, formatted, "utf8");
				return true;
			},
			ask: ctx.ask,
		};
		registry.execute(ToolIDs.known("write"), {filePath: "src/formatted-bom.cs", content: "using Formatted;\n"}, formattedCtx);
		final formattedBomContent = Fs.readFileSync(formattedBom, "utf8");
		eq(formattedPath, formattedBom, "write formatter receives absolute path");
		eq(formattedBomContent.charCodeAt(0), 0xfeff, "write restores BOM after formatter");
		eq(formattedBomContent.substr(1), "using Formatted;\n", "write keeps formatted content after BOM restore");

		final writeBus = new BusRuntime();
		final writeEdited:Array<String> = [];
		final writeWatcher:Array<String> = [];
		collectFileEvents(writeBus, writeEdited, writeWatcher);
		final writeBusCtx = contextWithBus(ctx, writeBus);
		final writeEventFile = NodePath.join(ctx.directory, "src/write-event.txt");
		registry.execute(ToolIDs.known("write"), {filePath: "src/write-event.txt", content: "first\n"}, writeBusCtx);
		registry.execute(ToolIDs.known("write"), {filePath: "src/write-event.txt", content: "second\n"}, writeBusCtx);
		eq(writeEdited.join("|"), [writeEventFile, writeEventFile].join("|"), "write publishes file.edited events");
		eq(writeWatcher.join("|"), [writeEventFile + ":add", writeEventFile + ":change"].join("|"), "write publishes watcher add/change events");

		final jsonContent = '{"key":"value","nested":{"array":[1,2,3]}}';
		registry.execute(ToolIDs.known("write"), {filePath: "src/data.json", content: jsonContent}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/data.json"), "utf8"), jsonContent, "write json content");

		final binaryContent = "Hello" + String.fromCharCode(0) + "World" + String.fromCharCode(1) + String.fromCharCode(2) + String.fromCharCode(3);
		registry.execute(ToolIDs.known("write"), {filePath: "src/binary.bin", content: binaryContent}, ctx);
		eq(Fs.readFileBufferSync(NodePath.join(ctx.directory, "src/binary.bin")).toString(), binaryContent, "write binary-safe content");

		final emptyFile = NodePath.join(ctx.directory, "src/empty.txt");
		registry.execute(ToolIDs.known("write"), {filePath: "src/empty.txt", content: ""}, ctx);
		eq(Fs.readFileSync(emptyFile, "utf8"), "", "write empty content");
		eq(Fs.statSync(emptyFile).size == 0, true, "write empty content size");

		final multiline = ["Line 1", "Line 2", "Line 3", ""].join("\n");
		registry.execute(ToolIDs.known("write"), {filePath: "src/multiline.txt", content: multiline}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/multiline.txt"), "utf8"), multiline, "write multiline content");

		final crlf = "Line 1\r\nLine 2\r\nLine 3";
		registry.execute(ToolIDs.known("write"), {filePath: "src/crlf.txt", content: crlf}, ctx);
		eq(Fs.readFileBufferSync(NodePath.join(ctx.directory, "src/crlf.txt")).toString(), crlf, "write CRLF content");

		final titled = registry.execute(ToolIDs.known("write"), {filePath: "src/components/Button.tsx", content: "export const Button = () => {}"}, ctx);
		eq(titled.title, "src/components/Button.tsx", "write relative title");

		final outsideDir = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-write-outside-"));
		final outsideFile = NodePath.join(outsideDir, "outside.txt");
		final outsideRequests:Array<ToolPermissionRequest> = [];
		registry.execute(ToolIDs.known("write"), {filePath: outsideFile, content: "external write\n"}, context(ctx.directory, request -> {
			outsideRequests.push(request);
			return {allowed: true};
		}));
		eq(Fs.readFileSync(outsideFile, "utf8"), "external write\n", "write external file content");
		eq(outsideRequests.length, 2, "write external permission count");
		eq(outsideRequests[0].permission, "external_directory", "write external permission kind");
		final outsidePattern = ToolPaths.normalize(NodePath.join(outsideDir, "*"));
		eq(outsideRequests[0].patterns.join(","), outsidePattern, "write external permission pattern");
		eq(outsideRequests[0].always.join(","), outsidePattern, "write external permission always");
		final outsideMetadata = Json.stringify(outsideRequests[0].metadata);
		eq(outsideMetadata.indexOf('"filepath":"' + jsonPath(outsideFile) + '"') != -1, true, "write external metadata filepath");
		eq(outsideMetadata.indexOf('"parentDir":"' + jsonPath(outsideDir) + '"') != -1, true, "write external metadata parent");
		eq(outsideRequests[1].permission, "edit", "write external edit permission kind");
		eq(outsideRequests[1].patterns.join(","), ToolPaths.relative(ctx, outsideFile), "write external edit permission pattern");

		final deniedExternalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "write outside blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("write"), {
			filePath: NodePath.join(outsideDir, "blocked.txt"),
			content: "blocked\n"
		}, deniedExternalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "write" && message.indexOf("write outside blocked") != -1;
				case _: false;
			}
		}, "write external directory denied");
		eq(Fs.existsSync(NodePath.join(outsideDir, "blocked.txt")), false, "write external denied avoids file write");
		Fs.rmSync(outsideDir, {recursive: true, force: true});
	}

	static function editExec(registry:ToolRegistry, ctx:ToolContext):Void {
		final single = registry.execute(ToolIDs.known("edit"), {filePath: "src/a.ts", oldString: "needle", newString: "pin"}, ctx);
		eq(single.output, "Edit applied successfully.", "edit output");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/a.ts"), "utf8").indexOf("pin") != -1, true, "edit content");

		write(ctx.directory, "src/edit-multiline.txt", "line1\nline2\nline3");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-multiline.txt",
			oldString: "line2",
			newString: "new line 2\nextra line"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/edit-multiline.txt"), "utf8"), "line1\nnew line 2\nextra line\nline3",
			"edit multiline replacement");

		write(ctx.directory, "src/edit-crlf.txt", "line1\r\nold\r\nline3");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-crlf.txt",
			oldString: "old",
			newString: "new"
		}, ctx);
		eq(Fs.readFileBufferSync(NodePath.join(ctx.directory, "src/edit-crlf.txt")).toString(), "line1\r\nnew\r\nline3", "edit preserves CRLF");

		expectToolFailure(() -> registry.execute(ToolIDs.known("edit"), {
			filePath: "src/a.ts",
			oldString: "",
			newString: ""
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "edit" && message.indexOf("identical") != -1;
				case _: false;
			}
		}, "edit identical failure");

		Fs.mkdirSync(NodePath.join(ctx.directory, "src/edit-dir"), {recursive: true});
		expectToolFailure(() -> registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-dir",
			oldString: "old",
			newString: "new"
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "edit" && message.indexOf("directory") != -1;
				case _: false;
			}
		}, "edit directory failure");

		write(ctx.directory, "src/edit-stats.txt", "line1\nline2\nline3");
		final statsEdit = registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-stats.txt",
			oldString: "line2",
			newString: "new line 2"
		}, ctx);
		final statsMetadata = metadataText(statsEdit);
		eq(statsMetadata.indexOf('"file":"' + jsonPath(NodePath.join(ctx.directory, "src/edit-stats.txt")) + '"') != -1, true, "edit filediff file metadata");
		eq(statsMetadata.indexOf('"additions":1') != -1, true, "edit filediff additions metadata");
		eq(statsMetadata.indexOf('"deletions":1') != -1, true, "edit filediff deletions metadata");

		write(ctx.directory, "src/repeat.txt", "x\nx\n");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/repeat.txt",
			oldString: "x",
			newString: "y",
			replaceAll: true
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/repeat.txt"), "utf8"), "y\ny\n", "edit replace all");

		expectToolFailure(() -> registry.execute(ToolIDs.known("edit"), {filePath: "src/repeat.txt", oldString: "y", newString: "z"}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "edit" && message.indexOf("multiple matches") != -1;
				case _: false;
			}
		}, "edit multiple failure");

		write(ctx.directory, "src/line-trimmed.txt", "function run() {\n  return 1;\n}\n");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/line-trimmed.txt",
			oldString: "function run() {\nreturn 1;\n}",
			newString: "function run() {\n  return 2;\n}"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/line-trimmed.txt"), "utf8"), "function run() {\n  return 2;\n}\n", "edit line-trimmed");

		write(ctx.directory, "src/block-anchor.txt", "start\nactual middle\nfinish\n");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/block-anchor.txt",
			oldString: "start\nstale middle\nfinish",
			newString: "start\nfresh middle\nfinish"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/block-anchor.txt"), "utf8"), "start\nfresh middle\nfinish\n", "edit block anchor");

		write(ctx.directory, "src/whitespace.txt", "const pair = alpha   +\t beta;\n");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/whitespace.txt",
			oldString: "const pair = alpha + beta;",
			newString: "const pair = gamma;"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/whitespace.txt"), "utf8"), "const pair = gamma;\n", "edit whitespace-normalized");

		write(ctx.directory, "src/indent.txt", "    alpha\n      beta\n    gamma\n");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/indent.txt",
			oldString: "alpha\n  beta\ngamma",
			newString: "delta"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/indent.txt"), "utf8"), "delta\n", "edit indentation-flexible");

		write(ctx.directory, "src/escaped.txt", "const value = \"a\\nb\";\n");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/escaped.txt",
			oldString: "const value = \"a\\\\nb\";",
			newString: "const value = \"c\";"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/escaped.txt"), "utf8"), "const value = \"c\";\n", "edit escape-normalized");

		final bom = String.fromCharCode(0xfeff);
		final bomExisting = NodePath.join(ctx.directory, "src/edit-bom.cs");
		Fs.writeFileSync(bomExisting, bom + "using System;\nclass Test {}\n", "utf8");
		final bomEdit = registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-bom.cs",
			oldString: "using System;",
			newString: "using Up;"
		}, ctx);
		final bomContent = Fs.readFileSync(bomExisting, "utf8");
		eq(bomContent.charCodeAt(0), 0xfeff, "edit preserves existing BOM");
		eq(bomContent.substr(1), "using Up;\nclass Test {}\n", "edit replaces visible content after BOM");
		final bomMetadata = Json.stringify(bomEdit.metadata);
		eq(bomMetadata.indexOf("-using System;") != -1, true, "edit BOM diff removes visible line");
		eq(bomMetadata.indexOf("+using Up;") != -1, true, "edit BOM diff adds visible line");
		eq(bomMetadata.indexOf(bom) == -1, true, "edit BOM diff hides marker");

		final formattedBom = NodePath.join(ctx.directory, "src/edit-formatted-bom.cs");
		Fs.writeFileSync(formattedBom, bom + "using System;\nclass Test {}\n", "utf8");
		var formattedPath = "";
		final formattedCtx:ToolContext = {
			directory: ctx.directory,
			worktree: ctx.worktree,
			sessionID: ctx.sessionID,
			messageID: ctx.messageID,
			callID: ctx.callID,
			agent: ctx.agent,
			toolOutputDir: ctx.toolOutputDir,
			formatFile: file -> {
				formattedPath = file;
				final formatted = ToolBom.split(Fs.readFileSync(file, "utf8")).text;
				Fs.writeFileSync(file, formatted, "utf8");
				return true;
			},
			ask: ctx.ask,
		};
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-formatted-bom.cs",
			oldString: "using System;",
			newString: "using Formatted;"
		}, formattedCtx);
		final formattedBomContent = Fs.readFileSync(formattedBom, "utf8");
		eq(formattedPath, formattedBom, "edit formatter receives absolute path");
		eq(formattedBomContent.charCodeAt(0), 0xfeff, "edit restores BOM after formatter");
		eq(formattedBomContent.substr(1), "using Formatted;\nclass Test {}\n", "edit keeps formatted content after BOM restore");

		final bomCreate = NodePath.join(ctx.directory, "src/edit-created-bom.cs");
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-created-bom.cs",
			oldString: "",
			newString: bom + "using Created;\n"
		}, ctx);
		final createdBomContent = Fs.readFileSync(bomCreate, "utf8");
		eq(createdBomContent.charCodeAt(0), 0xfeff, "edit preserves incoming BOM on create");
		eq(createdBomContent.substr(1), "using Created;\n", "edit strips incoming BOM from logical content");

		final editBus = new BusRuntime();
		final editEdited:Array<String> = [];
		final editWatcher:Array<String> = [];
		collectFileEvents(editBus, editEdited, editWatcher);
		final editBusCtx = contextWithBus(ctx, editBus);
		final editEventFile = NodePath.join(ctx.directory, "src/edit-event.txt");
		registry.execute(ToolIDs.known("edit"), {filePath: "src/edit-event.txt", oldString: "", newString: "first\n"}, editBusCtx);
		registry.execute(ToolIDs.known("edit"), {
			filePath: "src/edit-event.txt",
			oldString: "first",
			newString: "second"
		}, editBusCtx);
		eq(editEdited.join("|"), [editEventFile, editEventFile].join("|"), "edit publishes file.edited events");
		eq(editWatcher.join("|"), [editEventFile + ":add", editEventFile + ":change"].join("|"), "edit publishes watcher add/change events");

		final outsideDir = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-edit-outside-"));
		final outsideFile = NodePath.join(outsideDir, "outside.txt");
		Fs.writeFileSync(outsideFile, "alpha\n", "utf8");
		final outsideRequests:Array<ToolPermissionRequest> = [];
		registry.execute(ToolIDs.known("edit"), {
			filePath: outsideFile,
			oldString: "alpha",
			newString: "beta"
		}, context(ctx.directory, request -> {
			outsideRequests.push(request);
			return {allowed: true};
		}));
		eq(Fs.readFileSync(outsideFile, "utf8"), "beta\n", "edit external file content");
		eq(outsideRequests.length, 2, "edit external permission count");
		eq(outsideRequests[0].permission, "external_directory", "edit external permission kind");
		final outsidePattern = ToolPaths.normalize(NodePath.join(outsideDir, "*"));
		eq(outsideRequests[0].patterns.join(","), outsidePattern, "edit external permission pattern");
		eq(outsideRequests[0].always.join(","), outsidePattern, "edit external permission always");
		final outsideMetadata = Json.stringify(outsideRequests[0].metadata);
		eq(outsideMetadata.indexOf('"filepath":"' + jsonPath(outsideFile) + '"') != -1, true, "edit external metadata filepath");
		eq(outsideMetadata.indexOf('"parentDir":"' + jsonPath(outsideDir) + '"') != -1, true, "edit external metadata parent");
		eq(outsideRequests[1].permission, "edit", "edit external edit permission kind");
		eq(outsideRequests[1].patterns.join(","), ToolPaths.relative(ctx, outsideFile), "edit external edit permission pattern");

		final deniedExternalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "edit outside blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("edit"), {
			filePath: outsideFile,
			oldString: "beta",
			newString: "blocked"
		}, deniedExternalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "edit" && message.indexOf("edit outside blocked") != -1;
				case _: false;
			}
		}, "edit external directory denied");
		eq(Fs.readFileSync(outsideFile, "utf8"), "beta\n", "edit external denied avoids file mutation");
		Fs.rmSync(outsideDir, {recursive: true, force: true});
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
		final result = registry.execute(ToolIDs.known("apply_patch"), {patchText: patch}, ctx);
		eq(result.output.indexOf("A src/patch-added.txt") != -1, true, "patch add summary");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/patch-added.txt"), "utf8"), "one\ntwo\n", "patch add content");
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/c.ts"), "utf8").indexOf("other = 3") != -1, true, "patch update content");
		eq(Fs.existsSync(NodePath.join(ctx.directory, "src/b.txt")), false, "patch delete content");
		eq(metadataText(result).indexOf('"type":"add"') != -1, true, "patch metadata type");

		write(ctx.directory, "src/move-from.txt", "move me\n");
		registry.execute(ToolIDs.known("apply_patch"), {
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
		registry.execute(ToolIDs.known("apply_patch"), {
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

		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: "cat <<'EOF'\n*** Begin Patch\n*** Add File: src/heredoc.txt\n+wrapped\n*** End Patch\nEOF"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/heredoc.txt"), "utf8"), "wrapped\n", "patch heredoc");

		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: "<<EOF\n*** Begin Patch\n*** Add File: src/heredoc-no-cat.txt\n+no cat prefix\n*** End Patch\nEOF"
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/heredoc-no-cat.txt"), "utf8"), "no cat prefix\n", "patch heredoc no cat");

		write(ctx.directory, "src/insert-only.txt", "alpha\nomega\n");
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/insert-only.txt",
				"@@",
				" alpha",
				"+beta",
				" omega",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/insert-only.txt"), "utf8"), "alpha\nbeta\nomega\n", "patch insert-only hunk");

		write(ctx.directory, "src/context-disambig.txt", "fn a\nx=10\ny=2\nfn b\nx=10\ny=20\n");
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/context-disambig.txt",
				"@@ fn b",
				"-x=10",
				"+x=11",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/context-disambig.txt"), "utf8"), "fn a\nx=10\ny=2\nfn b\nx=11\ny=20\n",
			"patch context disambiguation");

		write(ctx.directory, "src/trailing-ws.txt", "line1  \nline2\nline3   \n");
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/trailing-ws.txt",
				"@@",
				"-line2",
				"+changed",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/trailing-ws.txt"), "utf8"), "line1  \nchanged\nline3   \n", "patch trailing whitespace match");

		write(ctx.directory, "src/leading-ws.txt", "  line1\nline2\n  line3\n");
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/leading-ws.txt",
				"@@",
				"-line2",
				"+changed",
				"*** End Patch",
			].join("\n")
		}, ctx);
		eq(Fs.readFileSync(NodePath.join(ctx.directory, "src/leading-ws.txt"), "utf8"), "  line1\nchanged\n  line3\n", "patch leading whitespace match");

		write(ctx.directory, "src/unicode.txt", "He said \u201Chello\u201D\nsome\u2014dash\nend\n");
		registry.execute(ToolIDs.known("apply_patch"), {
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

		final bom = String.fromCharCode(0xfeff);
		final bomFile = NodePath.join(ctx.directory, "src/patch-bom.cs");
		Fs.writeFileSync(bomFile, bom + "using System;\n\nclass Test {}\n", "utf8");
		final bomPatch = registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/patch-bom.cs",
				"@@",
				" class Test {}",
				"+class Next {}",
				"*** End Patch",
			].join("\n")
		}, ctx);
		final bomContent = Fs.readFileSync(bomFile, "utf8");
		eq(bomContent.charCodeAt(0), 0xfeff, "patch preserves existing BOM");
		eq(bomContent.substr(1), "using System;\n\nclass Test {}\nclass Next {}\n", "patch changes visible BOM content");
		final bomMetadata = Json.stringify(bomPatch.metadata);
		eq(bomMetadata.indexOf(bom) == -1, true, "patch BOM diff hides marker");
		eq(bomMetadata.indexOf("-using System;") == -1, true, "patch BOM diff avoids first-line churn");
		eq(bomMetadata.indexOf("+using System;") == -1, true, "patch BOM diff avoids first-line add churn");

		final formattedBom = NodePath.join(ctx.directory, "src/patch-formatted-bom.cs");
		Fs.writeFileSync(formattedBom, bom + "using System;\nclass Test {}\n", "utf8");
		var formattedPath = "";
		final formattedCtx:ToolContext = {
			directory: ctx.directory,
			sessionID: ctx.sessionID,
			messageID: ctx.messageID,
			ask: ctx.ask,
			formatFile: file -> {
				formattedPath = file;
				final formatted = ToolBom.split(Fs.readFileSync(file, "utf8")).text;
				Fs.writeFileSync(file, formatted, "utf8");
				return true;
			}
		};
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/patch-formatted-bom.cs",
				"@@",
				"-using System;",
				"+using Formatted;",
				"*** End Patch",
			].join("\n")
		}, formattedCtx);
		final formattedBomContent = Fs.readFileSync(formattedBom, "utf8");
		eq(formattedPath, formattedBom, "patch formatter receives target path");
		eq(formattedBomContent.charCodeAt(0), 0xfeff, "patch restores BOM after formatter");
		eq(formattedBomContent.substr(1), "using Formatted;\nclass Test {}\n", "patch keeps formatted content after BOM restore");

		final patchBus = new BusRuntime();
		final patchEdited:Array<String> = [];
		final patchWatcher:Array<String> = [];
		collectFileEvents(patchBus, patchEdited, patchWatcher);
		final patchBusCtx = contextWithBus(ctx, patchBus);
		write(ctx.directory, "src/patch-event-update.txt", "old\n");
		write(ctx.directory, "src/patch-event-move.txt", "move\n");
		write(ctx.directory, "src/patch-event-delete.txt", "delete\n");
		final patchAdd = NodePath.join(ctx.directory, "src/patch-event-add.txt");
		final patchUpdate = NodePath.join(ctx.directory, "src/patch-event-update.txt");
		final patchMoveFrom = NodePath.join(ctx.directory, "src/patch-event-move.txt");
		final patchMoveTo = NodePath.join(ctx.directory, "src/patch-event-moved.txt");
		final patchDelete = NodePath.join(ctx.directory, "src/patch-event-delete.txt");
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Add File: src/patch-event-add.txt",
				"+add",
				"*** Update File: src/patch-event-update.txt",
				"@@",
				"-old",
				"+new",
				"*** Update File: src/patch-event-move.txt",
				"*** Move to: src/patch-event-moved.txt",
				"@@",
				"-move",
				"+moved",
				"*** Delete File: src/patch-event-delete.txt",
				"*** End Patch",
			].join("\n")
		}, patchBusCtx);
		eq(patchEdited.join("|"), [patchAdd, patchUpdate, patchMoveTo].join("|"), "patch publishes edited add/update/move target events");
		eq(patchWatcher.join("|"), [
			patchAdd + ":add",
			patchUpdate + ":change",
			patchMoveFrom + ":unlink",
			patchMoveTo + ":add",
			patchDelete + ":unlink",
		].join("|"), "patch publishes watcher add/change/unlink events");

		final outsideDir = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-patch-outside-"));
		final outsideAdd = NodePath.join(outsideDir, "added.txt");
		final outsideRequests:Array<ToolPermissionRequest> = [];
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: ["*** Begin Patch", '*** Add File: ${outsideAdd}', "+outside", "*** End Patch",].join("\n")
		}, context(ctx.directory, request -> {
			outsideRequests.push(request);
			return {allowed: true};
		}));
		eq(Fs.readFileSync(outsideAdd, "utf8"), "outside\n", "patch external add content");
		eq(outsideRequests.length, 2, "patch external add permission count");
		eq(outsideRequests[0].permission, "external_directory", "patch external add permission kind");
		final outsidePattern = ToolPaths.normalize(NodePath.join(outsideDir, "*"));
		eq(outsideRequests[0].patterns.join(","), outsidePattern, "patch external add permission pattern");
		eq(outsideRequests[0].always.join(","), outsidePattern, "patch external add permission always");
		final outsideMetadata = Json.stringify(outsideRequests[0].metadata);
		eq(outsideMetadata.indexOf('"filepath":"' + jsonPath(outsideAdd) + '"') != -1, true, "patch external add metadata filepath");
		eq(outsideMetadata.indexOf('"parentDir":"' + jsonPath(outsideDir) + '"') != -1, true, "patch external add metadata parent");
		eq(outsideRequests[1].permission, "edit", "patch external add edit permission kind");
		eq(outsideRequests[1].patterns.join(","), ToolPaths.relative(ctx, outsideAdd), "patch external add edit permission pattern");

		final outsideMove = NodePath.join(outsideDir, "moved.txt");
		write(ctx.directory, "src/patch-external-move.txt", "move outside\n");
		final moveRequests:Array<ToolPermissionRequest> = [];
		registry.execute(ToolIDs.known("apply_patch"), {
			patchText: [
				"*** Begin Patch",
				"*** Update File: src/patch-external-move.txt",
				'*** Move to: ${outsideMove}',
				"@@",
				"-move outside",
				"+moved outside",
				"*** End Patch",
			].join("\n")
		}, context(ctx.directory, request -> {
			moveRequests.push(request);
			return {allowed: true};
		}));
		eq(Fs.existsSync(NodePath.join(ctx.directory, "src/patch-external-move.txt")), false, "patch external move removes source");
		eq(Fs.readFileSync(outsideMove, "utf8"), "moved outside\n", "patch external move target content");
		eq(moveRequests.length, 2, "patch external move permission count");
		eq(moveRequests[0].permission, "external_directory", "patch external move permission kind");
		eq(moveRequests[0].patterns.join(","), outsidePattern, "patch external move permission pattern");
		eq(moveRequests[1].permission, "edit", "patch external move edit permission kind");
		eq(moveRequests[1].patterns.join(","), ToolPaths.relative(ctx, outsideMove), "patch external move edit permission pattern");

		final deniedAdd = NodePath.join(outsideDir, "denied.txt");
		final deniedExternalCtx = context(ctx.directory, request -> {
			if (request.permission == "external_directory")
				return {allowed: false, reason: "patch outside blocked"};
			return {allowed: true};
		});
		expectToolFailure(() -> registry.execute(ToolIDs.known("apply_patch"), {
			patchText: ["*** Begin Patch", '*** Add File: ${deniedAdd}', "+blocked", "*** End Patch",].join("\n")
		}, deniedExternalCtx), function(failure) {
			return switch failure {
				case PermissionDenied(id, message): id == "apply_patch" && message.indexOf("patch outside blocked") != -1;
				case _: false;
			}
		}, "patch external directory denied");
		eq(Fs.existsSync(deniedAdd), false, "patch external denied avoids file write");
		Fs.rmSync(outsideDir, {recursive: true, force: true});

		expectToolFailure(() -> registry.execute(ToolIDs.known("apply_patch"), {patchText: "*** Begin Patch\n*** Frobnicate File: foo\n*** End Patch"}, ctx),
			function(failure) {
				return switch failure {
					case ExecutionFailed(id, message): id == "apply_patch" && message.indexOf("no hunks found") != -1;
					case _: false;
				}
			}, "patch malformed header");

		expectToolFailure(() -> registry.execute(ToolIDs.known("apply_patch"), {
			patchText: "*** Begin Patch\n*** Delete File: src/missing-delete.txt\n*** End Patch"
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "apply_patch" && message.indexOf("Failed to read file to delete") != -1;
				case _: false;
			}
		}, "patch missing delete failure");

		Fs.mkdirSync(NodePath.join(ctx.directory, "src/delete-dir"), {recursive: true});
		expectToolFailure(() -> registry.execute(ToolIDs.known("apply_patch"), {
			patchText: "*** Begin Patch\n*** Delete File: src/delete-dir\n*** End Patch"
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "apply_patch" && message.indexOf("Failed to read file to delete") != -1;
				case _: false;
			}
		}, "patch delete directory failure");

		expectToolFailure(() -> registry.execute(ToolIDs.known("apply_patch"), {
			patchText: "*** Begin Patch\n*** Add File: src/should-not-exist.txt\n+hello\n*** Update File: src/missing.txt\n@@\n-old\n+new\n*** End Patch"
		}, ctx), function(failure) {
			return switch failure {
				case ExecutionFailed(id, message): id == "apply_patch" && message.indexOf("Failed to read file to update") != -1;
				case _: false;
			}
		}, "patch verification no side effects");
		eq(Fs.existsSync(NodePath.join(ctx.directory, "src/should-not-exist.txt")), false, "patch no side effects");
	}

	@:async
	static function webFetchExec(ctx:ToolContext):Promise<Void> {
		final text = await(WebFetchTool.executeRaw({
			url: "data:text/plain;charset=utf-8,hello%20from%20webfetch",
			format: "text"
		}, ctx));
		eq(text.output, "hello from webfetch", "webfetch text output");
		eq(text.attachments == null, true, "webfetch text attachments absent");

		final svg = '<svg xmlns="http://www.w3.org/2000/svg"><text>hello</text></svg>';
		final svgResult = await(WebFetchTool.executeRaw({
			url: "data:image/svg+xml;charset=UTF-8," + StringTools.urlEncode(svg),
			format: "html"
		}, ctx));
		eq(svgResult.output.indexOf("<svg") != -1, true, "webfetch svg text output");
		eq(svgResult.attachments == null, true, "webfetch svg attachments absent");

		final image = await(WebFetchTool.executeRaw({
			url: "data:image/png;base64,iVBORw0KGgo=",
			format: "markdown"
		}, ctx));
		eq(image.output, "Image fetched successfully", "webfetch image output");
		if (image.attachments == null)
			throw "webfetch image expected attachments";
		eq(image.attachments.length, 1, "webfetch image attachment count");
		eq(image.attachments[0].type, "file", "webfetch image attachment type");
		eq(image.attachments[0].mime, "image/png", "webfetch image attachment mime");
		eq(StringTools.startsWith(image.attachments[0].url, "data:image/png;base64,"), true, "webfetch image attachment data url");
	}

	@:async
	static function questionExec(ctx:ToolContext):Promise<Void> {
		final service = new QuestionService();
		final resultPromise = QuestionTool.executeRaw({
			questions: [
				{
					question: "What is your favorite color?",
					header: "Color",
					options: [
						{label: "Red", description: "The color of passion"},
						{label: "Blue", description: "The color of sky"},
					],
					multiple: false,
				}
			],
		}, ctx, service);
		final pending = await(pendingQuestion(service, "question tool pending"));
		eq(pending.questions[0].question, "What is your favorite color?", "question tool request text");
		eq(pending.tool.callID, "call_tool", "question tool call metadata");
		eq(pending.tool.messageID.toString(), "msg_tool", "question tool message metadata");
		await(service.reply({requestID: pending.id, answers: [["Red"]]}));
		final result = await(resultPromise);
		eq(result.title, "Asked 1 question", "question tool title");
		eq(result.output.indexOf('"What is your favorite color?"="Red"') != -1, true, "question tool output answer");
		eq(Json.stringify(result.metadata).indexOf('"Red"') != -1, true, "question tool metadata answers");

		final longHeaderService = new QuestionService();
		final longHeaderPromise = QuestionTool.executeRaw({
			questions: [
				{
					question: "What is your favorite animal?",
					header: "This Header is Over 12",
					options: [{label: "Dog", description: "Man's best friend"}],
				}
			],
		}, ctx, longHeaderService);
		final longHeaderPending = await(pendingQuestion(longHeaderService, "question tool long header pending"));
		eq(longHeaderPending.questions[0].header, "This Header is Over 12", "question tool long header preserved");
		await(longHeaderService.reply({requestID: longHeaderPending.id, answers: [["Dog"]]}));
		final longHeaderResult = await(longHeaderPromise);
		eq(longHeaderResult.output.indexOf('"What is your favorite animal?"="Dog"') != -1, true, "question tool long header output");
	}

	@:async
	static function skillExec(ctx:ToolContext):Promise<Void> {
		final skillDir = NodePath.join(NodePath.join(NodePath.join(ctx.directory, ".opencode"), "skill"), "tool-skill");
		write(ctx.directory, ".opencode/skill/tool-skill/SKILL.md", '---
name: tool-skill
description: Skill for tool tests.
---

# Tool Skill

Use this skill.
');
		write(ctx.directory, ".opencode/skill/tool-skill/scripts/demo.txt", "demo");

		final requests:Array<ToolPermissionRequest> = [];
		final result = await(SkillTool.executeRaw({name: "tool-skill"}, context(ctx.directory, request -> {
			requests.push(request);
			return {allowed: true};
		})));
		final file = NodePath.resolve(NodePath.join(NodePath.join(skillDir, "scripts"), "demo.txt"), "");
		eq(requests.length, 1, "skill tool permission count");
		eq(requests[0].permission, "skill", "skill tool permission kind");
		eq(requests[0].patterns.indexOf("tool-skill") != -1, true, "skill tool permission patterns");
		eq(requests[0].always.indexOf("tool-skill") != -1, true, "skill tool permission always");
		eq(Json.stringify(result.metadata).indexOf('"dir":"' + skillDir) != -1, true, "skill tool metadata dir");
		eq(result.output.indexOf('<skill_content name="tool-skill">') != -1, true, "skill tool content block");
		eq(result.output.indexOf('Base directory for this skill: ${Url.pathToFileURL(skillDir).href}') != -1, true, "skill tool base url");
		eq(result.output.indexOf('<file>${file}</file>') != -1, true, "skill tool file list");
	}

	@:async
	static function pendingQuestion(service:QuestionService, label:String):Promise<QuestionRequest> {
		for (attempt in 0...20) {
			final pending = await(service.list());
			if (pending.length > 0)
				return pending[0];
			await(sleep(10));
		}
		throw '${label}: timed out';
	}

	static function context(root:String, ?ask:(ToolPermissionRequest) -> ToolPermissionDecision):ToolContext {
		return {
			directory: root,
			worktree: root,
			sessionID: "ses_tool",
			messageID: "msg_tool",
			callID: "call_tool",
			agent: "build",
			toolOutputDir: NodePath.join(root, "tool-output"),
			ask: ask,
		};
	}

	static function contextWithBus(ctx:ToolContext, bus:BusRuntime):ToolContext {
		return {
			directory: ctx.directory,
			worktree: ctx.worktree,
			sessionID: ctx.sessionID,
			messageID: ctx.messageID,
			callID: ctx.callID,
			agent: ctx.agent,
			toolOutputDir: ctx.toolOutputDir,
			instructionClaims: ctx.instructionClaims,
			loadedInstructions: ctx.loadedInstructions,
			formatFile: ctx.formatFile,
			bus: bus,
			ask: ctx.ask,
		};
	}

	static function collectFileEvents(bus:BusRuntime, edited:Array<String>, watcher:Array<String>):Void {
		bus.subscribe(FileToolEvents.Edited, event -> edited.push(event.properties.file));
		bus.subscribe(FileToolEvents.WatcherUpdated, event -> watcher.push(event.properties.file + ":" + event.properties.event));
	}

	static function contextWithInstructionClaims(root:String, messageID:String, claims:SessionInstructionClaims):ToolContext {
		return {
			directory: root,
			worktree: root,
			sessionID: "ses_tool",
			messageID: messageID,
			callID: "call_tool",
			agent: "build",
			toolOutputDir: NodePath.join(root, "tool-output"),
			instructionClaims: claims,
		};
	}

	static function write(root:String, relative:String, content:String):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function writeBytes(root:String, relative:String, content:NodeBufferData):Void {
		final path = NodePath.join(root, relative);
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function onlyAttachment(result:ToolResult, label:String):ToolResultAttachment {
		final attachments = result.attachments;
		if (attachments == null)
			throw '${label}: expected attachment';
		eq(attachments.length, 1, '${label} attachment count');
		return attachments[0];
	}

	static function numberedLines(count:Int):String {
		return [for (i in 0...count) 'line${i}'].join("\n");
	}

	static function numberedLinesWithPayload(count:Int, payload:String):String {
		return [for (i in 0...count) 'line${i}:${payload}'].join("\n");
	}

	static function repeat(text:String, count:Int):String {
		final out:Array<String> = [];
		for (_ in 0...count)
			out.push(text);
		return out.join("");
	}

	static function present<T>(value:Null<T>, label:String):T {
		if (value == null)
			throw '${label}: expected present value';
		return value;
	}

	static function jsonPath(path:String):String {
		return StringTools.replace(path, "\\", "\\\\");
	}

	static function metadataText(result:ToolResult):String {
		return Json.stringify(result.metadata);
	}

	static function savedOutputPath(output:String, label:String):String {
		final marker = "Full output saved to: ";
		final start = output.indexOf(marker);
		if (start == -1)
			throw '${label}: expected saved output marker';
		final pathStart = start + marker.length;
		final lineEnd = output.indexOf("\n", pathStart);
		if (lineEnd == -1)
			return output.substr(pathStart);
		return output.substr(pathStart, lineEnd - pathStart);
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
