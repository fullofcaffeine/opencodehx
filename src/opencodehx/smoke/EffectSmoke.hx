package opencodehx.smoke;

import haxe.DynamicAccess;
import js.lib.Error;
import js.lib.Promise;
import opencodehx.effect.AppRuntimeLoggerRuntime;
import opencodehx.effect.InstanceStateRuntime;
import opencodehx.effect.ObservabilityResource;
import opencodehx.effect.RunnerRuntime;
import opencodehx.effect.RunnerRuntime.RunnerCancelledError;
import opencodehx.effect.RunnerRuntime.RunnerState;
import opencodehx.effect.RunServiceRuntime;
import opencodehx.effect.RunServiceRuntime.RunServiceExit;
import opencodehx.effect.RuntimeMemo;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Process;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.project.InstanceRuntime;
import opencodehx.project.ProjectRuntime;
import opencodehx.smoke.SmokeCleanup.withCleanup;
import opencodehx.smoke.SmokeCleanup.withFailureCleanup;
import opencodehx.util.ProcessRuntime;

typedef SmokeSharedService = {
	final id:Int;
}

typedef SmokeRuntimeService = {
	final get:Void->Int;
}

typedef SmokeStateValue = {
	final directory:String;
	final n:Int;
}

typedef SmokeEnvEntry = {
	final key:String;
	final value:String;
}

typedef SmokeDeferredString = {
	final promise:Promise<String>;
	final resolve:String->Void;
	final reject:Error->Void;
}

class EffectSmoke {
	public static function run():Void {
		observabilityResource();
		runServiceMemoMap();
		instanceState();
		appRuntimeLogger();
	}

	@:async
	public static function runAsync():Promise<Void> {
		@:await runServiceAsync();
		@:await runner();
		@:await appRuntimeLoggerBridge();
		@:await crossSpawnSpawner();
	}

	static function observabilityResource():Void {
		final decoded = ObservabilityResource.resource({
			env: env([
				{
					key: "OTEL_RESOURCE_ATTRIBUTES",
					value: "service.namespace=anomalyco,team=platform%2Cobservability,label=hello%3Dworld,key%2Fname=value%20here"
				},
				{key: "OPENCODE_CLIENT", value: "cli"},
			]),
			processRole: "main",
			runID: "run-test",
			instanceID: "instance-test",
			installationChannel: "dev",
		});
		eq(decoded.serviceName, "opencode", "observability service name");
		eq(decoded.attributes.get("service.namespace"), "anomalyco", "observability namespace");
		eq(decoded.attributes.get("team"), "platform,observability", "observability comma decode");
		eq(decoded.attributes.get("label"), "hello=world", "observability equals decode");
		eq(decoded.attributes.get("key/name"), "value here", "observability slash and space decode");

		final invalid = ObservabilityResource.resource({
			env: env([
				{key: "OTEL_RESOURCE_ATTRIBUTES", value: "service.namespace=anomalyco,broken"},
				{key: "OPENCODE_CLIENT", value: "desktop"},
			]),
			processRole: "main",
			runID: "run-invalid",
			instanceID: "instance-invalid",
		});
		eq(invalid.attributes.exists("service.namespace"), false, "observability invalid entry drops env attributes");
		eq(invalid.attributes.exists("opencode.client"), true, "observability invalid keeps builtin attributes");

		final collision = ObservabilityResource.resource({
			env: env([
				{key: "OTEL_RESOURCE_ATTRIBUTES", value: "opencode.client=web,service.instance.id=override,service.namespace=anomalyco"},
				{key: "OPENCODE_CLIENT", value: "cli"},
			]),
			processRole: "main",
			runID: "run-collision",
			instanceID: "instance-collision",
		});
		eq(collision.attributes.get("opencode.client"), "cli", "observability builtin client wins");
		eq(collision.attributes.get("service.namespace"), "anomalyco", "observability env namespace kept");
		eq(collision.attributes.get("service.instance.id"), "instance-collision", "observability builtin instance wins");
	}

