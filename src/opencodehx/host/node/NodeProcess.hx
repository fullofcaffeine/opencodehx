package opencodehx.host.node;

import js.Syntax;
import js.lib.Error;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.SpawnSyncOptions;
import opencodehx.externs.node.ChildProcess.SpawnSyncResult;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;

using StringTools;

typedef ShellRun = {
	final command:String;
	final cwd:String;
	final env:haxe.DynamicAccess<String>;
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
	static final BLACKLIST = ["fish", "nu"];
	static final LOGIN = ["bash", "dash", "fish", "ksh", "sh", "zsh"];
	static final POSIX = ["bash", "dash", "ksh", "sh", "zsh"];

	public static function env():haxe.DynamicAccess<String> {
		// process.env is a Node host boundary. We copy it only to pass back into
		// spawnSync; application code should normalize specific variables before use.
		return Syntax.code("({ ...process.env })");
	}

	public static function envValue(key:String):Null<String> {
		return Syntax.code("(() => {
			if (process.platform !== 'win32') return process.env[{0}] ?? null;
			const name = Object.keys(process.env).find((item) => item.toLowerCase() === {0}.toLowerCase());
			return name ? process.env[name] ?? null : null;
		})()", key);
	}

	public static function platform():String {
		return Syntax.code("process.platform");
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
		final name = shellName(file);
		return name == "pwsh" || name == "powershell";
	}

	public static function isLoginShell(file:String):Bool {
		final name = shellName(file);
		return LOGIN.indexOf(name) != -1;
	}

	public static function isPosixShell(file:String):Bool {
		final name = shellName(file);
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
		final git = which("git");
		if (git == null)
			return null;
		final file = NodePath.join(git, "../../bin/bash.exe");
		return existsFile(file) ? file : null;
	}

	public static function runShell(input:ShellRun):SpawnSyncResult {
		final shellPath = acceptableShell();
		if (platform() == "win32" && isPowerShell(shellPath)) {
			final options:SpawnSyncOptions = Syntax.code("({ cwd: {0}, encoding: 'utf8', env: {1}, timeout: {2}, killSignal: 'SIGTERM', windowsHide: true, maxBuffer: {3} })",
				input.cwd, input.env,
				input.timeout, input.maxBuffer);
			return ChildProcess.spawnSync(shellPath, ["-NoLogo", "-NoProfile", "-NonInteractive", "-Command", input.command], options);
		}
		// Build the exact Node options object so TypeScript sees the native
		// SpawnSyncOptionsWithStringEncoding shape instead of Haxe optional-null fields.
		final options:SpawnSyncOptions = Syntax.code("({ cwd: {0}, encoding: 'utf8', env: {1}, shell: {2}, timeout: {3}, killSignal: 'SIGTERM', windowsHide: true, maxBuffer: {4} })",
			input.cwd,
			input.env, shellPath, input.timeout, input.maxBuffer);
		return ChildProcess.spawnSync(input.command, [], options);
	}

	static function runtimeShellSelection():ShellSelection {
		return {
			platform: platform(),
			shell: envValue("SHELL"),
			comspec: envValue("COMSPEC"),
			gitBash: gitBash(),
			pwsh: firstWhich(["pwsh.exe", "pwsh"]),
			powershell: firstWhich(["powershell.exe", "powershell"]),
			bash: which("bash"),
		};
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
			final found = which(name);
			if (found != null)
				return found;
		}
		return null;
	}

	static function which(command:String):Null<String> {
		final pathValue = envValue("PATH");
		if (pathValue == null || pathValue == "")
			return null;
		final isWin = platform() == "win32";
		final separator = isWin ? ";" : ":";
		final extensions = command.indexOf(".") == -1 && isWin ? pathExtensions() : [""];
		for (dir in pathValue.split(separator)) {
			if (dir == "")
				continue;
			for (ext in extensions) {
				final candidate = NodePath.join(dir, command + ext);
				if (existsFile(candidate))
					return candidate;
			}
		}
		return null;
	}

	static function pathExtensions():Array<String> {
		final raw = envValue("PATHEXT");
		if (raw == null || raw == "")
			return [".EXE", ".CMD", ".BAT", ".COM"];
		final out:Array<String> = [];
		for (ext in raw.split(";")) {
			if (ext != "")
				out.push(ext);
		}
		return out.length == 0 ? [".EXE", ".CMD", ".BAT", ".COM"] : out;
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
		return Syntax.code("{0}.replace(new RegExp({1}), (_match: string, drive: string) => `${drive.toUpperCase()}:/`)", file, pattern);
	}
}
