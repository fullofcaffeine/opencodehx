package opencodehx.util;

import haxe.DynamicAccess;
import haxe.extern.EitherType;
import js.html.AbortSignal;
import js.lib.Error;
import js.lib.Promise;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.ChildProcessHandle;
import opencodehx.externs.node.ChildProcess.NodeReadableStream;
import opencodehx.externs.node.ChildProcess.NodeSignal;
import opencodehx.externs.node.ChildProcess.SpawnOptions;
import opencodehx.externs.node.Process;
import opencodehx.externs.web.WebStreams.WebTimerHandle;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.host.node.NodeProcess;

typedef ProcessRunOptions = {
	@:optional final cwd:String;
	@:optional final env:DynamicAccess<String>;
	@:optional final shell:EitherType<Bool, String>;
	@:optional final abort:AbortSignal;
	@:optional final kill:NodeSignal;
	@:optional final timeout:Int;
	@:optional final input:String;
	@:optional final nothrow:Bool;
}

typedef ProcessSpawnOptions = {
	@:optional final cwd:String;
	@:optional final env:DynamicAccess<String>;
	@:optional final shell:EitherType<Bool, String>;
	@:optional final abort:AbortSignal;
	@:optional final kill:NodeSignal;
	@:optional final timeout:Int;
	@:optional final input:String;
	@:optional final stdin:String;
	@:optional final stdout:String;
	@:optional final stderr:String;
}

typedef ProcessResult = {
	final code:Int;
	final stdout:String;
	final stderr:String;
}

class ProcessRunFailedError extends Error {
	public final cmd:Array<String>;
	public final code:Int;
	public final stdout:String;
	public final stderr:String;

	public function new(cmd:Array<String>, code:Int, stdout:String, stderr:String) {
		final text = StringTools.trim(stderr);
		super(text == "" ? 'Command failed with code ${code}: ${cmd.join(" ")}' : 'Command failed with code ${code}: ${cmd.join(" ")}\n${text}');
		this.name = "ProcessRunFailedError";
		this.cmd = cmd.copy();
		this.code = code;
		this.stdout = stdout;
		this.stderr = stderr;
	}
}

class ProcessRuntime {
	public static final RunFailedError = ProcessRunFailedError;

	public static function run(cmd:Array<String>, ?opts:ProcessRunOptions):Promise<ProcessResult> {
		return new Promise<ProcessResult>((resolve, reject) -> {
			final child = spawn(cmd, {
				cwd: opts == null ? null : opts.cwd,
				env: opts == null ? null : opts.env,
				shell: opts == null ? null : opts.shell,
				abort: opts == null ? null : opts.abort,
				kill: opts == null ? null : opts.kill,
				timeout: opts == null ? null : opts.timeout,
				input: opts == null ? null : opts.input,
				stdout: "pipe",
				stderr: "pipe",
			});
			child.exited.then(code -> {
				final out:ProcessResult = {code: code, stdout: child.stdoutText(), stderr: child.stderrText()};
				if (code == 0 || (opts != null && opts.nothrow == true))
					resolve(out);
				else
					reject(new ProcessRunFailedError(cmd, code, out.stdout, out.stderr));
				return null;
			}).catchError(error -> {
				if (opts != null && opts.nothrow == true) {
					final out:ProcessResult = {code: 1, stdout: "", stderr: errorMessage(error)};
					resolve(out);
				} else
					reject(error);
				return null;
			});
		});
	}

	public static function spawn(cmd:Array<String>, ?opts:ProcessSpawnOptions):ProcessChild {
		if (cmd.length == 0)
			throw new Error("Command is required");
		final abort = opts == null ? null : opts.abort;
		if (abort != null && abort.aborted)
			throw new Error("This operation was aborted");

		final options = spawnOptions(cmd[0], opts);
		final handle = ChildProcess.spawn(cmd[0], cmd.slice(1), options);
		return new ProcessChild(cmd, handle, abort, opts == null ? null : opts.kill, opts == null ? null : opts.timeout, opts == null ? null : opts.input);
	}

	static function mergeEnv(overrides:Null<DynamicAccess<String>>):Null<DynamicAccess<String>> {
		if (overrides == null)
			return null;
		final env = NodeProcess.env();
		for (key in overrides.keys()) {
			final value = overrides.get(key);
			if (value != null)
				env.set(key, value);
		}
		return env;
	}

