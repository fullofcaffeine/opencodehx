package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import js.Syntax;
import js.lib.Promise;
import js.lib.Error as JsError;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Process;
import opencodehx.externs.web.AbortControllerWithReason;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;
import opencodehx.util.Abort;
import opencodehx.util.Color;
import opencodehx.util.DataUrl;
import opencodehx.util.ErrorTools;
import opencodehx.util.Format;
import opencodehx.util.GlobRuntime;
import opencodehx.util.Iife;
import opencodehx.util.Lazy;
import opencodehx.util.Lock;
import opencodehx.util.LogRuntime;
import opencodehx.util.ModuleResolver;
import opencodehx.util.ProcessRuntime;
import opencodehx.util.Timeout;
import opencodehx.util.Wildcard;
import opencodehx.util.Which;

class UtilSmoke {
	public static function run():Void {
		formatDuration();
		color();
		iife();
		errorTools();
		lazy();
		dataUrl();
		wildcard();
		which();
		moduleResolver();
		logCleanup();
	}

	@:async
	public static function runAsync():Promise<Void> {
		@:await timeout();
		@:await abort();
		@:await lock();
		@:await process();
		@:await glob();
	}

	static function formatDuration():Void {
		eq(Format.formatDuration(0), "", "duration zero");
		eq(Format.formatDuration(-100), "", "duration negative");
		eq(Format.formatDuration(59), "59s", "duration seconds");
		eq(Format.formatDuration(60), "1m", "duration minute boundary");
		eq(Format.formatDuration(61), "1m 1s", "duration minute seconds");
		eq(Format.formatDuration(3599), "59m 59s", "duration hour boundary");
		eq(Format.formatDuration(3600), "1h", "duration hour");
		eq(Format.formatDuration(86399), "23h 59m", "duration day boundary");
		eq(Format.formatDuration(86400), "~1 day", "duration day");
		eq(Format.formatDuration(604799), "~6 days", "duration week boundary");
		eq(Format.formatDuration(604800), "~1 week", "duration week");
		eq(Format.formatDuration(1209600), "~2 weeks", "duration weeks");
	}

	static function color():Void {
		eq(Color.hexToAnsiBold("#FFA500"), "\x1b[38;2;255;165;0m\x1b[1m", "hex ansi bold");
		eq(Color.hexToAnsiBold(null), null, "null hex ansi bold");
		eq(Color.hexToAnsiBold(""), null, "empty hex ansi bold");
		eq(Color.hexToAnsiBold("#FFF"), null, "short hex ansi bold");
		eq(Color.hexToAnsiBold("FFA500"), null, "missing hash hex ansi bold");
		eq(Color.hexToAnsiBold("#GGGGGG"), null, "invalid hex ansi bold");
		eq(Color.hexToAnsiBold("primary"), null, "theme color is not hex ansi bold");
	}

	static function iife():Void {
		var syncCalled = false;
		final syncResult = Iife.iife(() -> {
			syncCalled = true;
			return 42;
		});
		eq(syncCalled, true, "iife sync called");
		eq(syncResult, 42, "iife sync result");

		var asyncCalled = false;
		final promise = new Promise<String>((resolve, _) -> resolve("async result"));
		final asyncResult = Iife.iife(() -> {
			asyncCalled = true;
			return promise;
		});
		eq(asyncCalled, true, "iife async called");
		eq(asyncResult == promise, true, "iife async promise passthrough");

		var voidCalled = false;
		Iife.iife(() -> {
			voidCalled = true;
		});
		eq(voidCalled, true, "iife void called");
	}

	static function lazy():Void {
		var calls = 0;
		final value = new Lazy(() -> {
			calls++;
			return "expensive value";
		});

		eq(calls, 0, "lazy before get");
		eq(value.get(), "expensive value", "lazy first get");
		eq(calls, 1, "lazy first call count");
		eq(value.get(), "expensive value", "lazy second get");
		eq(calls, 1, "lazy second call count");
		value.reset();
		eq(value.get(), "expensive value", "lazy reset get");
		eq(calls, 2, "lazy reset call count");
	}

