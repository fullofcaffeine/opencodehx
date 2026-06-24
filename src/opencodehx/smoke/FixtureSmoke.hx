package opencodehx.smoke;

import opencodehx.externs.node.ChildProcess;
import opencodehx.externs.node.Fs;

using StringTools;

class FixtureSmoke {
	public static function run():Void {
		tmpdir();
	}

	static function tmpdir():Void {
		final tmp = SmokeTmpDir.create({git: true});
		final dir = tmp.path;
		var disposed = false;
		try {
			eq(plainGitConfig(dir, "core.fsmonitor"), "false", "tmpdir fsmonitor disabled");
			tmp.dispose();
			disposed = true;
			eq(Fs.existsSync(dir), false, "tmpdir dispose removes directory");
		} catch (error:Dynamic) {
			if (!disposed)
				tmp.dispose();
			throw error;
		}
	}

	static function plainGitConfig(cwd:String, key:String):String {
		final result = ChildProcess.spawnSync("git", ["config", key], {
			cwd: cwd,
			encoding: "utf8",
			windowsHide: true,
			maxBuffer: 1024 * 1024,
		});
		if (result.error != null)
			throw 'plain git config ${key}: ${result.error.message}';
		if (result.status != 0)
			throw 'plain git config ${key}: ${result.stderr}';
		return result.stdout.trim();
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}
