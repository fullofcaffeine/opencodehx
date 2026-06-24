package opencodehx.smoke;

import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.git.Git;
import opencodehx.git.Git.GitRunResult;
import opencodehx.host.node.NodePath;

typedef SmokeTmpDirOptions = {
	@:optional final git:Bool;
}

class SmokeTmpDir {
	public final path:String;

	function new(path:String) {
		this.path = path;
	}

	public static function create(?options:SmokeTmpDirOptions):SmokeTmpDir {
		final tmp = new SmokeTmpDir(Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-tmpdir-")));
		try {
			if (options != null && options.git == true)
				tmp.initGit();
		} catch (error:Dynamic) {
			tmp.dispose();
			throw error;
		}
		return tmp;
	}

	public function dispose():Void {
		Fs.rmSync(path, {recursive: true, force: true});
	}

	function initGit():Void {
		require(Git.run(path, ["init"]), "tmpdir git init");
		require(Git.run(path, ["config", "core.fsmonitor", "false"]), "tmpdir disable fsmonitor");
	}

	static function require(result:GitRunResult, label:String):Void {
		if (result.code != 0)
			throw '${label}: ${result.stderr}';
	}
}