	static function dataUrl():Void {
		final body = "{\n  \"ok\": true\n}\n";
		eq(DataUrl.decode("data:text/plain;base64,ewogICJvayI6IHRydWUKfQo="), body, "data-url base64");
		eq(DataUrl.decode("data:text/plain,hello%20world"), "hello world", "data-url plain");
		eq(DataUrl.decode("data:text/plain,hello+world"), "hello+world", "data-url plus parity");
		eq(DataUrl.decode("not-a-data-url"), "", "data-url missing comma");
	}

	static function wildcard():Void {
		eq(Wildcard.match("file1.txt", "file?.txt"), true, "wildcard question");
		eq(Wildcard.match("file12.txt", "file?.txt"), false, "wildcard question length");
		eq(Wildcard.match("foo+bar", "foo+bar"), true, "wildcard escapes regex plus");

		eq(Wildcard.match("ls", "ls *"), true, "wildcard command optional args");
		eq(Wildcard.match("ls -la", "ls *"), true, "wildcard command args");
		eq(Wildcard.match("ls foo bar", "ls *"), true, "wildcard command multi args");
		eq(Wildcard.match("ls", "ls*"), true, "wildcard adjacent star empty");
		eq(Wildcard.match("lstmeval", "ls*"), true, "wildcard adjacent star broad");
		eq(Wildcard.match("lstmeval", "ls *"), false, "wildcard command space protects");
		eq(Wildcard.match("git status", "git *"), true, "wildcard git status args");
		eq(Wildcard.match("git", "git *"), true, "wildcard git no args");
		eq(Wildcard.match("git commit -m foo", "git *"), true, "wildcard git commit args");

		final rules = [
			{pattern: "*", value: "deny"},
			{pattern: "git *", value: "ask"},
			{pattern: "git status", value: "allow"},
		];
		eq(Wildcard.all("git status", rules), "allow", "wildcard all most specific");
		eq(Wildcard.all("git log", rules), "ask", "wildcard all command");
		eq(Wildcard.all("echo hi", rules), "deny", "wildcard all fallback");

		final structured = [{pattern: "git *", value: "ask"}, {pattern: "git status*", value: "allow"},];
		eq(Wildcard.allStructured({head: "git", tail: ["status", "--short"]}, structured), "allow", "wildcard structured status");
		eq(Wildcard.allStructured({head: "npm", tail: ["run", "build", "--watch"]}, [{pattern: "npm run *", value: "allow"}]), "allow",
			"wildcard structured npm");
		eq(Wildcard.allStructured({head: "ls", tail: ["-la"]}, structured), null, "wildcard structured missing");

		final flagRules = [
			{pattern: "find *", value: "allow"},
			{pattern: "find * -delete*", value: "ask"},
			{pattern: "sort*", value: "allow"},
			{pattern: "sort -o *", value: "ask"},
		];
		eq(Wildcard.allStructured({head: "find", tail: ["src", "-delete"]}, flagRules), "ask", "wildcard structured delete");
		eq(Wildcard.allStructured({head: "find", tail: ["src", "-print"]}, flagRules), "allow", "wildcard structured print");
		eq(Wildcard.allStructured({head: "sort", tail: ["-o", "out.txt"]}, flagRules), "ask", "wildcard structured sort output");
		eq(Wildcard.allStructured({head: "sort", tail: ["--reverse"]}, flagRules), "allow", "wildcard structured sort reverse");

		final sedRules = [{pattern: "sed * -i*", value: "ask"}, {pattern: "sed -n*", value: "allow"},];
		eq(Wildcard.allStructured({head: "sed", tail: ["-i", "file"]}, sedRules), "ask", "wildcard structured sed in-place");
		eq(Wildcard.allStructured({head: "sed", tail: ["-i.bak", "file"]}, sedRules), "ask", "wildcard structured sed backup");
		eq(Wildcard.allStructured({head: "sed", tail: ["-n", "1p", "file"]}, sedRules), "allow", "wildcard structured sed print");
		eq(Wildcard.allStructured({head: "sed", tail: ["-i", "-n", "/./p", "myfile.txt"]}, sedRules), "ask", "wildcard structured sed mixed");

		eq(Wildcard.match("C:\\Windows\\System32\\*", "C:/Windows/System32/*"), true, "wildcard slash pattern");
		eq(Wildcard.match("C:/Windows/System32/drivers", "C:\\Windows\\System32\\*"), true, "wildcard slash value");
		if (NodeProcess.platform() == "win32") {
			eq(Wildcard.match("C:\\windows\\system32\\hosts", "C:/Windows/System32/*"), true, "wildcard windows case path");
			eq(Wildcard.match("c:/windows/system32/hosts", "C:\\Windows\\System32\\*"), true, "wildcard windows case drive");
		} else {
			eq(Wildcard.match("/users/test/file", "/Users/test/*"), false, "wildcard unix case sensitive");
		}
	}

