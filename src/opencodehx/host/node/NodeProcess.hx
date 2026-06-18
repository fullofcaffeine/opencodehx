package opencodehx.host.node;

import js.Syntax;
import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.ChildProcess.SpawnSyncResult;

typedef ShellRun = {
	final command:String;
	final cwd:String;
	@:optional final env:Dynamic;
	@:optional final timeout:Int;
	@:optional final maxBuffer:Int;
}

class NodeProcess {
	public static function env():Dynamic {
		return Syntax.code("({ ...process.env })");
	}

	public static function platform():String {
		return Syntax.code("process.platform");
	}

	public static function shell():String {
		return platform() == "win32" ? "cmd.exe" : "/bin/sh";
	}

	public static function runShell(input:ShellRun):SpawnSyncResult {
		final options:Dynamic = {
			cwd: input.cwd,
			encoding: "utf8",
			env: input.env == null ? env() : input.env,
			shell: shell(),
			timeout: input.timeout,
			killSignal: "SIGTERM",
			windowsHide: true,
			maxBuffer: input.maxBuffer == null ? 1024 * 1024 : input.maxBuffer,
		};
		return cast ChildProcess.spawnSync(input.command, [], options);
	}
}
