package opencodehx.git;

import opencodehx.externs.node.ChildProcess;

using StringTools;

enum abstract GitChangeKind(String) to String {
	var Added = "added";
	var Deleted = "deleted";
	var Modified = "modified";
}

typedef GitBase = {
	final name:String;
	final ref:String;
}

typedef GitItem = {
	final file:String;
	final code:String;
	final status:GitChangeKind;
}

typedef GitStat = {
	final file:String;
	final additions:Int;
	final deletions:Int;
}

typedef GitRunResult = {
	final code:Int;
	final stdout:String;
	final stderr:String;
}

class Git {
	static final BASE_ARGS = [
		"--no-optional-locks",
		"-c",
		"core.autocrlf=false",
		"-c",
		"core.fsmonitor=false",
		"-c",
		"core.longpaths=true",
		"-c",
		"core.symlinks=true",
		"-c",
		"core.quotepath=false",
	];

	public static function baseArgs():Array<String> {
		return BASE_ARGS.copy();
	}

	public static function run(cwd:String, args:Array<String>):GitRunResult {
		final result = ChildProcess.spawnSync("git", baseArgs().concat(args), {
			cwd: cwd,
			encoding: "utf8",
			windowsHide: true,
			maxBuffer: 20 * 1024 * 1024,
		});
		if (result.error != null) {
			return {
				code: 1,
				stdout: "",
				stderr: result.error.message == null ? Std.string(result.error) : result.error.message,
			};
		}
		return {
			code: result.status == null ? 1 : result.status,
			stdout: result.stdout == null ? "" : result.stdout,
			stderr: result.stderr == null ? "" : result.stderr,
		};
	}

	public static function branch(cwd:String):Null<String> {
		final result = run(cwd, ["symbolic-ref", "--quiet", "--short", "HEAD"]);
		if (result.code != 0)
			return null;
		final value = result.stdout.trim();
		return value == "" ? null : value;
	}

	public static function prefix(cwd:String):String {
		final result = run(cwd, ["rev-parse", "--show-prefix"]);
		return result.code == 0 ? result.stdout.trim() : "";
	}

	public static function defaultBranch(cwd:String):Null<GitBase> {
		final remote = primaryRemote(cwd);
		if (remote != null) {
			final head = run(cwd, ["symbolic-ref", 'refs/remotes/${remote}/HEAD']);
			if (head.code == 0) {
				final ref = new EReg("^refs/remotes/", "").replace(head.stdout.trim(), "");
				final prefix = '${remote}/';
				final name = ref.startsWith(prefix) ? ref.substr(prefix.length) : "";
				if (name != "")
					return {name: name, ref: ref};
			}
		}

		final branches = refs(cwd);
		final configured = run(cwd, ["config", "init.defaultBranch"]).stdout.trim();
		if (configured != "" && branches.indexOf(configured) != -1)
			return {name: configured, ref: configured};
		if (branches.indexOf("main") != -1)
			return {name: "main", ref: "main"};
		if (branches.indexOf("master") != -1)
			return {name: "master", ref: "master"};
		return null;
	}

	public static function hasHead(cwd:String):Bool {
		return run(cwd, ["rev-parse", "--verify", "HEAD"]).code == 0;
	}

	public static function mergeBase(cwd:String, base:String, ?head:String):Null<String> {
		final result = run(cwd, ["merge-base", base, head == null ? "HEAD" : head]);
		if (result.code != 0)
			return null;
		final value = result.stdout.trim();
		return value == "" ? null : value;
	}

	public static function show(cwd:String, ref:String, file:String, ?prefix:String):String {
		final target = prefix == null || prefix == "" ? file : prefix + file;
		final result = run(cwd, ["show", '${ref}:${target}']);
		if (result.code != 0 || result.stdout.indexOf(String.fromCharCode(0)) != -1)
			return "";
		return result.stdout;
	}

	public static function status(cwd:String):Array<GitItem> {
		final result = run(cwd, [
			"status",
			"--porcelain=v1",
			"--untracked-files=all",
			"--no-renames",
			"-z",
			"--",
			"."
		]);
		return parseStatusNuls(result.stdout);
	}

	public static function diff(cwd:String, ref:String):Array<GitItem> {
		final result = run(cwd, ["diff", "--no-ext-diff", "--no-renames", "--name-status", "-z", ref, "--", "."]);
		final list = nuls(result.stdout);
		final out:Array<GitItem> = [];
		var index = 0;
		while (index < list.length) {
			final code = list[index];
			final file = index + 1 < list.length ? list[index + 1] : "";
			if (code != "" && file != "")
				out.push({file: file, code: code, status: kind(code)});
			index += 2;
		}
		return out;
	}

	public static function diffFile(cwd:String, file:String):String {
		final unstaged = run(cwd, ["diff", "--no-ext-diff", "--no-renames", "--", file]);
		if (unstaged.code == 0 && unstaged.stdout.trim() != "")
			return unstaged.stdout;
		final staged = run(cwd, ["diff", "--no-ext-diff", "--no-renames", "--staged", "--", file]);
		return staged.code == 0 ? staged.stdout : "";
	}

	public static function stats(cwd:String, ref:String):Array<GitStat> {
		final result = run(cwd, ["diff", "--no-ext-diff", "--no-renames", "--numstat", "-z", ref, "--", "."]);
		final out:Array<GitStat> = [];
		for (item in nuls(result.stdout)) {
			final first = item.indexOf("\t");
			final second = first == -1 ? -1 : item.indexOf("\t", first + 1);
			if (first == -1 || second == -1)
				continue;
			final file = item.substr(second + 1);
			if (file == "")
				continue;
			out.push({
				file: file,
				additions: number(item.substr(0, first)),
				deletions: number(item.substr(first + 1, second - first - 1)),
			});
		}
		return out;
	}

	static function primaryRemote(cwd:String):Null<String> {
		final list = lines(run(cwd, ["remote"]).stdout);
		if (list.indexOf("origin") != -1)
			return "origin";
		if (list.length == 1)
			return list[0];
		if (list.indexOf("upstream") != -1)
			return "upstream";
		return list.length == 0 ? null : list[0];
	}

	static function refs(cwd:String):Array<String> {
		return lines(run(cwd, ["for-each-ref", "--format=%(refname:short)", "refs/heads"]).stdout);
	}

	static function parseStatusNuls(text:String):Array<GitItem> {
		final out:Array<GitItem> = [];
		for (item in nuls(text)) {
			if (item.length < 4)
				continue;
			final code = item.substr(0, 2);
			final file = item.substr(3);
			if (file != "")
				out.push({file: file, code: code, status: kind(code)});
		}
		return out;
	}

	static function nuls(text:String):Array<String> {
		return text.split(String.fromCharCode(0)).filter(item -> item != "");
	}

	static function lines(text:String):Array<String> {
		final out:Array<String> = [];
		for (line in text.split("\n")) {
			final value = line.trim();
			if (value != "")
				out.push(value);
		}
		return out;
	}

	static function kind(code:String):GitChangeKind {
		if (code == "??")
			return Added;
		if (code.indexOf("U") != -1)
			return Modified;
		if (code.indexOf("A") != -1 && code.indexOf("D") == -1)
			return Added;
		if (code.indexOf("D") != -1 && code.indexOf("A") == -1)
			return Deleted;
		return Modified;
	}

	static function number(value:String):Int {
		if (value == "-")
			return 0;
		final parsed = Std.parseInt(value == "" ? "0" : value);
		return parsed == null ? 0 : parsed;
	}
}
