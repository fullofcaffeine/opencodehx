package opencodehx.util;

import haxe.DynamicAccess;
import js.lib.Error;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Process;
import opencodehx.host.node.NodePath;

class Which {
	static inline final UNIX_EXECUTABLE_BITS = 73;

	public static function which(command:String, ?env:DynamicAccess<String>):Null<String> {
		final base = envValue(env, "PATH");
		if (base == null || base == "")
			return null;
		final isWin = Process.platform == "win32";
		final separator = isWin ? ";" : ":";
		final extensions = command.indexOf(".") == -1 && isWin ? pathExtensions(env) : [""];
		for (dir in base.split(separator)) {
			if (dir == "")
				continue;
			for (ext in extensions) {
				final candidate = NodePath.join(dir, command + ext);
				if (isExecutable(candidate, isWin))
					return candidate;
			}
		}
		return null;
	}

	static function pathExtensions(env:Null<DynamicAccess<String>>):Array<String> {
		final raw = envValue(env, "PATHEXT");
		if (raw == null || raw == "")
			return [".EXE", ".CMD", ".BAT", ".COM"];
		final out:Array<String> = [];
		for (ext in raw.split(";")) {
			if (ext != "")
				out.push(ext);
		}
		return out.length == 0 ? [".EXE", ".CMD", ".BAT", ".COM"] : out;
	}

	static function envValue(env:Null<DynamicAccess<String>>, key:String):Null<String> {
		if (env == null)
			return processEnvValue(key);
		if (Process.platform != "win32")
			return env.get(key);
		final lower = key.toLowerCase();
		for (name in env.keys()) {
			if (name.toLowerCase() == lower)
				return env.get(name);
		}
		return null;
	}

	static function processEnvValue(key:String):Null<String> {
		if (Process.platform != "win32")
			return Process.env.get(key);
		final lower = key.toLowerCase();
		for (name in Process.env.keys()) {
			if (name.toLowerCase() == lower)
				return Process.env.get(name);
		}
		return null;
	}

	static function isExecutable(file:String, isWin:Bool):Bool {
		try {
			if (!Fs.existsSync(file))
				return false;
			final stat = Fs.statSync(file);
			if (!stat.isFile())
				return false;
			if (isWin)
				return true;
			final mode = stat.mode;
			return mode != null && (mode & UNIX_EXECUTABLE_BITS) != 0;
		} catch (_:Error) {
			return false;
		}
	}
}