	static function spawnOptions(command:String, opts:Null<ProcessSpawnOptions>):SpawnOptions {
		final options:Dynamic = {
			stdio: "pipe",
			windowsHide: Process.platform == "win32",
		};
		if (opts != null) {
			if (opts.cwd != null)
				Reflect.setField(options, "cwd", opts.cwd);
			final env = mergeEnv(opts.env);
			if (env != null)
				Reflect.setField(options, "env", env);
			final shell = shellOption(command, opts.shell);
			if (shell != null)
				Reflect.setField(options, "shell", shell);
		}
		// Optional Node spawn properties must be absent, not present as null.
		// Build the host options dynamically here, then return to the typed seam.
		return cast options;
	}

	static function shellOption(command:String, shell:Null<EitherType<Bool, String>>):Null<EitherType<Bool, String>> {
		if (shell != null)
			return shell;
		if (Process.platform == "win32") {
			final lower = command.toLowerCase();
			if (StringTools.endsWith(lower, ".cmd") || StringTools.endsWith(lower, ".bat"))
				return true;
		}
		return null;
	}

	static function errorMessage(error:Dynamic):String {
		final message = Reflect.field(error, "message");
		return message == null ? Std.string(error) : Std.string(message);
	}
}

class ProcessChild {
	final handle:ChildProcessHandle;
	final killSignal:NodeSignal;
	final timeoutMs:Int;
	var stdoutBuffer:String = "";
	var stderrBuffer:String = "";
	var allBuffer:String = "";
	var closed = false;
	var timer:Null<WebTimerHandle> = null;

	public final exited:Promise<Int>;

	public function new(cmd:Array<String>, handle:ChildProcessHandle, abort:Null<AbortSignal>, kill:Null<NodeSignal>, timeout:Null<Int>, input:Null<String>) {
		this.handle = handle;
		killSignal = kill == null ? "SIGTERM" : kill;
		timeoutMs = timeout == null ? 5000 : timeout;
		attachOutput(handle.stdout, chunk -> {
			stdoutBuffer += chunk;
			allBuffer += chunk;
		});
		attachOutput(handle.stderr, chunk -> {
			stderrBuffer += chunk;
			allBuffer += chunk;
		});

		exited = new Promise<Int>((resolve, reject) -> {
			final cleanup = () -> {
				if (abort != null)
					abort.removeEventListener("abort", abortProcess);
				if (timer != null)
					WebTimers.clearTimeout(timer);
			};
			handle.once("exit", code -> {
				cleanup();
				resolve(code == null ? 1 : code);
			});
			handle.once("error", error -> {
				cleanup();
				reject(error);
			});
		});
		exited.catchError(_ -> null);

		if (abort != null) {
			abort.addEventListener("abort", abortProcess);
			if (abort.aborted)
				abortProcess();
		}

		if (input != null)
			writeAndEnd(input);
	}

	public function stdoutText():String {
		return stdoutBuffer;
	}

	public function stderrText():String {
		return stderrBuffer;
	}

	public function allText():String {
		return allBuffer;
	}

	public function pid():Null<Int> {
		return handle.pid;
	}

	public function isRunning():Bool {
		return handle.exitCode == null && handle.signalCode == null;
	}

	public function kill(?signal:NodeSignal, ?forceKillAfter:Int):Promise<Int> {
		if (!isRunning())
			return exited;
		closed = true;
		handle.kill(signal == null ? killSignal : signal);
		final delay = forceKillAfter == null ? timeoutMs : forceKillAfter;
		if (delay > 0) {
			timer = WebTimers.setTimeout(() -> {
				if (isRunning())
					handle.kill("SIGKILL");
			}, delay);
		}
		return exited;
	}

	public function writeStdin(value:String):Void {
		if (handle.stdin != null)
			handle.stdin.write(value);
	}

	public function endStdin():Void {
		if (handle.stdin != null)
			handle.stdin.end();
	}

	public function writeAndEnd(value:String):Void {
		writeStdin(value);
		endStdin();
	}

	function abortProcess(?_:Dynamic):Void {
		if (closed || handle.exitCode != null || handle.signalCode != null)
			return;
		closed = true;
		handle.kill(killSignal);
		if (timeoutMs <= 0)
			return;
		timer = WebTimers.setTimeout(() -> {
			if (isRunning())
				handle.kill("SIGKILL");
		}, timeoutMs);
	}

	static function attachOutput(stream:Null<NodeReadableStream>, append:String->Void):Void {
		if (stream == null)
			return;
		stream.setEncoding("utf8");
		stream.on("data", chunk -> append(chunk));
	}
}
