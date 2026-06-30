package opencodehx.smoke;

import js.lib.Error;
import opencodehx.auth.AuthStore;
import opencodehx.auth.AuthStore.AuthMap;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

class AuthSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-auth-"));
		final originalDataHome = NodeProcess.envValue("XDG_DATA_HOME");
		final originalAuthContent = NodeProcess.envValue("OPENCODE_AUTH_CONTENT");
		try {
			NodeProcess.setEnv("XDG_DATA_HOME", root);
			NodeProcess.unsetEnv("OPENCODE_AUTH_CONTENT");
			setNormalizesTrailingSlash();
			setCleansTrailingSlashEntry();
			removeDeletesNormalizedAndTrailingSlashForms();
			setRemoveProviderID();
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Error) {
			// Preserve host/runtime smoke failures while still restoring env and tmpdir.
			Fs.rmSync(root, {recursive: true, force: true});
			restoreEnv("XDG_DATA_HOME", originalDataHome);
			restoreEnv("OPENCODE_AUTH_CONTENT", originalAuthContent);
			throw error;
		}
		restoreEnv("XDG_DATA_HOME", originalDataHome);
		restoreEnv("OPENCODE_AUTH_CONTENT", originalAuthContent);
	}

	static function setNormalizesTrailingSlash():Void {
		AuthStore.set("https://example.com/", {type: "wellknown", key: "TOKEN", token: "abc"});
		final auth = current();
		eq(auth.exists("https://example.com"), true, "auth set normalized key");
		eq(auth.exists("https://example.com/"), false, "auth set removed trailing key");
		eq(auth.get("https://example.com").token, "abc", "auth set token");
	}

	static function setCleansTrailingSlashEntry():Void {
		AuthStore.set("https://example.com/", {type: "wellknown", key: "TOKEN", token: "old"});
		AuthStore.set("https://example.com", {type: "wellknown", key: "TOKEN", token: "new"});
		final auth = current();
		final keys = keysContaining(auth, "example.com");
		eq(keys.join(","), "https://example.com", "auth set duplicate cleanup keys");
		eq(auth.get("https://example.com").token, "new", "auth set duplicate cleanup token");
	}

	static function removeDeletesNormalizedAndTrailingSlashForms():Void {
		AuthStore.set("https://example.com", {type: "wellknown", key: "TOKEN", token: "abc"});
		AuthStore.remove("https://example.com/");
		final auth = current();
		eq(auth.exists("https://example.com"), false, "auth remove normalized key");
		eq(auth.exists("https://example.com/"), false, "auth remove trailing key");
	}

	static function setRemoveProviderID():Void {
		AuthStore.set("anthropic", {type: "api", key: "api-key"});
		eq(current().get("anthropic").key, "api-key", "auth provider id set");
		AuthStore.remove("anthropic");
		eq(current().exists("anthropic"), false, "auth provider id remove");
	}

	static function current():AuthMap {
		return AuthStore.load(NodeProcess.env());
	}

	static function keysContaining(auth:AuthMap, needle:String):Array<String> {
		final out:Array<String> = [];
		for (key in auth.keys())
			if (key.indexOf(needle) != -1)
				out.push(key);
		out.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		return out;
	}

	static function restoreEnv(key:String, value:Null<String>):Void {
		if (value == null)
			NodeProcess.unsetEnv(key);
		else
			NodeProcess.setEnv(key, value);
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw new Error('$label expected ${expected} got ${actual}');
	}
}
