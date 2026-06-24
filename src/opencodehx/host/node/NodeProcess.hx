package opencodehx.host.node;

import genes.js.Async.await;
import haxe.DynamicAccess;
import js.lib.Error;
import js.lib.Promise;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.ChildProcessHandle;
import opencodehx.externs.node.ChildProcess.SpawnSyncOptions;
import opencodehx.externs.node.ChildProcess.SpawnSyncResult;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Process;
import opencodehx.externs.web.WebStreams.WebTimers;
import opencodehx.host.node.NodePath;
import opencodehx.util.Which;

using StringTools;

typedef KillTreeOptions = {
	@:optional final exited:Void->Bool;
}

typedef ShellRun = {
	final command:String;
	final cwd:String;
	final env:DynamicAccess<String>;
	final timeout:Int;
	final maxBuffer:Int;
}

typedef ShellSelection = {
	final platform:String;
	@:optional final shell:Null<String>;
	@:optional final comspec:Null<String>;
	@:optional final gitBash:Null<String>;
	@:optional final pwsh:Null<String>;
	@:optional final powershell:Null<String>;
	@:optional final bash:Null<String>;
}

class NodeProcess {
	static inline final SIGKILL_TIMEOUT_MS = 200;
	static final BLACKLIST = ["fish", "nu"];
	static final LOGIN = ["bash", "dash", "fish", "ksh", "sh", "zsh"];
	static final POSIX = ["bash", "dash", "ksh", "sh", "zsh"];

	public static function env():DynamicAccess<String> {
		// process.env is a Node host boundary. We copy it only to pass back into
		// spawnSync; application code should normalize specific variables before use.
		final out = new DynamicAccess<String>();
		for (key in Process.env.keys()) {
			final value = Process.env.get(key);
			if (value != null)
				out.set(key, value);
		}
		return out;
	}

	public static function envValue(key:String):Null<String> {
		if (Process.platform != "win32")
			return Process.env.get(key);
		final lower = key.toLowerCase();
		for (name in Process.env.keys()) {
			if (name.toLowerCase() == lower)
				return Process.env.get(name);
		}
		return null;
	}

	public static function setEnv(key:String, value:String):Void {
		// Mutating process.env is a Node host boundary used by CLI smokes and
		// config bootstrap. Keep it centralized so app logic receives typed env maps.
		Process.env.set(key, value);
	}

	public static function unsetEnv(key:String):Void {
		// See setEnv: deleting a process env key is host mutation and should stay
		// behind this helper rather than scattered across application modules.
		Process.env.remove(key);
	}

	public static function cwd():String {
		// process.cwd() is the Node host boundary for CLI directory defaults.
		// Keep the process read here so callers do not depend on Node directly.
		return Process.cwd();
	}

	public static function chdir(path:String):Void {
		// process.chdir() is a CLI host effect; app code should pass resolved
		// directories explicitly once it crosses this boundary.
		Process.chdir(path);
	}

	public static function platform():String {
		return Process.platform;
	}

	public static function shell():String {
		return acceptableShell();
	}

	public static function preferredShell():String {
		return selectPreferred(runtimeShellSelection());
	}

	public static function acceptableShell():String {
		return selectAcceptable(runtimeShellSelection());
	}

	public static function selectPreferred(input:ShellSelection):String {
		return select(input, false);
	}

	public static function selectAcceptable(input:ShellSelection):String {
		return select(input, true);
	}

	public static function shellName(file:String):String {
		return shellNameForPlatform(file, platform());
	}

	public static function shellNameForPlatform(file:String, platform:String):String {
		final path = platform == "win32" ? windowsPathForPlatform(file, platform) : file;
		var name = basenameForPlatform(path, platform).toLowerCase();
		if (platform == "win32") {
			final dot = name.lastIndexOf(".");
			if (dot > 0)
				name = name.substr(0, dot);
		}
		return name;
	}

	public static function isPowerShell(file:String):Bool {
		return isPowerShellForPlatform(file, platform());
	}

	public static function isPowerShellForPlatform(file:String, platform:String):Bool {
		final name = shellNameForPlatform(file, platform);
		return name == "pwsh" || name == "powershell";
	}

	public static function isLoginShell(file:String):Bool {
		return isLoginShellForPlatform(file, platform());
	}

	public static function isLoginShellForPlatform(file:String, platform:String):Bool {
		final name = shellNameForPlatform(file, platform);
		return LOGIN.indexOf(name) != -1;
	}

