package opencodehx.skill;

import genes.js.Async.await;
import js.Syntax;
import js.lib.Promise;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;

typedef SkillIndexEntry = {
	final name:String;
	final files:Array<String>;
}

typedef SkillIndexPayload = {
	final skills:Array<SkillIndexEntry>;
}

extern typedef SkillFetchResponse = {
	final ok:Bool;
	final status:Int;
	function text():Promise<String>;
	function json():Promise<SkillIndexPayload>;
}

typedef SkillFetchFunction = String->Promise<SkillFetchResponse>;

class SkillRemoteDiscovery {
	@:async
	public static function pull(url:String, cacheDir:String, ?fetcher:SkillFetchFunction):Promise<Array<String>> {
		final fetch = fetcher == null ? defaultFetch : fetcher;
		final base = StringTools.endsWith(url, "/") ? url : url + "/";
		final indexUrl = resolveUrl("index.json", base);
		final host = base.substr(0, base.length - 1);
		final index = @:await fetchIndex(fetch, indexUrl);
		if (index == null || !isSkillIndex(index))
			return [];

		final result:Array<String> = [];
		for (skill in index.skills) {
			if (!isValidSkill(skill) || skill.files.indexOf("SKILL.md") == -1)
				continue;
			final root = NodePath.join(cacheDir, skill.name);
			var downloadedSkillFile = false;
			for (file in skill.files) {
				final target = safeCachePath(root, file);
				if (target == null)
					continue;
				final source = resolveUrl(file, host + "/" + skill.name + "/");
				final ok = @:await download(fetch, source, target);
				if (ok && file == "SKILL.md")
					downloadedSkillFile = true;
			}
			final md = NodePath.join(root, "SKILL.md");
			if (downloadedSkillFile || Fs.existsSync(md))
				result.push(root);
		}
		return result;
	}

	@:async
	static function fetchIndex(fetch:SkillFetchFunction, url:String):Promise<Null<SkillIndexPayload>> {
		try {
			final response = @:await fetch(url);
			if (!response.ok)
				return null;
			return @:await response.json();
		} catch (_:Dynamic) {
			// Fetch/json failures come from the JS runtime boundary; returning no
			// remote skills matches upstream's best-effort discovery behavior.
			return null;
		}
	}

	@:async
	static function download(fetch:SkillFetchFunction, url:String, target:String):Promise<Bool> {
		if (Fs.existsSync(target))
			return true;
		try {
			final response = @:await fetch(url);
			if (!response.ok)
				return false;
			final text = @:await response.text();
			Fs.mkdirSync(NodePath.dirname(target), {recursive: true});
			Fs.writeFileSync(target, text);
			return true;
		} catch (_:Dynamic) {
			// Network and filesystem failures are contained to this file download;
			// callers only see the successfully cached skill directories.
			return false;
		}
	}

	static function defaultFetch(url:String):Promise<SkillFetchResponse> {
		return Syntax.code("fetch({0})", url);
	}

	static function safeCachePath(root:String, file:String):Null<String> {
		if (NodePath.isAbsolute(file))
			return null;
		final target = NodePath.resolve(root, file);
		final relative = NodePath.relative(root, target);
		if (relative == ".."
			|| StringTools.startsWith(relative, "../")
			|| StringTools.startsWith(relative, "..\\")
			|| NodePath.isAbsolute(relative))
			return null;
		return target;
	}

	static function isSkillIndex(index:SkillIndexPayload):Bool {
		return Syntax.code("Array.isArray({0}.skills)", index);
	}

	static function isValidSkill(skill:SkillIndexEntry):Bool {
		return Syntax.code("typeof {0}.name === 'string' && Array.isArray({0}.files) && {0}.files.every((file) => typeof file === 'string')", skill);
	}

	static function resolveUrl(path:String, base:String):String {
		return Syntax.code("new URL({0}, {1}).href", path, base);
	}
}
