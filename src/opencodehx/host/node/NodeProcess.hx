package opencodehx.host.node;

import js.Syntax;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.SpawnSyncOptions;
import opencodehx.externs.node.ChildProcess.SpawnSyncResult;

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

	public static function platform():String {
		return Syntax.code("process.platform");
	}

	public static function shell():String {
		return platform() == "win32" ? "cmd.exe" : "/bin/sh";
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
