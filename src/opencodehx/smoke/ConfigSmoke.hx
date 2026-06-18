package opencodehx.smoke;

import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigError.ConfigFailure;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigLoader;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;

class ConfigSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-config-"));
		try {
			missingConfig(root);
			jsonAndJsonc(root);
			envContentAndSubstitution(root);
			legacyTuiKeys(root);
			invalidJson(root);
			invalidSchema(root);
			fileSubstitution(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function missingConfig(root:String):Void {
		final dir = directory(root, "missing");
		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		eq(config.username, "fixture-user", "missing username default");
		eq(config.model, null, "missing model");
	}

	static function jsonAndJsonc(root:String):Void {
		final dir = directory(root, "jsonc-wins");
		write(dir, "opencode.json", '{"' + "$" + 'schema":"${ConfigInfo.DEFAULT_SCHEMA}","model":"json/model","username":"json-user"}');
		write(dir, "opencode.jsonc", '{
  // jsonc takes precedence over json in the same directory
  "'
			+ "$"
			+ 'schema": "${ConfigInfo.DEFAULT_SCHEMA}",
  "model": "jsonc/model",
  "username": "jsonc-user",
  "share": "manual",
  "autoupdate": "notify",
}');
		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		eq(config.model, "jsonc/model", "jsonc model override");
		eq(config.username, "jsonc-user", "jsonc username override");
		eq(config.share, ShareManual, "share enum parse");
		eq(config.autoupdate, AutoUpdateNotify, "autoupdate enum parse");
	}

	static function envContentAndSubstitution(root:String):Void {
		final dir = directory(root, "env-content");
		write(dir, "opencode.json", '{"username":"{env:USER_NAME}","model":"base/model"}');
		final config = ConfigLoader.loadProject(dir, {
			defaultUsername: "fixture-user",
			env: {
				USER_NAME: "env-user",
				OPENCODE_CONFIG_CONTENT: '{"model":"content/model","instructions":["AGENTS.md"]}'
			},
		});
		eq(config.username, "env-user", "env substitution");
		eq(config.model, "content/model", "config content override");
		eq(config.instructions.join(","), "AGENTS.md", "content instructions");
	}

	static function legacyTuiKeys(root:String):Void {
		final dir = directory(root, "legacy-tui");
		write(dir, "opencode.json", '{"model":"test/model","theme":"legacy","tui":{"scroll_speed":4},"keybinds":{"x":"y"}}');
		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		eq(config.model, "test/model", "legacy tui stripped model preserved");
	}

	static function invalidJson(root:String):Void {
		final dir = directory(root, "bad-json");
		write(dir, "opencode.json", "{ invalid json }");
		expectFailure(() -> ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"}), "invalid json", function(failure) {
			return switch failure {
				case JsonError(_, _): true;
				case _: false;
			}
		});
	}

	static function invalidSchema(root:String):Void {
		final dir = directory(root, "bad-schema");
		write(dir, "opencode.json", '{"invalid_field":"nope"}');
		expectFailure(() -> ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"}), "invalid schema", function(failure) {
			return switch failure {
				case InvalidError(_, issues): issues.join("\n").indexOf("invalid_field") != -1;
				case _: false;
			}
		});
	}

	static function fileSubstitution(root:String):Void {
		final dir = directory(root, "file-substitution");
		write(dir, "included.txt", "file-user");
		write(dir, "opencode.json", '{"username":"{file:included.txt}"}');
		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		eq(config.username, "file-user", "file substitution");
	}

	static function directory(root:String, name:String):String {
		final dir = NodePath.join(root, name);
		Fs.mkdirSync(dir, {recursive: true});
		return dir;
	}

	static function write(dir:String, name:String, data:String):Void {
		Fs.writeFileSync(NodePath.join(dir, name), data);
	}

	static function expectFailure(run:() -> Void, label:String, matches:ConfigFailure->Bool):Void {
		try {
			run();
		} catch (error:ConfigException) {
			if (matches(error.failure))
				return;
			throw '${label}: unexpected failure ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