	static function runServiceMemoMap():Void {
		var initialized = 0;
		final shared = new RuntimeMemo<SmokeSharedService>();
		final sharedLayer = () -> shared.get(() -> {
			initialized += 1;
			return {id: initialized};
		});

		final one:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			final svc = sharedLayer();
			final get = () -> svc.id;
			return {get: get};
		});
		final two:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			final svc = sharedLayer();
			final get = () -> svc.id;
			return {get: get};
		});

		eq(one.run(svc -> svc.get()), 1, "run-service first runtime shared id");
		eq(two.run(svc -> svc.get()), 1, "run-service second runtime shared id");
		eq(initialized, 1, "run-service dependent layer initialized once");
	}

	@:async
	static function runServiceAsync():Promise<Void> {
		var initialized = 0;
		final runtime:RunServiceRuntime<SmokeRuntimeService> = RunServiceRuntime.make(() -> {
			initialized += 1;
			final id = initialized;
			final get = () -> id;
			return {get: get};
		});

		final first = @:await runtime.runPromise(svc -> Promise.resolve(svc.get()));
		final second = @:await runtime.runPromise(svc -> delay('async-${svc.get()}', 10));
		eq(first, 1, "run-service async first value");
		eq(second, "async-1", "run-service async reuses service");
		eq(initialized, 1, "run-service async initializes service once");

		eq(exitValue(@:await runtime.runPromiseExit(svc -> Promise.resolve(svc.get()))), "success:1", "run-service promise exit success");
		eq(exitValue(@:await runtime.runPromiseExit(_ -> Promise.reject(new Error("exit boom")))), "failed:exit boom", "run-service promise exit failure");

		final callbackSuccess = new Promise<Bool>((resolve, reject) -> {
			runtime.runCallback(svc -> Promise.resolve(svc.get()), result -> {
				switch (result) {
					case Succeeded(value):
						eq(value, 1, "run-service callback success value");
						resolve(true);
					case Failed(error):
						reject(error);
					case Interrupted:
						reject(new Error("callback should not interrupt"));
				}
			});
		});
		@:await callbackSuccess;

		final fork = runtime.runFork(svc -> delay('fork-${svc.get()}', 10));
		eq(exitValue(@:await fork.exit), "success:fork-1", "run-service fork success");

		final interrupted = runtime.runFork(_ -> delay("late", 25));
		interrupted.interrupt();
		eq(exitValue(@:await interrupted.exit), "interrupted", "run-service fork interrupt");
		@:await delay("settled", 30);
	}

	static function instanceState():Void {
		ProjectRuntime.reset();
		InstanceRuntime.reset();
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-instance-state-"));
		withCleanup(() -> withFailureCleanup(() -> {
			final one = directory(root, "one");
			final two = directory(root, "two");
			final projectOne = ProjectRuntime.fromDirectory(one).project;
			final projectTwo = ProjectRuntime.fromDirectory(two).project;
			var initialized = 0;
			final disposed:Array<String> = [];
			final state = new InstanceStateRuntime<SmokeStateValue>(context -> {
				initialized += 1;
				return {directory: context.directory, n: initialized};
			}, value -> disposed.push(value.directory));

			final contextOne = requireContext(InstanceRuntime.boot({directory: one, worktree: one, project: projectOne}), "instance state one boot");
			final a = state.get(contextOne);
			final b = state.get(contextOne);
			eq(a == b, true, "instance-state caches values per directory");
			eq(initialized, 1, "instance-state initializes cached directory once");

			final contextTwo = requireContext(InstanceRuntime.boot({directory: two, worktree: two, project: projectTwo}), "instance state two boot");
			final c = state.get(contextTwo);
			eq(a == c, false, "instance-state isolates directories");
			eq(initialized, 2, "instance-state initializes isolated directory");

			final reloaded = requireContext(InstanceRuntime.reload({directory: one, worktree: one, project: projectOne}), "instance state reload");
			final d = state.get(reloaded);
			eq(a == d, false, "instance-state invalidates on reload");
			eq(disposed.indexOf(a.directory) != -1, true, "instance-state disposes reloaded value");

			InstanceRuntime.disposeAll();
			eq(disposed.indexOf(c.directory) != -1, true, "instance-state disposes isolated value on disposeAll");
			eq(disposed.indexOf(d.directory) != -1, true, "instance-state disposes reloaded value on disposeAll");
			state.dispose();
		},
			() -> InstanceRuntime.reset()), () -> Fs.rmSync(root, {recursive: true, force: true}));
	}

	static function appRuntimeLogger():Void {
		final serviceRuntime = RunServiceRuntime.make(() -> AppRuntimeLoggerRuntime.make());
		final fromRuntime = serviceRuntime.run(runtime -> runtime.current());
		eq(fromRuntime.effectLogger, true, "app-runtime logger makeRuntime installs effect logger");
		eq(fromRuntime.defaultLogger, false, "app-runtime logger makeRuntime removes default logger");

		final appRuntime = AppRuntimeLoggerRuntime.make();
		final fromApp = appRuntime.current();
		eq(fromApp.effectLogger, true, "app-runtime logger installs effect logger");
		eq(fromApp.defaultLogger, false, "app-runtime logger removes default logger");
		eq(fromApp.size, 1, "app-runtime logger set size");

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-app-runtime-logger-"));
		final attached = AppRuntimeLoggerRuntime.make(root).current();
		eq(attached.directory, root, "app-runtime logger attaches instance directory");
		Fs.rmSync(root, {recursive: true, force: true});
	}

	@:async
	static function runner():Promise<Void> {
		final success = new RunnerRuntime<String>();
		eq(@:await success.ensureRunning(() -> Promise.resolve("hello")), "hello", "runner returns result");
		eq(stateName(success.state), "Idle", "runner returns to idle after success");
		eq(success.busy, false, "runner not busy after success");

		final failing = new RunnerRuntime<String>();
		var failureRejected = false;
		@:await failing.ensureRunning(() -> Promise.reject(new Error("boom"))).then(_ -> {
			throw "runner failure should reject";
			return null;
		}).catchError(_ -> {
			failureRejected = true;
			return null;
		});
		eq(failureRejected, true, "runner propagates failure");
		eq(stateName(failing.state), "Idle", "runner returns to idle after failure");

		var sharedCalls = 0;
		final shared = new RunnerRuntime<String>();
		final sharedA = shared.ensureRunning(() -> {
			sharedCalls++;
			return delay("shared", 20);
		});
		final sharedB = shared.ensureRunning(() -> {
			sharedCalls++;
			return Promise.resolve("ignored");
		});
		eq(@:await sharedA, "shared", "runner shared first caller");
		eq(@:await sharedB, "shared", "runner shared second caller");
		eq(sharedCalls, 1, "runner concurrent callers share one run");

		var sharedFailureCalls = 0;
		final sharedFailure = new RunnerRuntime<String>();
		final sharedFailureA = sharedFailure.ensureRunning(() -> {
			sharedFailureCalls++;
			return delayedFailure("shared-boom", 20);
		});
		final sharedFailureB = sharedFailure.ensureRunning(() -> {
			sharedFailureCalls++;
			return Promise.resolve("ignored");
		});
		eq(@:await rejected(sharedFailureA), true, "runner shared first caller receives failure");
		eq(@:await rejected(sharedFailureB), true, "runner shared second caller receives failure");
		eq(sharedFailureCalls, 1, "runner shared failure starts one run");

		final repeat = new RunnerRuntime<String>();
		eq(@:await repeat.ensureRunning(() -> Promise.resolve("first")), "first", "runner first run");
		eq(@:await repeat.ensureRunning(() -> Promise.resolve("second")), "second", "runner can run again");

		final ignored = new RunnerRuntime<String>();
		final ran:Array<String> = [];
		final ignoredA = ignored.ensureRunning(() -> {
			ran.push("first");
			return delay("first-result", 20);
		});
		final ignoredB = ignored.ensureRunning(() -> {
			ran.push("second");
			return Promise.resolve("second-result");
		});
		eq(@:await ignoredA, "first-result", "runner ignored first result");
		eq(@:await ignoredB, "first-result", "runner ignores replacement work");
		eq(ran.join(","), "first", "runner replacement work not started");

		final idleCancel = new RunnerRuntime<String>();
		@:await idleCancel.cancel();
		eq(idleCancel.busy, false, "runner idle cancel no-op");

		final rejected = new RunnerRuntime<String>();
		final rejectedA = rejected.ensureRunning(never);
		final rejectedB = rejected.ensureRunning(() -> Promise.resolve("queued"));
		@:await rejected.cancel();
		eq(@:await cancelled(rejectedA), true, "runner cancel rejects first caller");
		eq(@:await cancelled(rejectedB), true, "runner cancel rejects queued caller");

		final fallback = new RunnerRuntime<String>({onInterrupt: () -> Promise.resolve("fallback")});
		final fallbackA = fallback.ensureRunning(never);
		final fallbackB = fallback.ensureRunning(() -> Promise.resolve("queued"));
		@:await fallback.cancel();
		eq(@:await fallbackA, "fallback", "runner cancel fallback first caller");
		eq(@:await fallbackB, "fallback", "runner cancel fallback queued caller");

		final restart = new RunnerRuntime<String>();
		final restartPending = restart.ensureRunning(never);
		@:await restart.cancel();
		@:await restartPending.catchError(_ -> null);
		eq(@:await restart.ensureRunning(() -> Promise.resolve("after-cancel")), "after-cancel", "runner starts after cancel");

		final interrupt = deferredString();
		final replacementDone = deferredString();
		final interleaved = new RunnerRuntime<String>({onInterrupt: () -> interrupt.promise});
		final interrupted = interleaved.ensureRunning(never);
		final stopping = interleaved.cancel();
		eq(interleaved.busy, false, "runner cancel releases busy before interrupt fallback settles");
		final replacement = interleaved.ensureRunning(() -> replacementDone.promise);
		eq(interleaved.busy, true, "runner replacement starts during pending interrupt fallback");
		interrupt.resolve("fallback");
		eq(@:await stopping, true, "runner pending interrupt fallback completes");
		eq(@:await interrupted, "fallback", "runner pending interrupt fallback settles cancelled caller");
		eq(interleaved.busy, true, "runner replacement stays active after interrupt fallback");
		replacementDone.resolve("replacement");
		eq(@:await replacement, "replacement", "runner replacement completes after interrupt fallback");
		eq(interleaved.busy, false, "runner returns idle after interleaved replacement");
	}

	static function env(values:Array<SmokeEnvEntry>):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		for (entry in values)
			out.set(entry.key, entry.value);
		return out;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}

	static function directory(root:String, name:String):String {
		final path = NodePath.join(root, name);
		Fs.mkdirSync(path, {recursive: true});
		return path;
	}

	static function requireContext<T>(context:Null<T>, label:String):T {
		if (context == null)
			throw '${label}: expected context';
		return context;
	}

	static function stateName(state:RunnerState):String {
		return switch state {
			case Idle: "Idle";
			case Running: "Running";
		}
	}

	static function exitValue<T>(result:RunServiceExit<T>):String {
		return switch (result) {
			case Succeeded(value): 'success:${value}';
			case Failed(error): 'failed:${error.message}';
			case Interrupted: "interrupted";
		}
	}

	static function delay(value:String, ms:Int):Promise<String> {
		return new Promise<String>((resolve, _) -> {
			WebTimers.setTimeout(() -> resolve(value), ms);
		});
	}

	static function delayedFailure(message:String, ms:Int):Promise<String> {
		return new Promise<String>((_, reject) -> {
			WebTimers.setTimeout(() -> reject(new Error(message)), ms);
		});
	}

	static function never():Promise<String> {
		return new Promise<String>((_, _) -> {});
	}

	static function deferredString():SmokeDeferredString {
		var resolve:String->Void = _ -> {};
		var reject:Error->Void = _ -> {};
		final promise = new Promise<String>((done, fail) -> {
			resolve = done;
			reject = fail;
		});
		return {promise: promise, resolve: resolve, reject: reject};
	}

	@:async
	static function appRuntimeLoggerBridge():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-app-runtime-bridge-"));
		final runtime = AppRuntimeLoggerRuntime.make(root);
		final result = @:await runtime.runPromise(context -> {
			final bridge = AppRuntimeLoggerRuntime.bridgeFor(context);
			return Promise.resolve(true).then(_ -> bridge.promise(AppRuntimeLoggerRuntime.snapshot));
		});
		eq(result.directory, root, "app-runtime bridge preserves instance directory");
		eq(result.effectLogger, true, "app-runtime bridge preserves effect logger");
		eq(result.defaultLogger, false, "app-runtime bridge preserves logger replacement");
		Fs.rmSync(root, {recursive: true, force: true});
	}

	@:async
	static function crossSpawnSpawner():Promise<Void> {
		final out = @:await ProcessRuntime.run(node('process.stdout.write("ok")'));
		eq(out.stdout, "ok", "cross-spawn captures stdout");

		final lines = ProcessRuntime.spawn(node('console.log("line1"); console.log("line2"); console.log("line3")'));
		eq(@:await lines.exited, 0, "cross-spawn multiple lines exit");
		eq(StringTools.trim(lines.stdoutText()), "line1\nline2\nline3", "cross-spawn captures multiple lines");

		final zero = ProcessRuntime.spawn(node("process.exit(0)"));
		eq(@:await zero.exited, 0, "cross-spawn exit code zero");

		final nonzero = ProcessRuntime.spawn(node("process.exit(42)"));
		eq(@:await nonzero.exited, 42, "cross-spawn nonzero exit code");

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cross-spawn-"));
		final cwd = @:await ProcessRuntime.run(node("process.stdout.write(process.cwd())"), {cwd: root});
		eq(NodePath.normalize(Fs.realpathSync(cwd.stdout)), NodePath.normalize(Fs.realpathSync(root)), "cross-spawn cwd option");

		final badCwd = @:await ProcessRuntime.spawn(["echo", "test"], {cwd: NodePath.join(root, "missing")}).exited.then(_ -> false).catchError(_ -> true);
		eq(badCwd, true, "cross-spawn invalid cwd fails");

		final envOut = @:await ProcessRuntime.run(node('process.stdout.write((process.env.VAR1 ?? "") + "-" + (process.env.VAR2 ?? "") + "-" + (process.env.VAR3 ?? ""))'),
			{
			env: env([{key: "VAR1", value: "one"}, {key: "VAR2", value: "two"}, {key: "VAR3", value: "three"}])
		});
		eq(envOut.stdout, "one-two-three", "cross-spawn passes env");

		final err = ProcessRuntime.spawn(node('process.stderr.write("error message")'));
		eq(@:await err.exited, 0, "cross-spawn stderr exit");
		eq(err.stderrText(), "error message", "cross-spawn captures stderr");
		eq(err.allText(), "error message", "cross-spawn all captures stderr");

		final both = ProcessRuntime.spawn(node('process.stdout.write("stdout\\n"); process.stderr.write("stderr\\n")'));
		eq(@:await both.exited, 0, "cross-spawn combined exit");
		eq(both.allText().indexOf("stdout") != -1, true, "cross-spawn all includes stdout");
		eq(both.allText().indexOf("stderr") != -1, true, "cross-spawn all includes stderr");

		final stdin = ProcessRuntime.spawn(node('process.stdin.setEncoding("utf8"); let out = ""; process.stdin.on("data", chunk => out += chunk); process.stdin.on("end", () => process.stdout.write(out))'),
			{
				input: "a b c",
			});
		eq(@:await stdin.exited, 0, "cross-spawn stdin exit");
		eq(stdin.stdoutText(), "a b c", "cross-spawn stdin input");

		final running = ProcessRuntime.spawn(node("setInterval(() => {}, 10_000)"));
		eq(running.isRunning(), true, "cross-spawn isRunning before kill");
		final killed = @:await running.kill("SIGTERM", 100);
		eq(killed != 0, true, "cross-spawn kill exit code");
		eq(running.isRunning(), false, "cross-spawn isRunning after exit");

		final missing = @:await ProcessRuntime.spawn([NodePath.join(root, "missing-command")]).exited.then(_ -> false).catchError(_ -> true);
		eq(missing, true, "cross-spawn missing command fails");

		if (NodeProcess.platform() == "win32") {
			final shellOut = @:await ProcessRuntime.run(["set", "OPENCODE_TEST_SHELL"], {shell: true, env: env([{key: "OPENCODE_TEST_SHELL", value: "ok"}])});
			eq(shellOut.stdout.indexOf("OPENCODE_TEST_SHELL=ok") != -1, true, "cross-spawn windows shell");

			final dir = NodePath.join(root, "with space");
			final file = NodePath.join(dir, "echo cmd.cmd");
			Fs.mkdirSync(dir, {recursive: true});
			Fs.writeFileSync(file, "@echo off\r\nif %~1==--stdio exit /b 0\r\nexit /b 7\r\n");
			eq(@:await ProcessRuntime.spawn([file, "--stdio"]).exited, 0, "cross-spawn windows cmd with spaces");
		}

		Fs.rmSync(root, {recursive: true, force: true});
	}

	static function node(code:String):Array<String> {
		return [Process.argv[0], "-e", code];
	}

	static function cancelled(promise:Promise<String>):Promise<Bool> {
		return promise.then(_ -> false).catchError(error -> Std.isOfType(error, RunnerCancelledError));
	}

	static function rejected(promise:Promise<String>):Promise<Bool> {
		return promise.then(_ -> false).catchError(_ -> true);
	}
}