	public static function isPosixShell(file:String):Bool {
		return isPosixShellForPlatform(file, platform());
	}

	public static function isPosixShellForPlatform(file:String, platform:String):Bool {
		final name = shellNameForPlatform(file, platform);
		return POSIX.indexOf(name) != -1;
	}

	public static function windowsPath(file:String):String {
		return windowsPathForPlatform(file, platform());
	}

	public static function windowsPathForPlatform(file:String, platform:String):String {
		if (platform != "win32")
			return file;
		var out = convertDrivePath(file, "^/([A-Za-z]):(?:[\\\\/]|$)");
		out = convertDrivePath(out, "^/([A-Za-z])(?:/|$)");
		out = convertDrivePath(out, "^/cygdrive/([A-Za-z])(?:/|$)");
		out = convertDrivePath(out, "^/mnt/([A-Za-z])(?:/|$)");
		return out;
	}

	public static function gitBash():Null<String> {
		if (platform() != "win32")
			return null;
		final configured = envValue("OPENCODE_GIT_BASH_PATH");
		if (configured != null && configured != "")
			return configured;
		final git = Which.which("git");
		if (git == null)
			return null;
		final file = NodePath.join(git, "../../bin/bash.exe");
		return existsFile(file) ? file : null;
	}

	public static function runShell(input:ShellRun):SpawnSyncResult {
		final shellPath = acceptableShell();
		if (platform() == "win32" && isPowerShell(shellPath)) {
			final options:SpawnSyncOptions = {
				cwd: input.cwd,
				encoding: "utf8",
				env: input.env,
				timeout: input.timeout,
				killSignal: "SIGTERM",
				windowsHide: true,
				maxBuffer: input.maxBuffer,
			};
			return ChildProcess.spawnSync(shellPath, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", input.command], options);
		}
		final options:SpawnSyncOptions = {
			cwd: input.cwd,
			encoding: "utf8",
			env: input.env,
			shell: shellPath,
			timeout: input.timeout,
			killSignal: "SIGTERM",
			windowsHide: true,
			maxBuffer: input.maxBuffer,
		};
		return ChildProcess.spawnSync(input.command, [], options);
	}

	@:async
	public static function killTree(proc:ChildProcessHandle, ?opts:KillTreeOptions):Promise<Void> {
		final pid = proc.pid;
		if (pid == null || exited(opts))
			return;

		if (platform() == "win32") {
			@:await killTreeWindows(pid);
			return;
		}

		try {
			Process.kill(-pid, "SIGTERM");
			@:await sleep(SIGKILL_TIMEOUT_MS);
			if (!exited(opts))
				Process.kill(-pid, "SIGKILL");
		} catch (_:Error) {
			proc.kill("SIGTERM");
			@:await sleep(SIGKILL_TIMEOUT_MS);
			if (!exited(opts))
				proc.kill("SIGKILL");
		}
	}

	static function runtimeShellSelection():ShellSelection {
		return {
			platform: platform(),
			shell: envValue("SHELL"),
			comspec: envValue("COMSPEC"),
			gitBash: gitBash(),
			pwsh: firstWhich(["pwsh.exe", "pwsh"]),
			powershell: firstWhich(["powershell.exe", "powershell"]),
			bash: Which.which("bash"),
		};
	}

	static function exited(?opts:KillTreeOptions):Bool {
		return opts != null && opts.exited != null && opts.exited();
	}

	static function killTreeWindows(pid:Int):Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			// taskkill owns Windows descendant traversal. Errors are treated as
			// successful teardown, matching upstream's best-effort behavior.
			final resolveVoid:Void->Void = cast resolve;
			final killer = ChildProcess.spawn("taskkill", ["/pid", Std.string(pid), "/f", "/t"], {
				stdio: "ignore",
				windowsHide: true,
			});
			var done = false;
			final finish = (_:Dynamic) -> {
				if (!done) {
					done = true;
					resolveVoid();
				}
			};
			killer.once("exit", finish);
			killer.once("error", finish);
		});
	}

	static function sleep(ms:Int):Promise<Void> {
		return new Promise<Void>((resolve, _) -> {
			// Promise<Void> needs a zero-arg resolver shape in Haxe, while JS
			// promises resolve with undefined.
			final resolveVoid:Void->Void = cast resolve;
			WebTimers.setTimeout(resolveVoid, ms);
		});
	}

	static function select(input:ShellSelection, acceptable:Bool):String {
		final file = input.shell;
		if (file != null && file != "" && (!acceptable || BLACKLIST.indexOf(shellNameForPlatform(file, input.platform)) == -1))
			return full(file, input);
		if (input.platform == "win32") {
			final shell = pickPowerShell(input);
			if (shell != null)
				return shell;
		}
		return fallback(input);
	}

	static function full(file:String, input:ShellSelection):String {
		if (input.platform != "win32")
			return file;
		final shell = windowsPathForPlatform(file, input.platform);
		if (dirnameForPlatform(shell, input.platform) != ".") {
			if (shell.startsWith("/") && shellNameForPlatform(shell, input.platform) == "bash" && input.gitBash != null)
				return input.gitBash;
			return shell;
		}
		final found = whichFromSelection(shell, input);
		return found == null ? shell : found;
	}

	static function pickPowerShell(input:ShellSelection):Null<String> {
		if (input.pwsh != null && input.pwsh != "")
			return input.pwsh;
		if (input.powershell != null && input.powershell != "")
			return input.powershell;
		return null;
	}

	static function fallback(input:ShellSelection):String {
		if (input.platform == "win32") {
			if (input.gitBash != null && input.gitBash != "")
				return input.gitBash;
			if (input.comspec != null && input.comspec != "")
				return input.comspec;
			return "cmd.exe";
		}
		if (input.platform == "darwin")
			return "/bin/zsh";
		if (input.bash != null && input.bash != "")
			return input.bash;
		return "/bin/sh";
	}

	static function whichFromSelection(file:String, input:ShellSelection):Null<String> {
		return switch shellNameForPlatform(file, input.platform) {
			case "pwsh": input.pwsh;
			case "powershell": input.powershell;
			case "bash": input.bash != null ? input.bash : input.gitBash;
			case "cmd": input.comspec;
			case _: null;
		}
	}

	static function firstWhich(names:Array<String>):Null<String> {
		for (name in names) {
			final found = Which.which(name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function existsFile(file:String):Bool {
		try {
			return Fs.existsSync(file) && Fs.statSync(file).isFile();
		} catch (_:Error) {
			return false;
		}
	}

	static function basenameForPlatform(file:String, platform:String):String {
		var trimmed = file;
		while (trimmed.length > 1 && (trimmed.endsWith("/") || trimmed.endsWith("\\")))
			trimmed = trimmed.substr(0, trimmed.length - 1);
		final slash = trimmed.lastIndexOf("/");
		final backslash = trimmed.lastIndexOf("\\");
		final index = slash > backslash ? slash : backslash;
		return index == -1 ? trimmed : trimmed.substr(index + 1);
	}

	static function dirnameForPlatform(file:String, platform:String):String {
		var trimmed = file;
		while (trimmed.length > 1 && (trimmed.endsWith("/") || trimmed.endsWith("\\")))
			trimmed = trimmed.substr(0, trimmed.length - 1);
		final slash = trimmed.lastIndexOf("/");
		final backslash = trimmed.lastIndexOf("\\");
		final index = slash > backslash ? slash : backslash;
		if (index == -1)
			return ".";
		if (index == 0)
			return trimmed.substr(0, 1);
		return trimmed.substr(0, index);
	}

	static function convertDrivePath(file:String, pattern:String):String {
		return switch pattern {
			case "^/([A-Za-z]):(?:[\\\\/]|$)":
				convertDrivePrefix(file, "/", true);
			case "^/([A-Za-z])(?:/|$)":
				convertDrivePrefix(file, "/", false);
			case "^/cygdrive/([A-Za-z])(?:/|$)":
				convertDrivePrefix(file, "/cygdrive/", false);
			case "^/mnt/([A-Za-z])(?:/|$)":
				convertDrivePrefix(file, "/mnt/", false);
			case _:
				file;
		}
	}

	static function convertDrivePrefix(file:String, prefix:String, expectsColon:Bool):String {
		if (!file.startsWith(prefix))
			return file;
		final driveIndex = prefix.length;
		if (driveIndex >= file.length)
			return file;
		final drive = file.charAt(driveIndex);
		final upperDrive = drive.toUpperCase();
		if (upperDrive < "A" || upperDrive > "Z")
			return file;
		var restIndex = driveIndex + 1;
		if (expectsColon) {
			if (restIndex >= file.length || file.charAt(restIndex) != ":")
				return file;
			restIndex += 1;
		}
		if (restIndex < file.length) {
			final separator = file.charAt(restIndex);
			if (separator != "/" && separator != "\\")
				return file;
			restIndex += 1;
		}
		return upperDrive + ":/" + file.substr(restIndex);
	}
}
