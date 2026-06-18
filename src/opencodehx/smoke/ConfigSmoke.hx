package opencodehx.smoke;

import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigError.ConfigFailure;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigLoader;
import opencodehx.config.ConfigPlugin;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeLocal;
import opencodehx.config.ConfigWriter;
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
			projectDiscovery(root);
			configDirAndProjectDisable(root);
			schemaAutoAddPreservesTokens(root);
			pluginMergeAndOrigins(root);
			globalLoadAndUpdate(root);
			localUpdateWritesConfigJson(root);
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

	static function projectDiscovery(root:String):Void {
		final worktree = directory(root, "project-discovery");
		write(worktree, "opencode.json", '{"model":"root/model","instructions":["root.md","shared.md"]}');
		final project = directory(worktree, "project");
		write(project, "opencode.json", '{"model":"project/model","instructions":["shared.md","project.md"]}');
		final opencodeDir = directory(project, ".opencode");
		write(opencodeDir, "opencode.json", '{"model":"opencode/model","username":"opencode-user","instructions":["opencode.md"]}');
		final nested = directory(project, "nested");

		final config = ConfigLoader.loadProject(nested, {defaultUsername: "fixture-user", worktree: worktree});
		eq(config.model, "opencode/model", ".opencode model override");
		eq(config.username, "opencode-user", ".opencode username override");
		eq(config.instructions.join(","), "root.md,shared.md,project.md,opencode.md", "ancestor instruction merge");
	}

	static function configDirAndProjectDisable(root:String):Void {
		final project = directory(root, "project-disabled");
		write(project, "opencode.json", '{"model":"project/model"}');
		final opencodeDir = directory(project, ".opencode");
		write(opencodeDir, "opencode.json", '{"model":"opencode/model"}');
		final configDir = directory(root, "config-dir");
		write(configDir, "opencode.json", '{"model":"configdir/model"}');

		final config = ConfigLoader.loadProject(project, {
			defaultUsername: "fixture-user",
			worktree: project,
			env: {
				OPENCODE_DISABLE_PROJECT_CONFIG: "true",
				OPENCODE_CONFIG_DIR: configDir
			}
		});
		eq(config.model, "configdir/model", "OPENCODE_CONFIG_DIR loads with project config disabled");

		final enabled = ConfigLoader.loadProject(project, {
			defaultUsername: "fixture-user",
			worktree: project,
			env: {
				OPENCODE_CONFIG_DIR: configDir
			}
		});
		eq(enabled.model, "configdir/model", "OPENCODE_CONFIG_DIR overrides project .opencode");
	}

	static function schemaAutoAddPreservesTokens(root:String):Void {
		final dir = directory(root, "schema-preserves-tokens");
		final path = NodePath.join(dir, "opencode.json");
		write(dir, "opencode.json", '{"username":"{env:PRESERVE_USER}","model":"schema/model"}');
		final config = ConfigLoader.loadProject(dir, {
			defaultUsername: "fixture-user",
			env: {
				PRESERVE_USER: "secret-user"
			}
		});
		eq(config.schema, ConfigInfo.DEFAULT_SCHEMA, "schema auto-add model value");
		eq(config.username, "secret-user", "schema auto-add parsed env value");

		final updated = Fs.readFileSync(path, "utf8");
		contains(updated, "$schema", "schema auto-add writes schema");
		contains(updated, "{env:PRESERVE_USER}", "schema auto-add preserves raw env token");
		notContains(updated, "secret-user", "schema auto-add does not leak expanded env value");
	}

	static function pluginMergeAndOrigins(root:String):Void {
		final worktree = directory(root, "plugin-merge");
		final project = directory(worktree, "project");
		write(worktree, "opencode.json",
			'{"' + "$" +
			'schema":"${ConfigInfo.DEFAULT_SCHEMA}","plugin":[["shared-plugin@1.0.0",{"source":"root"}],"global-only@1.0.0","file:///tmp/opencodehx-plugin.js"]}');
		final opencodeDir = directory(project, ".opencode");
		write(opencodeDir, "opencode.json",
			'{"' + "$" +
			'schema":"${ConfigInfo.DEFAULT_SCHEMA}","plugin":[["shared-plugin@2.0.0",{"source":"local"}],"local-only@1.0.0","file:///tmp/opencodehx-plugin.js"]}');

		final config = ConfigLoader.loadProject(project, {defaultUsername: "fixture-user", worktree: worktree});
		final names = [for (plugin in config.plugin) ConfigPlugin.specifier(plugin)];
		eq(names.join(","), "global-only@1.0.0,shared-plugin@2.0.0,local-only@1.0.0,file:///tmp/opencodehx-plugin.js", "plugin merge/dedupe order");
		eq(config.pluginOrigins.length, config.plugin.length, "plugin origins align length");
		for (index in 0...config.plugin.length) {
			eq(ConfigPlugin.specifier(config.pluginOrigins[index].spec), ConfigPlugin.specifier(config.plugin[index]), 'plugin origin aligns ${index}');
		}
		final shared = config.pluginOrigins[1];
		eq(shared.scope, PluginScopeLocal, "plugin origin scope");
		contains(shared.source, ".opencode", "plugin origin source");
		eq(Reflect.field(shared.spec.options, "source"), "local", "plugin tuple options preserved");
	}

	static function globalLoadAndUpdate(root:String):Void {
		final dir = directory(root, "global-update");
		write(dir, "config.json", '{"model":"legacy/model","instructions":["legacy.md"]}');
		write(dir, "opencode.json", '{"model":"json/model","instructions":["json.md"]}');
		write(dir, "opencode.jsonc", '{
  // keep this comment while patching
  "model": "jsonc/model",
  "plugin": ["old-plugin@1.0.0"]
}');

		final loaded = ConfigWriter.loadGlobal(dir);
		eq(loaded.model, "jsonc/model", "global load jsonc precedence");
		eq(loaded.instructions.join(","), "legacy.md,json.md", "global load merge order");

		final patch = new ConfigInfo();
		patch.model = "patched/model";
		patch.server = {port: 4096};
		patch.plugin = [{specifier: "new-plugin@2.0.0"}];
		patch.pluginOrigins = [ConfigPlugin.withOrigin(patch.plugin[0], "internal", PluginScopeLocal)];

		final next = ConfigWriter.updateGlobal(dir, patch);
		eq(next.model, "patched/model", "global update return model");
		eq(next.server.port, 4096, "global update nested server");
		eq(ConfigPlugin.specifier(next.plugin[0]), "new-plugin@2.0.0", "global update plugin");

		final text = Fs.readFileSync(NodePath.join(dir, "opencode.jsonc"), "utf8");
		contains(text, "keep this comment", "global update preserves jsonc comments");
		contains(text, '"model": "patched/model"', "global update writes model");
		contains(text, '"port": 4096', "global update writes nested server");
		contains(text, '"plugin": [', "global update writes plugin");
		notContains(text, "plugin_origins", "global update omits plugin origins");

		final freshDir = directory(root, "global-update-new");
		final fresh = new ConfigInfo();
		fresh.model = "fresh/model";
		ConfigWriter.updateGlobal(freshDir, fresh);
		eq(Fs.existsSync(NodePath.join(freshDir, "opencode.jsonc")), true, "global update creates opencode.jsonc");
	}

	static function localUpdateWritesConfigJson(root:String):Void {
		final dir = directory(root, "local-update");
		write(dir, "config.json", '{"model":"old/model","permission":{"bash":"ask"}}');

		final patch = new ConfigInfo();
		patch.model = "new/model";
		patch.permission = cast {
			bash: "allow",
		};

		final next = ConfigWriter.updateLocal(dir, patch);
		eq(next.model, "new/model", "local update return model");
		eq(Reflect.field(next.permission, "bash"), "allow", "local update nested permission");

		final text = Fs.readFileSync(NodePath.join(dir, "config.json"), "utf8");
		contains(text, '"model": "new/model"', "local update writes config.json");
		contains(text, '"bash": "allow"', "local update merges permission");
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

	static function contains(text:String, needle:String, label:String):Void {
		if (text.indexOf(needle) == -1)
			throw '$label: expected to contain ${needle}';
	}

	static function notContains(text:String, needle:String, label:String):Void {
		if (text.indexOf(needle) != -1)
			throw '$label: expected not to contain ${needle}';
	}
}
