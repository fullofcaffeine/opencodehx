package opencodehx.smoke;

import haxe.DynamicAccess;
import genes.js.Async.await;
import js.Syntax;
import js.lib.Promise;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigError.ConfigFailure;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.OpenConfigValue;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigLoader.ConfigEnv;
import opencodehx.config.ConfigLoader;
import opencodehx.config.ConfigPlugin;
import opencodehx.config.ConfigPlugin.PluginOrigin;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeLocal;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeGlobal;
import opencodehx.config.ConfigWriter;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Url;
import opencodehx.externs.web.Fetch.FetchFunction;
import opencodehx.externs.web.Fetch.RemoteConfigObject;
import opencodehx.host.node.NodePath;

typedef RemoteMcpEntry = {
	final enabled:Bool;
}

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
			pluginDirectoryDiscovery(root);
			globalLoadAndUpdate(root);
			legacyGlobalTomlMigration(root);
			localUpdateWritesConfigJson(root);
			legacyToolsMigration(root);
			finalizationEnvFlags(root);
			commandAgentDiscovery(root);
			projectDisableSkipsDiscoveredEntries(root);
			invalidJson(root);
			invalidSchema(root);
			fileSubstitution(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	@:async
	public static function runRemote():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-config-remote-"));
		final originalFetch:FetchFunction = Syntax.code("globalThis.fetch");
		try {
			Syntax.code("(globalThis as unknown as { __opencodehxFetchedUrl?: string }).__opencodehxFetchedUrl = undefined");
			Syntax.code("globalThis.fetch = (url: string | URL | Request) => {
				const text = url instanceof Request ? url.url : url instanceof URL ? url.href : String(url);
				(globalThis as unknown as { __opencodehxFetchedUrl?: string }).__opencodehxFetchedUrl = text;
				return Promise.resolve(new Response(JSON.stringify({
					config: {
						username: '{env:TEST_TOKEN}',
						mcp: { jira: { type: 'remote', url: 'https://jira.example.com/mcp', enabled: false } }
					}
				}), { status: 200 }));
			}");
			final project = directory(root, "remote-project");
			write(project, "opencode.json", '{"model":"project/model","mcp":{"jira":{"type":"remote","url":"https://jira.example.com/mcp","enabled":true}}}');
			final env:ConfigEnv = cast {};
			final accountConfig = accountRemoteConfig();
			final config = @:await ConfigLoader.loadProjectWithRemoteSources(project,
				[{url: "https://example.com/", key: "TEST_TOKEN", token: "remote-token"}], [
				{url: "https://control.example.com/", token: "st_test_token", config: accountConfig}
			], {defaultUsername: "fixture-user", worktree: project, env: env});

			eq(Syntax.code("(globalThis as unknown as { __opencodehxFetchedUrl?: string }).__opencodehxFetchedUrl ?? null"),
				"https://example.com/.well-known/opencode", "remote well-known URL normalized");
			eq(config.username, "remote-token", "remote well-known env token substitution");
			final jira:RemoteMcpEntry = cast Reflect.field(config.mcp, "jira");
			eq(jira.enabled, true, "project config overrides remote well-known config");
			eq(config.model, "account/model", "account config overrides project config");
			eq(Reflect.field(env, "OPENCODE_CONSOLE_TOKEN"), "st_test_token", "account token injected into substitution env");
			final providers = require(config.provider, "account provider map");
			final provider = require(providers.get("opencode"), "account provider config");
			final options = require(provider.options, "account provider options");
			eq(Reflect.field(options, "apiKey"), "st_test_token", "account config resolves token env template");
			Syntax.code("globalThis.fetch = {0}", originalFetch);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Syntax.code("globalThis.fetch = {0}", originalFetch);
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function accountRemoteConfig():RemoteConfigObject {
		final options = new DynamicAccess<OpenConfigValue>();
		options.set("apiKey", "{env:OPENCODE_CONSOLE_TOKEN}");
		final opencode = new DynamicAccess<OpenConfigValue>();
		opencode.set("options", options);
		final provider = new DynamicAccess<OpenConfigValue>();
		provider.set("opencode", opencode);
		final config = new DynamicAccess<OpenConfigValue>();
		config.set("provider", provider);
		config.set("model", "account/model");
		return config;
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

	static function pluginDirectoryDiscovery(root:String):Void {
		final worktree = directory(root, "plugin-discovery");
		final project = directory(worktree, "project");
		final opencodeDir = directory(project, ".opencode");
		final pluginDir = directory(opencodeDir, "plugin");
		final pluginsDir = directory(opencodeDir, "plugins");
		write(pluginDir, "local-a.js", "export default {}");
		write(pluginsDir, "local-b.ts", "export default {}");
		write(pluginsDir, "ignore.md", "not a plugin");

		final configDir = directory(root, "plugin-config-dir");
		final configPluginsDir = directory(configDir, "plugins");
		write(configPluginsDir, "global.js", "export default {}");

		final config = ConfigLoader.loadProject(project, {
			defaultUsername: "fixture-user",
			worktree: worktree,
			env: {
				OPENCODE_CONFIG_DIR: configDir
			},
		});

		final localA = Url.pathToFileURL(NodePath.join(pluginDir, "local-a.js")).href;
		final localB = Url.pathToFileURL(NodePath.join(pluginsDir, "local-b.ts")).href;
		final global = Url.pathToFileURL(NodePath.join(configPluginsDir, "global.js")).href;
		final names = [for (plugin in config.plugin) ConfigPlugin.specifier(plugin)];
		eq(names.indexOf(localA) != -1, true, "plugin directory singular discovery");
		eq(names.indexOf(localB) != -1, true, "plugin directory plural discovery");
		eq(names.indexOf(global) != -1, true, "plugin config dir discovery");
		eq(hasSuffix(names, "ignore.md"), false, "plugin discovery ignores non-js-ts");

		final localOrigin = require(findOrigin(config.pluginOrigins, localA), "local plugin origin");
		eq(localOrigin.scope, PluginScopeLocal, "local discovered plugin scope");
		eq(localOrigin.source, opencodeDir, "local discovered plugin source");
		final globalOrigin = require(findOrigin(config.pluginOrigins, global), "global plugin origin");
		eq(globalOrigin.scope, PluginScopeGlobal, "config dir discovered plugin scope");
		eq(globalOrigin.source, configDir, "config dir discovered plugin source");
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

	static function legacyGlobalTomlMigration(root:String):Void {
		final dir = directory(root, "legacy-global-toml");
		write(dir, "opencode.jsonc", '{
  "instructions": ["jsonc.md"],
  "model": "jsonc/model"
}');
		write(dir, "config", 'provider = "anthropic"
model = "claude-sonnet-4-5"
instructions = ["legacy.md"]
disabled_providers = ["openai"]
');

		final migrated = ConfigWriter.loadGlobal(dir);
		eq(migrated.model, "anthropic/claude-sonnet-4-5", "legacy toml provider/model migration");
		eq(migrated.instructions.join(","), "jsonc.md,legacy.md", "legacy toml merges rest fields");
		eq(migrated.schema, ConfigInfo.DEFAULT_SCHEMA, "legacy toml writes schema");
		eq(Fs.existsSync(NodePath.join(dir, "config")), false, "legacy toml file removed");
		eq(Fs.existsSync(NodePath.join(dir, "config.json")), true, "legacy toml writes config.json");

		final written = Fs.readFileSync(NodePath.join(dir, "config.json"), "utf8");
		contains(written, '"model": "anthropic/claude-sonnet-4-5"', "legacy toml written model");
		contains(written, '"disabled_providers": [', "legacy toml writes rest fields");
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

	static function legacyToolsMigration(root:String):Void {
		final dir = directory(root, "legacy-tools");
		write(dir, "opencode.json", '{"permission":{"glob":"allow","bash":"deny"},"tools":{"bash":true,"write":false,"read":false,"patch":true}}');

		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		final permission = require(config.permission, "legacy tools permission");
		eq(permission.get("glob"), "allow", "legacy tools preserves explicit permission");
		eq(permission.get("bash"), "deny", "explicit permission overrides migrated tool");
		eq(permission.get("edit"), "allow", "write/edit/patch tools collapse to edit permission");
		eq(permission.get("read"), "deny", "legacy read tool migrates to permission");
	}

	static function finalizationEnvFlags(root:String):Void {
		final dir = directory(root, "finalization-flags");
		write(dir, "opencode.json", '{"autoshare":true,"permission":{"bash":"deny"},"compaction":{"auto":true,"prune":true,"tail_turns":3,"reserved":128}}');

		final config = ConfigLoader.loadProject(dir, {
			defaultUsername: "fixture-user",
			env: {
				OPENCODE_PERMISSION: '{"bash":"allow","read":"deny"}',
				OPENCODE_DISABLE_AUTOCOMPACT: "1",
				OPENCODE_DISABLE_PRUNE: "true",
			},
		});

		eq(config.autoshare, true, "autoshare source preserved");
		eq(config.share, ShareAuto, "autoshare migrates to share auto");
		final permission = require(config.permission, "env permission");
		eq(permission.get("bash"), "allow", "env permission overrides config permission");
		eq(permission.get("read"), "deny", "env permission adds rule");
		final compaction = require(config.compaction, "compaction flags");
		eq(compaction.auto, false, "disable autocompact flag");
		eq(compaction.prune, false, "disable prune flag");
		eq(compaction.tail_turns, 3, "compaction tail turns preserved");
		eq(compaction.reserved, 128, "compaction reserved preserved");
	}

	static function commandAgentDiscovery(root:String):Void {
		final worktree = directory(root, "entry-discovery");
		final project = directory(worktree, "project");
		final opencodeDir = directory(project, ".opencode");
		final agentDir = directory(opencodeDir, "agents");
		directory(agentDir, "nested");
		write(agentDir, "helper.md", '---
model: test/model
mode: subagent
tools:
  write: true
color: "#FFA500"
---
Helper agent prompt');
		write(NodePath.join(agentDir, "nested"), "child.md", '---
model: test/model
mode: subagent
---
Nested agent prompt');

		final commandDir = directory(opencodeDir, "command");
		directory(commandDir, "nested");
		write(commandDir, "hello.md", '---
description: Test command
agent: helper
subtask: true
---
Hello from singular command');
		write(NodePath.join(commandDir, "nested"), "child.md", '---
description: Nested command
---
Nested command template');

		final modeDir = directory(opencodeDir, "modes");
		write(modeDir, "plan.md", '---
model: test/model
---
Plan mode prompt');

		final configDir = directory(root, "entry-config-dir");
		final configCommands = directory(configDir, "commands");
		write(configCommands, "global.md", '---
description: Global command
---
Global command template');

		final config = ConfigLoader.loadProject(project, {
			defaultUsername: "fixture-user",
			worktree: worktree,
			env: {
				OPENCODE_CONFIG_DIR: configDir
			},
		});

		final agents = require(config.agent, "agent discovery map");
		final commands = require(config.command, "command discovery map");
		final helper = require(agents.get("helper"), "helper agent");
		eq(helper.name, "helper", "agent discovery name");
		eq(helper.model, "test/model", "agent discovery model");
		eq(helper.mode, "subagent", "agent discovery mode");
		eq(helper.prompt, "Helper agent prompt", "agent discovery prompt");
		final helperPermission = require(helper.permission, "helper permission");
		eq(helperPermission.get("edit"), "allow", "agent tools permission migration");
		eq(helper.color, "#FFA500", "agent color discovery");

		final nestedAgent = require(agents.get("nested/child"), "nested agent");
		eq(nestedAgent.prompt, "Nested agent prompt", "nested agent path name");

		final plan = require(agents.get("plan"), "plan mode agent");
		eq(plan.mode, "primary", "mode discovery becomes primary agent");
		eq(plan.prompt, "Plan mode prompt", "mode prompt");

		final hello = require(commands.get("hello"), "hello command");
		eq(hello.description, "Test command", "command description");
		eq(hello.agent, "helper", "command agent");
		eq(hello.subtask, true, "command subtask");
		eq(hello.template, "Hello from singular command", "command template");

		final nestedCommand = require(commands.get("nested/child"), "nested command");
		eq(nestedCommand.template, "Nested command template", "nested command path name");
		eq(require(commands.get("global"), "global command").template, "Global command template", "OPENCODE_CONFIG_DIR command discovery");
	}

	static function projectDisableSkipsDiscoveredEntries(root:String):Void {
		final project = directory(root, "entry-disabled");
		final opencodeDir = directory(project, ".opencode");
		final commandDir = directory(opencodeDir, "command");
		write(commandDir, "skip.md", "# Skip\nShould not load");

		final config = ConfigLoader.loadProject(project, {
			defaultUsername: "fixture-user",
			worktree: project,
			env: {
				OPENCODE_DISABLE_PROJECT_CONFIG: "true"
			},
		});
		eq(config.command, null, "project disable skips command discovery");
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

	static function findOrigin(origins:Array<PluginOrigin>, specifier:String):Null<PluginOrigin> {
		for (origin in origins) {
			if (ConfigPlugin.specifier(origin.spec) == specifier)
				return origin;
		}
		return null;
	}

	static function hasSuffix(values:Array<String>, suffix:String):Bool {
		for (value in values) {
			if (StringTools.endsWith(value, suffix))
				return true;
		}
		return false;
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

	static function require<T>(value:Null<T>, label:String):T {
		if (value == null)
			throw '${label}: expected value';
		return value;
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
