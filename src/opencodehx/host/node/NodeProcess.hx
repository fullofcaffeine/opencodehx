package opencodehx.host.node;

import js.Syntax;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.SpawnSyncOptions;
import opencodehx.externs.node.ChildProcess.SpawnSyncResult;
import opencodehx.host.node.NodePath;

using StringTools;

typedef ShellRun = {
	final command:String;
	final cwd:String;
	final env:haxe.DynamicAccess<String>;
	final timeout:Int;
	final maxBuffer:Int;
}

class NodeProcess {
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
		return platform() == "win32" ? "cmd.exe" : "/bin/sh";
	}

	public static function preferredShell():String {
		if (platform() == "win32") {
			final comspec:String = Syntax.code("process.env.COMSPEC || 'cmd.exe'");
			return comspec;
		}
		final bash:String = Syntax.code("process.env.SHELL || '/bin/bash'");
		return bash == "" ? "/bin/sh" : bash;
	}

	public static function shellName(file:String):String {
		final name = NodePath.basename(file).toLowerCase();
		return name.endsWith(".exe") ? name.substr(0, name.length - 4) : name;
	}

	public static function isPowerShell(file:String):Bool {
		final name = shellName(file);
		return name == "pwsh" || name == "powershell";
	}

	public static function isLoginShell(file:String):Bool {
		final name = shellName(file);
		return ["bash", "dash", "fish", "ksh", "sh", "zsh"].indexOf(name) != -1;
	}

	public static function runShell(input:ShellRun):SpawnSyncResult {
		final shellPath = shell();
		// Build the exact Node options object so TypeScript sees the native
		// SpawnSyncOptionsWithStringEncoding shape instead of Haxe optional-null fields.
		final options:SpawnSyncOptions = Syntax.code("({ cwd: {0}, encoding: 'utf8', env: {1}, shell: {2}, timeout: {3}, killSignal: 'SIGTERM', windowsHide: true, maxBuffer: {4} })",
			input.cwd,
			input.env, shellPath, input.timeout, input.maxBuffer);
		return ChildProcess.spawnSync(input.command, [], options);
	}
}