	static function which():Void {
		eq(Which.which("opencode-missing-command-for-test"), null, "which missing command");

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-which-"));
		try {
			final bin = NodePath.join(root, "bin");
			Fs.mkdirSync(bin, {recursive: true});
			final tool = command(bin, "tool", true);
			samePath(Which.which("tool", envPath(bin)), tool, "which path override");

			final firstDir = NodePath.join(root, "a");
			final secondDir = NodePath.join(root, "b");
			Fs.mkdirSync(firstDir, {recursive: true});
			Fs.mkdirSync(secondDir, {recursive: true});
			final first = command(firstDir, "dupe", true);
			command(secondDir, "dupe", true);
			samePath(Which.which("dupe", envPath(firstDir + pathDelimiter() + secondDir)), first, "which first path match");

			if (NodeProcess.platform() != "win32") {
				final noexec = command(bin, "noexec", false);
				eq(Fs.existsSync(noexec), true, "which noexec fixture exists");
				eq(Which.which("noexec", envPath(bin)), null, "which rejects unix noexec");
			} else {
				final pathext = NodePath.join(bin, "pathext.CMD");
				Fs.writeFileSync(pathext, "@echo off\r\n");
				samePath(Which.which("pathext", envPath(bin, ".CMD")), pathext, "which windows pathext");

				final mixed = command(bin, "mixed", true);
				final mixedEnv = new DynamicAccess<String>();
				mixedEnv.set("Path", bin);
				final pathExt = NodeProcess.envValue("PathExt");
				mixedEnv.set("PathExt", pathExt == null ? ".CMD;.EXE;.BAT;.COM" : pathExt);
				samePath(Which.which("mixed", mixedEnv), mixed, "which windows path casing");
			}
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function moduleResolver():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-module-"));
		try {
			final project = NodePath.join(root, "proj");
			final tsserver = NodePath.join(project, "node_modules/typescript/lib/tsserver.js");
			write(tsserver, "export {}\n");
			write(NodePath.join(project, "node_modules/typescript/package.json"), '{"name":"typescript"}');
			eq(ModuleResolver.resolve("typescript/lib/tsserver.js", project), tsserver, "module resolver subpath");

			final cwd = NodePath.join(project, "apps/web");
			final eslint = NodePath.join(project, "node_modules/eslint/lib/api.js");
			write(eslint, "export {}\n");
			write(NodePath.join(project, "node_modules/eslint/package.json"), '{"name":"eslint","main":"lib/api.js"}');
			write(NodePath.join(cwd, ".keep"), "");
			eq(ModuleResolver.resolve("eslint", cwd), eslint, "module resolver ancestor package");

			final leftRoot = NodePath.join(root, "a");
			final rightRoot = NodePath.join(root, "b");
			final left = NodePath.join(leftRoot, "node_modules/biome/index.js");
			final right = NodePath.join(rightRoot, "node_modules/biome/index.js");
			write(left, "export {}\n");
			write(right, "export {}\n");
			write(NodePath.join(leftRoot, "node_modules/biome/package.json"), '{"name":"biome","main":"index.js"}');
			write(NodePath.join(rightRoot, "node_modules/biome/package.json"), '{"name":"biome","main":"index.js"}');
			eq(ModuleResolver.resolve("biome", leftRoot), left, "module resolver left root");
			eq(ModuleResolver.resolve("biome", rightRoot), right, "module resolver right root");
			eq(ModuleResolver.resolve("biome", leftRoot) != ModuleResolver.resolve("biome", rightRoot), true, "module resolver roots distinct");
			eq(ModuleResolver.resolve("missing-package", root), null, "module resolver missing");
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function logCleanup():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-log-"));
		try {
			final logs:Array<String> = [];
			for (i in 0...12) {
				final name = '2000-01-${pad2(i + 1)}T000000.log';
				logs.push(name);
				Fs.writeFileSync(NodePath.join(root, name), name);
			}
			Fs.writeFileSync(NodePath.join(root, "nested.log"), "not timestamped");

			final path = LogRuntime.init(root, {print: false, dev: false});
			if (path == null)
				throw "log init path should be set when print is false";

			final next = Fs.readdirNamesSync(root);
			next.sort((a, b) -> Reflect.compare(a, b));
			eq(next.indexOf(logs[0]), -1, "log cleanup removes oldest timestamped log");
			eq(next.indexOf(logs[logs.length - 1]) != -1, true, "log cleanup keeps newest timestamped log");
			eq(next.indexOf("nested.log") != -1, true, "log cleanup ignores non-timestamped log");
			eq(next.filter((name) -> StringTools.endsWith(name, ".log")).length, 12, "log cleanup keeps ten plus current and non-timestamped");

			final devRoot = Fs.mkdtempSync(NodePath.join(root, "dev-"));
			final devPath = LogRuntime.init(devRoot, {print: false, dev: true});
			eq(devPath, NodePath.join(devRoot, "dev.log"), "log dev path");
			eq(LogRuntime.init(devRoot, {print: true}), null, "log print mode skips file");
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	static function timeout():Promise<Void> {
		final fast = @:await Timeout.withTimeout(delayValue("fast", 10), 100);
		eq(fast, "fast", "timeout fast result");

		final error = @:await Timeout.withTimeout(delayValue("slow", 200), 50).then(_ -> {
			return null;
		}).catchError(error -> {
			return error;
		});
		if (error == null)
			throw "timeout slow promise should reject";
		eq(Std.string(Reflect.field(error, "message")), "Operation timed out after 50ms", "timeout rejection message");
	}

	@:async
	static function abort():Promise<Void> {
		final timed = Abort.abortAfter(5);
		eq(timed.signal.aborted, false, "abort after starts active");
		@:await delayValue("aborted", 20);
		eq(timed.signal.aborted, true, "abort after timeout aborts");
		timed.clearTimeout();

		final cleared = Abort.abortAfter(30);
		cleared.clearTimeout();
		@:await delayValue("cleared", 50);
		eq(cleared.signal.aborted, false, "abort after clear prevents abort");

		final controller = new AbortControllerWithReason();
		final combined = Abort.abortAfterAny(1000, [controller.signal]);
		eq(combined.signal.aborted, false, "abort any starts active");
		controller.abort();
		@:await flush();
		eq(combined.signal.aborted, true, "abort any input aborts combined signal");
		combined.clearTimeout();
	}

	@:async
	static function lock():Promise<Void> {
		final key = "lock:" + Std.random(1000000);
		var writer2Acquired = false;
		var readerAcquired = false;
		var writers = 0;

		final writer1 = @:await Lock.write(key);
		writers++;
		eq(writers, 1, "lock writer1 acquired");

		final writer2Task = Lock.write(key).then(writer2 -> {
			writers++;
			eq(writers, 1, "lock writer2 exclusive");
			writer2Acquired = true;
			return tick().then(_ -> writer2);
		});

		final readerTask = Lock.read(key).then(reader -> {
			readerAcquired = true;
			return reader;
		});

		@:await flush();
		eq(writer2Acquired, false, "lock writer2 blocked by writer1");
		eq(readerAcquired, false, "lock reader blocked by writer1");

		writer1.dispose();
		writers--;
		final writer2 = @:await writer2Task;
		eq(writer2Acquired, true, "lock writer2 acquired after writer1");

		@:await flush();
		eq(readerAcquired, false, "lock reader waits behind writer2");

		writer2.dispose();
		writers--;
		final reader = @:await readerTask;
		eq(readerAcquired, true, "lock reader acquired after writer2");
		reader.dispose();
	}

	@:async
	static function process():Promise<Void> {
		final out = @:await ProcessRuntime.run(node('process.stdout.write("out");process.stderr.write("err")'));
		eq(out.code, 0, "process run code");
		eq(out.stdout, "out", "process stdout");
		eq(out.stderr, "err", "process stderr");

		final nonzero = @:await ProcessRuntime.run(node("process.exit(7)"), {nothrow: true});
		eq(nonzero.code, 7, "process nothrow code");

		final failed:Dynamic = @:await ProcessRuntime.run(node('process.stderr.write("bad");process.exit(3)')).then(_ -> null).catchError(error -> error);
		if (Reflect.field(failed, "name") != "ProcessRunFailedError")
			throw "process failure should reject with ProcessRunFailedError";
		eq(Reflect.field(failed, "code"), 3, "process failed code");
		eq(Reflect.field(failed, "stderr"), "bad", "process failed stderr");

		final abort = new AbortControllerWithReason();
		WebTimers.setTimeout(() -> abort.abort(), 25);
		final started = nowMillis();
		final aborted = @:await ProcessRuntime.run(node("setInterval(() => {}, 1000)"), {abort: abort.signal, nothrow: true});
		eq(aborted.code != 0, true, "process abort code");
		eq(nowMillis() - started < 1000, true, "process abort duration");

		if (NodeProcess.platform() != "win32") {
			final stubborn = new AbortControllerWithReason();
			WebTimers.setTimeout(() -> stubborn.abort(), 25);
			final stubbornStarted = nowMillis();
			final killed = @:await ProcessRuntime.run(node('process.on("SIGTERM", () => {}); setInterval(() => {}, 1000)'), {
				abort: stubborn.signal,
				nothrow: true,
				timeout: 25,
			});
			eq(killed.code != 0, true, "process abort sigkill code");
			eq(nowMillis() - stubbornStarted < 1000, true, "process abort sigkill duration");
		}

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-process-"));
		try {
			final cwdOut = @:await ProcessRuntime.run(node("process.stdout.write(process.cwd())"), {cwd: root});
			eq(NodePath.normalize(Fs.realpathSync(cwdOut.stdout)), NodePath.normalize(Fs.realpathSync(root)), "process cwd");

			final env = new DynamicAccess<String>();
			env.set("OPENCODE_TEST", "set");
			final envOut = @:await ProcessRuntime.run(node('process.stdout.write(process.env.OPENCODE_TEST ?? "")'), {env: env});
			eq(envOut.stdout, "set", "process env");

			if (NodeProcess.platform() == "win32") {
				final shellEnv = new DynamicAccess<String>();
				shellEnv.set("OPENCODE_TEST_SHELL", "ok");
				final shellOut = @:await ProcessRuntime.run(["set", "OPENCODE_TEST_SHELL"], {shell: true, env: shellEnv});
				eq(shellOut.stdout.indexOf("OPENCODE_TEST_SHELL=ok") != -1, true, "process windows shell");

				final dir = NodePath.join(root, "with space");
				final file = NodePath.join(dir, "echo cmd.cmd");
				Fs.mkdirSync(dir, {recursive: true});
				Fs.writeFileSync(file, "@echo off\r\nif %~1==--stdio exit /b 0\r\nexit /b 7\r\n");
				final proc = ProcessRuntime.spawn([file, "--stdio"], {stdin: "pipe", stdout: "pipe", stderr: "pipe"});
				eq(@:await proc.exited, 0, "process windows cmd with spaces");
			}

			final missing = NodePath.join(root, "missing" + (NodeProcess.platform() == "win32" ? ".cmd" : ""));
			final missingError:Dynamic = @:await ProcessRuntime.spawn([missing], {stdin: "pipe", stdout: "pipe", stderr: "pipe"})
				.exited.catchError(error -> error);
			eq(Reflect.field(missingError, "code"), "ENOENT", "process missing command error");

			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	static function glob():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-glob-"));
		try {
			write(NodePath.join(root, "a.txt"), "");
			write(NodePath.join(root, "b.txt"), "");
			write(NodePath.join(root, "c.md"), "");
			write(NodePath.join(root, "nested/deep.txt"), "");

			final txt = @:await GlobRuntime.scan("*.txt", {cwd: root});
			txt.sort(Reflect.compare);
			eq(txt.join(","), "a.txt,b.txt", "glob scan txt");

			final absolute = @:await GlobRuntime.scan("*.txt", {cwd: root, absolute: true});
			absolute.sort(Reflect.compare);
			eq(absolute.indexOf(NodePath.join(root, "a.txt")) != -1, true, "glob scan absolute");

			Fs.mkdirSync(NodePath.join(root, "subdir"), {recursive: true});
			final starFiles = @:await GlobRuntime.scan("*", {cwd: root});
			starFiles.sort(Reflect.compare);
			eq(starFiles.indexOf("subdir"), -1, "glob excludes directories by default");
			eq(starFiles.indexOf("a.txt") != -1, true, "glob includes files by default");

			final starAll = @:await GlobRuntime.scan("*", {cwd: root, include: "all"});
			starAll.sort(Reflect.compare);
			eq(starAll.indexOf("subdir") != -1, true, "glob include all directory");

			final nested = @:await GlobRuntime.scan("**/*.txt", {cwd: root});
			nested.sort(Reflect.compare);
			eq(nested.indexOf(NodePath.join("nested", "deep.txt")) != -1, true, "glob nested txt");
			eq((@:await GlobRuntime.scan("*.nonexistent", {cwd: root})).length, 0, "glob no matches");

			final symlinkRoot = NodePath.join(root, "symlink");
			Fs.mkdirSync(NodePath.join(symlinkRoot, "realdir"), {recursive: true});
			write(NodePath.join(symlinkRoot, "realdir/file.txt"), "");
			var symlinkCreated = true;
			try {
				Fs.symlinkSync(NodePath.join(symlinkRoot, "realdir"), NodePath.join(symlinkRoot, "linkdir"));
			} catch (_:Dynamic) {
				symlinkCreated = false;
			}
			if (symlinkCreated) {
				final noFollow = @:await GlobRuntime.scan("**/*.txt", {cwd: symlinkRoot});
				noFollow.sort(Reflect.compare);
				eq(noFollow.join(","), normalizePath(NodePath.join("realdir", "file.txt")), "glob skips symlink directories");
				final follow = @:await GlobRuntime.scan("**/*.txt", {cwd: symlinkRoot, symlink: true});
				follow.sort(Reflect.compare);
				eq(follow.join(","), [
					normalizePath(NodePath.join("linkdir", "file.txt")),
					normalizePath(NodePath.join("realdir", "file.txt"))
				].join(","), "glob follows symlink directories");
			}

			write(NodePath.join(root, ".hidden"), "");
			write(NodePath.join(root, "visible"), "");
			final dot = @:await GlobRuntime.scan("*", {cwd: root, dot: true});
			dot.sort(Reflect.compare);
			eq(dot.indexOf(".hidden") != -1, true, "glob dot includes hidden");
			final noDot = @:await GlobRuntime.scan("*", {cwd: root, dot: false});
			eq(noDot.indexOf(".hidden"), -1, "glob dot false excludes hidden");

			final syncTxt = GlobRuntime.scanSync("*.txt", {cwd: root});
			syncTxt.sort(Reflect.compare);
			eq(syncTxt.join(","), "a.txt,b.txt", "glob scanSync txt");
			final syncAll = GlobRuntime.scanSync("*", {cwd: root, include: "all"});
			eq(syncAll.indexOf("subdir") != -1, true, "glob scanSync include all");

			eq(GlobRuntime.match("*.txt", "file.txt"), true, "glob match simple");
			eq(GlobRuntime.match("*.txt", "file.js"), false, "glob match simple miss");
			eq(GlobRuntime.match("**/*.js", "src/index.js"), true, "glob match directory");
			eq(GlobRuntime.match("**/*.js", "src/index.ts"), false, "glob match directory miss");
			eq(GlobRuntime.match(".*", ".gitignore"), true, "glob match dot");
			eq(GlobRuntime.match("**/*.md", ".github/README.md"), true, "glob match nested dot");
			eq(GlobRuntime.match("*.{js,ts}", "file.js"), true, "glob brace js");
			eq(GlobRuntime.match("*.{js,ts}", "file.ts"), true, "glob brace ts");
			eq(GlobRuntime.match("*.{js,ts}", "file.py"), false, "glob brace miss");

			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function errorTools():Void {
		final golden:Dynamic = Json.parse(Resources.text(ResourcePaths.known("errors/diagnostics.golden.json")));
		final util:Dynamic = Reflect.field(golden, "util");

		final native = new JsError("boom");
		final nativeUnknown = Unknown.fromBoundary(native);
		final nativeData = ErrorTools.data(nativeUnknown);
		eq(ErrorTools.message(nativeUnknown), Reflect.field(util, "nativeMessage"), "native error message");
		eq(dataString(nativeData, "type"), Reflect.field(util, "nativeType"), "native error type");
		eq(dataString(nativeData, "message"), Reflect.field(util, "nativeMessage"), "native error data message");
		eq(ErrorTools.format(nativeUnknown).indexOf("boom") != -1, true, "native error formatted");
		eq(dataString(nativeData, "formatted").indexOf("boom") != -1, true, "native error data formatted");

		final record = {message: "bad input", code: "E_BAD"};
		final recordUnknown = Unknown.fromBoundary(record);
		final recordData = ErrorTools.data(recordUnknown);
		eq(ErrorTools.message(recordUnknown), Reflect.field(util, "recordMessage"), "record error message");
		eq(dataString(recordData, "message"), Reflect.field(util, "recordMessage"), "record error data message");
		eq(dataString(recordData, "code"), Reflect.field(util, "recordCode"), "record error code");

		// Upstream util/error tests use a JavaScript object literal with a custom
		// toString method. Keep this fixture at that JS boundary shape.
		final opaque:Dynamic = Syntax.code("({ toString() { return \"ResolveMessage: Cannot resolve module\"; } })");
		final opaqueUnknown = Unknown.fromBoundary(opaque);
		eq(ErrorTools.message(opaqueUnknown), Reflect.field(util, "opaqueMessage"), "opaque error message");
		eq(dataString(ErrorTools.data(opaqueUnknown), "message"), Reflect.field(util, "opaqueMessage"), "opaque error data message");
		eq(dataString(ErrorTools.data(opaqueUnknown), "formatted").indexOf("ResolveMessage") != -1, true, "opaque error data formatted");
	}

	static function dataString(data:opencodehx.util.ErrorTools.ErrorData, field:String):String {
		final value = UnknownNarrow.string(data.get(field));
		return value == null ? "" : value;
	}

	static function command(dir:String, name:String, exec:Bool):String {
		final file = NodePath.join(dir, name + (NodeProcess.platform() == "win32" ? ".cmd" : ""));
		Fs.writeFileSync(file, NodeProcess.platform() == "win32" ? "@echo off\r\n" : "#!/bin/sh\n");
		if (NodeProcess.platform() != "win32")
			Fs.chmodSync(file, exec ? 0x1ed : 0x1a4);
		return file;
	}

	static function node(script:String):Array<String> {
		return [Process.argv[0], "-e", script];
	}

	static function nowMillis():Float {
		return new js.lib.Date().getTime();
	}

	static function normalizePath(path:String):String {
		return StringTools.replace(path, "\\", "/");
	}

	static function write(path:String, content:String):Void {
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content);
	}

	static function envPath(path:String, ?pathExt:String):DynamicAccess<String> {
		final env = new DynamicAccess<String>();
		env.set("PATH", path);
		final ext = pathExt == null ? NodeProcess.envValue("PATHEXT") : pathExt;
		if (ext != null)
			env.set("PATHEXT", ext);
		return env;
	}

	static function samePath(actual:Null<String>, expected:String, label:String):Void {
		if (actual == null)
			throw '$label: expected ${expected}, got null';
		if (NodeProcess.platform() == "win32")
			eq(actual.toLowerCase(), expected.toLowerCase(), label);
		else
			eq(actual, expected, label);
	}

	static function pathDelimiter():String {
		return NodeProcess.platform() == "win32" ? ";" : ":";
	}

	static function delayValue(value:String, ms:Int):Promise<String> {
		return new Promise<String>((resolve, _) -> {
			WebTimers.setTimeout(() -> resolve(value), ms);
		});
	}

	static function tick():Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			final resolveVoid:Void->Void = cast resolve;
			Promise.resolve(null).then(_ -> {
				resolveVoid();
				return null;
			});
		});
	}

	@:async
	static function flush(?count:Int):Promise<Void> {
		final total = count == null ? 5 : count;
		for (_ in 0...total)
			@:await tick();
	}

	static function pad2(value:Int):String {
		return value < 10 ? "0" + value : Std.string(value);
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
