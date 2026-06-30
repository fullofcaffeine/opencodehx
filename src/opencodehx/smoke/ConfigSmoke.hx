package opencodehx.smoke;

import haxe.DynamicAccess;
import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import js.lib.Promise;
import opencodehx.account.AccountRepo;
import opencodehx.account.AccountRepo.AccountID;
import opencodehx.account.AccountRepo.AccessToken;
import opencodehx.account.AccountRepo.OrgID;
import opencodehx.account.AccountRepo.RefreshToken;
import opencodehx.account.AccountService;
import opencodehx.account.AccountService.AccountHttpRequest;
import opencodehx.account.AccountService.AccountHttpResponse;
import opencodehx.agent.AgentRuntime;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigError.ConfigFailure;
import opencodehx.config.ConfigDependencyRuntime;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.OpenConfigValue;
import opencodehx.config.ConfigInfo.PermissionConfigValue;
import opencodehx.config.ConfigInfo.AutoUpdate;
import opencodehx.config.ConfigInfo.ShareMode;
import opencodehx.config.ConfigLoader.ConfigEnv;
import opencodehx.config.ConfigLoader;
import opencodehx.config.ConfigLsp;
import opencodehx.config.ConfigManaged;
import opencodehx.config.ConfigMarkdown;
import opencodehx.config.ConfigMarkdown.MarkdownDocument;
import opencodehx.config.ConfigPlugin;
import opencodehx.config.ConfigPlugin.PluginOrigin;
import opencodehx.config.ConfigPlugin.PluginOptionValue;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeLocal;
import opencodehx.config.ConfigPlugin.PluginScope.PluginScopeGlobal;
import opencodehx.config.ConfigTui;
import opencodehx.config.ConfigVariable;
import opencodehx.config.ConfigWriter;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.npm.Npm as NpmRuntime;
import opencodehx.npm.Npm.NpmDeps;
import opencodehx.npm.Npm.NpmHttpResponse;
import opencodehx.npm.Npm.NpmReifyRequest;
import opencodehx.provider.ProviderOptionAccess;

typedef RemoteMcpEntry = {
	final enabled:Bool;
}

typedef ConfigNpmFixture = {
	final deps:NpmDeps;
	final requests:Array<NpmReifyRequest>;
	final responses:Map<String, NpmHttpResponse>;
	final fail:Array<Bool>;
}

class ConfigSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-config-"));
		try {
			missingConfig(root);
			jsonAndJsonc(root);
			envContentAndSubstitution(root);
			legacyTuiKeys(root);
			tuiConfig(root);
			lspConfigRefinement(root);
			markdownParsing();
			projectDiscovery(root);
			configDirAndProjectDisable(root);
			schemaAutoAddPreservesTokens(root);
			pluginMergeAndOrigins(root);
			pluginDirectoryDiscovery(root);
			pluginPathResolution(root);
			agentColorConfig(root);
			globalLoadAndUpdate(root);
			legacyGlobalTomlMigration(root);
			localUpdateWritesConfigJson(root);
			legacyToolsMigration(root);
			finalizationEnvFlags(root);
			managedConfig(root);
			dependencyBootstrap(root);
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
		final originalFetch = SmokeFetchStub.installConfigRemote();
		try {
			final project = directory(root, "remote-project");
			write(project, "opencode.json", '{"model":"project/model","mcp":{"jira":{"type":"remote","url":"https://jira.example.com/mcp","enabled":true}}}');
			final env:ConfigEnv = cast {};
			final accountConfig = accountRemoteConfig();
			final config = @:await ConfigLoader.loadProjectWithRemoteSources(project,
				[{url: "https://example.com/", key: "TEST_TOKEN", token: "remote-token"}], [
				{url: "https://control.example.com/", token: "st_test_token", config: accountConfig}
			], {defaultUsername: "fixture-user", worktree: project, env: env});

			eq(SmokeFetchStub.configFetchedUrl(), "https://example.com/.well-known/opencode", "remote well-known URL normalized");
			eq(config.username, "remote-token", "remote well-known env token substitution");
			final jira:RemoteMcpEntry = cast Reflect.field(config.mcp, "jira");
			eq(jira.enabled, true, "project config overrides remote well-known config");
			eq(config.model, "account/model", "account config overrides project config");
			final providers = require(config.provider, "account provider map");
			final provider = require(providers.get("opencode"), "account provider config");
			final options = require(provider.options, "account provider options");
			eq(ProviderOptionAccess.string(options, "apiKey", null), "st_test_token", "account config resolves token env template");
			await(accountServiceRemoteConfig(root, env));
			await(accountServiceNoActiveFallback(root));
			await(accountServiceFailureFallback(root));
			SmokeFetchStub.restore(originalFetch);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			SmokeFetchStub.restore(originalFetch);
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function accountRemoteConfig():genes.ts.UnknownRecord {
		final options = new DynamicAccess<OpenConfigValue>();
		options.set("apiKey", Unknown.fromBoundary("{env:OPENCODE_CONSOLE_TOKEN}"));
		final opencode = new DynamicAccess<OpenConfigValue>();
		opencode.set("options", Unknown.fromBoundary(options));
		final provider = new DynamicAccess<OpenConfigValue>();
		provider.set("opencode", Unknown.fromBoundary(opencode));
		final config = new DynamicAccess<OpenConfigValue>();
		config.set("provider", Unknown.fromBoundary(provider));
		config.set("model", Unknown.fromBoundary("account/model"));
		return require(UnknownNarrow.record(Unknown.fromBoundary(config)), "account remote config record");
	}

	@:async
	static function accountServiceRemoteConfig(root:String, env:ConfigEnv):Promise<Void> {
		final project = directory(root, "account-service-project");
		write(project, "opencode.json", '{"model":"project/model"}');
		var seenAuth:Null<String> = null;
		var seenOrg:Null<String> = null;
		var refreshCalls = 0;
		final fixture = accountService(root, "account-service", request -> {
			if (request.url == "https://control.example.com/auth/device/token") {
				refreshCalls++;
				return accountResponse(200, {
					access_token: "st_test_token",
					refresh_token: "rt_new",
					expires_in: 600,
				});
			}
			if (request.url == "https://control.example.com/api/config") {
				seenAuth = header(request, "authorization");
				seenOrg = header(request, "x-org-id");
				return accountResponse(200, {
					config: {
						provider: {
							opencode: {
								options: {
									apiKey: "{env:OPENCODE_CONSOLE_TOKEN}"
								}
							}
						},
						model: "account-service/model",
					}
				});
			}
			return accountResponse(404, {});
		});
		fixture.repo.persistAccount({
			id: AccountID.make("account-1"),
			email: "user@example.com",
			url: "https://control.example.com",
			accessToken: AccessToken.make("at_old"),
			refreshToken: RefreshToken.make("rt_old"),
			expiry: Date.now().getTime() - 1000,
			orgID: OrgID.make("org-1"),
		});
		final config = @:await ConfigLoader.loadProjectWithAccountService(project, fixture.service,
			{defaultUsername: "fixture-user", worktree: project, env: env});
		eq(refreshCalls, 1, "account service config refresh count");
		eq(seenAuth, "Bearer st_test_token", "account service config auth header");
		eq(seenOrg, "org-1", "account service config org header");
		eq(config.model, "account-service/model", "account service config overrides project");
		final providers = require(config.provider, "account service provider map");
		final provider = require(providers.get("opencode"), "account service provider config");
		final options = require(provider.options, "account service provider options");
		eq(ProviderOptionAccess.string(options, "apiKey", null), "st_test_token", "account service config resolves token env template");
		fixture.repo.close();
	}

	@:async
	static function accountServiceNoActiveFallback(root:String):Promise<Void> {
		final project = directory(root, "account-service-no-active");
		write(project, "opencode.json", '{"model":"project/model"}');
		final calls:Array<AccountHttpRequest> = [];
		final fixture = accountService(root, "account-service-no-active", request -> {
			calls.push(request);
			return accountResponse(500, {});
		});
		final config = @:await ConfigLoader.loadProjectWithAccountService(project, fixture.service, {defaultUsername: "fixture-user", worktree: project});
		eq(config.model, "project/model", "account service no active fallback model");
		eq(calls.length, 0, "account service no active request count");
		fixture.repo.close();
	}

	@:async
	static function accountServiceFailureFallback(root:String):Promise<Void> {
		final project = directory(root, "account-service-failure");
		write(project, "opencode.json", '{"model":"project/model"}');
		final calls:Array<AccountHttpRequest> = [];
		final fixture = accountService(root, "account-service-failure", request -> {
			calls.push(request);
			return accountResponse(500, {error: "server_error"});
		});
		fixture.repo.persistAccount({
			id: AccountID.make("account-failure"),
			email: "failure@example.com",
			url: "https://control.example.com",
			accessToken: AccessToken.make("at_old"),
			refreshToken: RefreshToken.make("rt_old"),
			expiry: Date.now().getTime() - 1000,
			orgID: OrgID.make("org-1"),
		});
		final config = @:await ConfigLoader.loadProjectWithAccountService(project, fixture.service, {defaultUsername: "fixture-user", worktree: project});
		eq(config.model, "project/model", "account service failure fallback model");
		eq(calls.length, 1, "account service failure request count");
		fixture.repo.close();
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
		eq(ConfigVariable.substitute("user={env:USER_NAME};empty={env:EMPTY_ENV};missing={env:MISSING_ENV}",
			{
				dir: dir,
				env: {
					USER_NAME: "env-user",
					EMPTY_ENV: null
				}
			}), "user=env-user;empty=;missing=", "env substitution narrows provided env map");
	}

	static function legacyTuiKeys(root:String):Void {
		final dir = directory(root, "legacy-tui");
		write(dir, "opencode.json", '{"model":"test/model","theme":"legacy","tui":{"scroll_speed":4},"keybinds":{"x":"y"}}');
		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		eq(config.model, "test/model", "legacy tui stripped model preserved");
	}

	static function tuiConfig(root:String):Void {
		final global = directory(root, "tui-global");
		final project = directory(root, "tui-project");
		final opencode = directory(project, ".opencode");
		write(global, "tui.json",
			'{"theme":"global","keybinds":{"app_exit":"ctrl+q"},"plugin":[["shared-plugin@1.0.0",{"source":"global"}],"global-only@1.0.0"],"plugin_enabled":{"demo.plugin":true}}');
		write(project, "tui.json",
			'{"theme":"project","keybinds":{"theme_list":"ctrl+k"},"plugin":[["shared-plugin@2.0.0",{"source":"local","enabled":true}],"local-only@1.0.0"],"plugin_enabled":{"demo.plugin":false,"local.plugin":true}}');
		write(opencode, "tui.json", '{"diff_style":"stacked"}');

		final merged = ConfigTui.load(project, {globalConfigDir: global, worktree: project});
		eq(merged.theme, "project", "tui project overrides global theme");
		eq(merged.diffStyle, "stacked", ".opencode tui overrides project diff style");
		eq(merged.keybinds.get("app_exit"), "ctrl+q", "tui global keybind preserved");
		eq(merged.keybinds.get("theme_list"), "ctrl+k", "tui project keybind merged");
		eq(merged.plugin.map(ConfigPlugin.specifier).join(","), "global-only@1.0.0,shared-plugin@2.0.0,local-only@1.0.0",
			"tui plugin deduplicates by package with local precedence");
		eq(merged.pluginOrigins[0].scope, PluginScopeGlobal, "tui global plugin origin scope");
		eq(merged.pluginOrigins[1].scope, PluginScopeLocal, "tui local plugin origin scope");
		eq(ConfigPlugin.stringOption(merged.pluginOrigins[1].spec, "source"), "local", "tui tuple plugin options preserved");
		eq(ConfigPlugin.boolOption(merged.pluginOrigins[1].spec, "enabled"), true, "tui tuple plugin boolean option preserved");
		eq(merged.pluginEnabled.get("demo.plugin"), false, "tui plugin_enabled local override");
		eq(merged.pluginEnabled.get("local.plugin"), true, "tui plugin_enabled local value");

		final flat = directory(root, "tui-flat");
		write(flat, "tui.json", '{"diff_style":"auto","tui":{"diff_style":"stacked","scroll_speed":3}}');
		final flattened = ConfigTui.load(flat, {globalConfigDir: directory(root, "tui-empty-global"), worktree: flat});
		eq(flattened.diffStyle, "auto", "tui top-level field wins over nested tui field");
		eq(flattened.scrollSpeed, 3.0, "tui nested field flattened");

		final windowsDefault = directory(root, "tui-windows-default");
		final windowsDefaultConfig = ConfigTui.load(windowsDefault, {
			globalConfigDir: directory(root, "tui-empty-windows-default-global"),
			worktree: windowsDefault,
			platform: "win32",
		});
		eq(windowsDefaultConfig.keybinds.get("terminal_suspend"), "none", "tui Windows disables terminal suspend");
		eq(windowsDefaultConfig.keybinds.get("input_undo"), "ctrl+z,ctrl+-,super+z", "tui Windows default input undo");

		final windowsExplicit = directory(root, "tui-windows-explicit");
		write(windowsExplicit, "tui.json", '{"keybinds":{"terminal_suspend":"alt+z","input_undo":"ctrl+y"}}');
		final windowsExplicitConfig = ConfigTui.load(windowsExplicit, {
			globalConfigDir: directory(root, "tui-empty-windows-explicit-global"),
			worktree: windowsExplicit,
			platform: "win32",
		});
		eq(windowsExplicitConfig.keybinds.get("terminal_suspend"), "none", "tui Windows ignores terminal suspend override");
		eq(windowsExplicitConfig.keybinds.get("input_undo"), "ctrl+y", "tui Windows preserves explicit input undo");

		final migrationRoot = directory(root, "tui-migration");
		final nested = directory(migrationRoot, "apps/client");
		write(migrationRoot, "opencode.json", '{"theme":"root-theme"}');
		write(nested, "opencode.json",
			'{"model":"test/model","theme":"nested-theme","tui":{"scroll_speed":2,"diff_style":"stacked","ignored":true},"keybinds":{"app_exit":"ctrl+x"}}');
		final migrated = ConfigTui.load(nested, {globalConfigDir: directory(root, "tui-empty-migration-global"), worktree: migrationRoot});
		eq(migrated.theme, "nested-theme", "tui legacy migration preserves nearest theme");
		eq(migrated.scrollSpeed, 2.0, "tui legacy migration moves nested scroll speed");
		eq(migrated.keybinds.get("app_exit"), "ctrl+x", "tui legacy migration moves keybinds");
		eq(Fs.existsSync(NodePath.join(migrationRoot, "opencode.json.tui-migration.bak")), true, "tui root migration backup");
		eq(Fs.existsSync(NodePath.join(nested, "opencode.json.tui-migration.bak")), true, "tui nested migration backup");
		eq(Fs.existsSync(NodePath.join(migrationRoot, "tui.json")), true, "tui root migration writes tui.json");
		eq(Fs.existsSync(NodePath.join(nested, "tui.json")), true, "tui nested migration writes tui.json");
		final stripped = Fs.readFileSync(NodePath.join(nested, "opencode.json"), "utf8");
		eq(stripped.indexOf("theme") == -1 && stripped.indexOf("tui") == -1 && stripped.indexOf("keybinds") == -1, true,
			"tui legacy migration strips moved keys from source");
		eq(Fs.readFileSync(NodePath.join(nested, "tui.json"), "utf8").indexOf("ignored") == -1, true, "tui legacy migration drops unknown nested keys");

		final readonlyDir = directory(root, "tui-readonly-migration");
		final readonlySource = NodePath.join(readonlyDir, "opencode.json");
		write(readonlyDir, "opencode.json", '{"theme":"readonly-theme","tui":{"scroll_speed":5}}');
		Fs.chmodSync(readonlySource, 0x124);
		try {
			final readonly = ConfigTui.load(readonlyDir, {globalConfigDir: directory(root, "tui-empty-readonly-global"), worktree: readonlyDir});
			eq(readonly.theme, "readonly-theme", "tui readonly migration loads generated tui config");
			eq(readonly.scrollSpeed, 5.0, "tui readonly migration moves nested scroll speed");
			eq(Fs.existsSync(NodePath.join(readonlyDir, "tui.json")), true, "tui readonly migration writes tui.json");
			final preserved = Fs.readFileSync(readonlySource, "utf8");
			eq(preserved.indexOf("readonly-theme") != -1, true, "tui readonly migration keeps source when strip fails");
			eq(preserved.indexOf("scroll_speed") != -1, true, "tui readonly migration keeps nested source when strip fails");
		} catch (error:haxe.Exception) {
			Fs.chmodSync(readonlySource, 0x1a4);
			throw error;
		}
		Fs.chmodSync(readonlySource, 0x1a4);

		final envDir = directory(root, "tui-env");
		write(envDir, "theme.txt", "env-theme");
		write(envDir, "key.txt", "ctrl+e");
		write(envDir, "custom-tui.json", '{"theme":"{file:theme.txt}","keybinds":{"app_exit":"{file:key.txt}"}}');
		final original = NodeProcess.envValue("OPENCODE_TUI_CONFIG");
		NodeProcess.setEnv("OPENCODE_TUI_CONFIG", NodePath.join(envDir, "custom-tui.json"));
		try {
			final envConfig = ConfigTui.load(envDir, {globalConfigDir: directory(root, "tui-empty-env-global"), worktree: envDir});
			eq(envConfig.theme, "env-theme", "tui env config file substitution");
			eq(envConfig.keybinds.get("app_exit"), "ctrl+e", "tui env config keybind substitution");

			final envProject = directory(root, "tui-env-project");
			write(envProject, "custom-tui.json", '{"theme":"custom-env"}');
			write(envProject, "tui.json", '{"theme":"project-tui"}');
			NodeProcess.setEnv("OPENCODE_TUI_CONFIG", NodePath.join(envProject, "custom-tui.json"));
			eq(ConfigTui.load(envProject, {globalConfigDir: directory(root, "tui-empty-env-project-global"), worktree: envProject}).theme, "project-tui",
				"tui project file overrides OPENCODE_TUI_CONFIG");
		} catch (error:haxe.Exception) {
			restoreEnv("OPENCODE_TUI_CONFIG", original);
			throw error;
		}
		restoreEnv("OPENCODE_TUI_CONFIG", original);
	}

	static function lspConfigRefinement(root:String):Void {
		final enabledDir = directory(root, "lsp-enabled");
		write(enabledDir, "opencode.json", '{"lsp":true}');
		eq(ConfigLoader.loadProject(enabledDir, {defaultUsername: "fixture-user"}).lsp, true, "lsp true toggle");
		final disabledDir = directory(root, "lsp-disabled");
		write(disabledDir, "opencode.json", '{"lsp":false}');
		eq(ConfigLoader.loadProject(disabledDir, {defaultUsername: "fixture-user"}).lsp, false, "lsp false toggle");

		final builtinDir = directory(root, "lsp-builtin");
		write(builtinDir, "opencode.json", '{"lsp":{"typescript":{"command":["typescript-language-server","--stdio"]}}}');
		final builtin = Unknown.fromBoundary(ConfigLoader.loadProject(builtinDir, {defaultUsername: "fixture-user"}).lsp);
		eq(ConfigLsp.hasServerField(builtin, "typescript", "extensions"), false, "builtin lsp can omit extensions");

		final customDir = directory(root, "lsp-custom");
		write(customDir, "opencode.json", '{"lsp":{"my-lsp":{"command":["my-lsp-bin"],"extensions":[".ml"]}}}');
		final custom = Unknown.fromBoundary(ConfigLoader.loadProject(customDir, {defaultUsername: "fixture-user"}).lsp);
		eq(require(ConfigLsp.extensions(custom, "my-lsp"), "custom lsp extensions")[0], ".ml", "custom lsp extensions");

		final disabledCustomDir = directory(root, "lsp-disabled-custom");
		write(disabledCustomDir, "opencode.json", '{"lsp":{"my-lsp":{"disabled":true}}}');
		eq(ConfigLsp.disabled(Unknown.fromBoundary(ConfigLoader.loadProject(disabledCustomDir, {defaultUsername: "fixture-user"}).lsp), "my-lsp"), true,
			"disabled custom lsp omits extensions");

		final mixedDir = directory(root, "lsp-mixed");
		write(mixedDir, "opencode.json",
			'{"lsp":{"typescript":{"command":["typescript-language-server","--stdio"]},"my-lsp":{"command":["my-lsp-bin"],"extensions":[".ml"]}}}');
		eq(ConfigLsp.hasServer(Unknown.fromBoundary(ConfigLoader.loadProject(mixedDir, {defaultUsername: "fixture-user"}).lsp), "typescript"), true,
			"mixed lsp builtin");

		final emptyExtensionsDir = directory(root, "lsp-empty-extensions");
		write(emptyExtensionsDir, "opencode.json", '{"lsp":{"my-lsp":{"command":["my-lsp-bin"],"extensions":[]}}}');
		eq(require(ConfigLsp.extensions(Unknown.fromBoundary(ConfigLoader.loadProject(emptyExtensionsDir, {defaultUsername: "fixture-user"}).lsp), "my-lsp"),
			"empty lsp extensions").length,
			0, "empty lsp extensions current behavior");

		expectFailure(() -> {
			final invalidDir = directory(root, "lsp-invalid");
			write(invalidDir, "opencode.json", '{"lsp":{"my-lsp":{"command":["my-lsp-bin"]}}}');
			ConfigLoader.loadProject(invalidDir, {defaultUsername: "fixture-user"});
		}, "custom lsp without extensions", function(failure) {
			return switch failure {
				case InvalidError(_, issues): issues.indexOf("For custom LSP servers, 'extensions' array is required.") != -1;
				case _: false;
			}
		});

		expectFailure(() -> {
			final invalidMixedDir = directory(root, "lsp-invalid-mixed");
			write(invalidMixedDir, "opencode.json",
				'{"lsp":{"typescript":{"command":["typescript-language-server","--stdio"]},"my-lsp":{"command":["my-lsp-bin"]}}}');
			ConfigLoader.loadProject(invalidMixedDir, {defaultUsername: "fixture-user"});
		}, "mixed custom lsp without extensions", function(failure) {
			return switch failure {
				case InvalidError(_, issues): issues.indexOf("For custom LSP servers, 'extensions' array is required.") != -1;
				case _: false;
			}
		});

		expectFailure(() -> {
			final invalidExtensionsDir = directory(root, "lsp-invalid-extensions");
			write(invalidExtensionsDir, "opencode.json", '{"lsp":{"my-lsp":{"command":["my-lsp-bin"],"extensions":"ml"}}}');
			ConfigLoader.loadProject(invalidExtensionsDir, {defaultUsername: "fixture-user"});
		}, "custom lsp extensions must be array", function(failure) {
			return switch failure {
				case InvalidError(_, issues): issues.indexOf("lsp.my-lsp.extensions: expected array") != -1;
				case _: false;
			}
		});

		expectFailure(() -> {
			final invalidExtensionItemDir = directory(root, "lsp-invalid-extension-item");
			write(invalidExtensionItemDir, "opencode.json", '{"lsp":{"my-lsp":{"command":["my-lsp-bin"],"extensions":[".ml",1]}}}');
			ConfigLoader.loadProject(invalidExtensionItemDir, {defaultUsername: "fixture-user"});
		}, "custom lsp extensions must contain strings", function(failure) {
			return switch failure {
				case InvalidError(_, issues): issues.indexOf("lsp.my-lsp.extensions: expected string entries") != -1;
				case _: false;
			}
		});
	}

	static function markdownParsing():Void {
		final refs = ConfigMarkdown.files('This is a @valid/path/to/a/file and it should also match at
  the beginning of a line:

  @another-valid/path/to/a/file

  but this is not:

     - Adds a "Co-authored-by:" footer which clarifies which AI agent
       helped create this commit, using an appropriate `noreply@...`
       or `noreply@anthropic.com` email address.

  We also need to deal with files followed by @commas, ones
  with @file-extensions.md, even @multiple.extensions.bak,
  hidden directories like @.config/ or files like @.bashrc
  and ones at the end of a sentence like @foo.md.

  Also shouldn\'t forget @/absolute/paths.txt with and @/without/extensions,
  as well as @~/home-files and @~/paths/under/home.txt.

  If the reference is `@quoted/in/backticks` then it shouldn\'t match at all.');
		eq(refs.length, 12, "markdown file reference count");
		eq(refs[0][1], "valid/path/to/a/file", "markdown file reference first");
		eq(refs[1][1], "another-valid/path/to/a/file", "markdown file reference line start");
		eq(refs[2][1], "commas", "markdown file reference strips comma");
		eq(refs[3][1], "file-extensions.md", "markdown file reference extension");
		eq(refs[4][1], "multiple.extensions.bak", "markdown file reference multiple extensions");
		eq(refs[5][1], ".config/", "markdown file reference hidden dir");
		eq(refs[6][1], ".bashrc", "markdown file reference hidden file");
		eq(refs[7][1], "foo.md", "markdown file reference strips period");
		eq(refs[8][1], "/absolute/paths.txt", "markdown file reference absolute");
		eq(refs[9][1], "/without/extensions", "markdown file reference absolute no extension");
		eq(refs[10][1], "~/home-files", "markdown file reference home");
		eq(refs[11][1], "~/paths/under/home.txt", "markdown file reference home nested");
		eq(ConfigMarkdown.files("This `@should/not/match` should be ignored").length, 0, "markdown backtick reference ignored");
		eq(ConfigMarkdown.files("Contact user@example.com for help").length, 0, "markdown email ignored");

		final parsed = ConfigMarkdown.parseText('---
description: "This is a description wrapped in quotes"
# field: this is a commented out field that should be ignored
occupation: This man has the following occupation: Software Engineer
title: \'Hello World\'
name: John "Doe"

family: He has no \'family\'
summary: >
  This is a summary
url: https://example.com:8080/path?query=value
time: The time is 12:30:00 PM
nested: First: Second: Third: Fourth
quoted_colon: "Already quoted: no change needed"
single_quoted_colon: \'Single quoted: also fine\'
mixed: He said "hello: world" and then left
empty:
dollar: Use $\' and $& for special patterns
---

Content that should not be parsed:

fake_field: this is not yaml
another: neither is this
time: 10:30:00 AM
url: https://should-not-be-parsed.com:3000

The above lines look like YAML but are just content.', "frontmatter.md");
		eq(markdownString(parsed, "description"), "This is a description wrapped in quotes", "frontmatter description");
		eq(markdownString(parsed, "occupation"), "This man has the following occupation: Software Engineer", "frontmatter colon value");
		eq(markdownString(parsed, "title"), "Hello World", "frontmatter single quote");
		eq(markdownString(parsed, "name"), 'John "Doe"', "frontmatter embedded quote");
		eq(markdownString(parsed, "family"), "He has no 'family'", "frontmatter embedded single quote");
		eq(markdownString(parsed, "summary"), "This is a summary\n", "frontmatter folded summary");
		eq(parsed.data.exists("field"), false, "frontmatter comment ignored");
		eq(markdownString(parsed, "url"), "https://example.com:8080/path?query=value", "frontmatter url with port");
		eq(markdownString(parsed, "time"), "The time is 12:30:00 PM", "frontmatter time colons");
		eq(markdownString(parsed, "nested"), "First: Second: Third: Fourth", "frontmatter multiple colons");
		eq(markdownString(parsed, "quoted_colon"), "Already quoted: no change needed", "frontmatter quoted colon");
		eq(markdownString(parsed, "single_quoted_colon"), "Single quoted: also fine", "frontmatter single quoted colon");
		eq(markdownString(parsed, "mixed"), 'He said "hello: world" and then left', "frontmatter mixed quotes");
		eq(UnknownNarrow.isNull(parsed.data.get("empty")), true, "frontmatter empty value");
		eq(markdownString(parsed, "dollar"), "Use $' and $& for special patterns", "frontmatter dollar literals");
		eq(parsed.data.exists("fake_field"), false, "frontmatter content fake field ignored");
		contains(parsed.content, "fake_field: this is not yaml", "frontmatter content preserved");
		contains(parsed.content, "url: https://should-not-be-parsed.com:3000", "frontmatter url content preserved");

		final empty = ConfigMarkdown.parseText("---
---

Content", "empty-frontmatter.md");
		eq(empty.data.keys().length, 0, "empty frontmatter data");
		eq(StringTools.trim(empty.content), "Content", "empty frontmatter content");

		final none = ConfigMarkdown.parseText("Content", "no-frontmatter.md");
		eq(none.data.keys().length, 0, "no frontmatter data");
		eq(StringTools.trim(none.content), "Content", "no frontmatter content");

		final markdownHeader = ConfigMarkdown.parseText("# Response Formatting Requirements\n\nAlways structure your responses using clear markdown formatting:",
			"markdown-header.md");
		eq(markdownHeader.data.keys().length, 0, "markdown header data");
		contains(markdownHeader.content, "# Response Formatting Requirements", "markdown header content");

		final weird = ConfigMarkdown.parseText('---
description: General coding and planning agent
mode: subagent
model: synthetic/hf:zai-org/GLM-4.7
tools:
  write: true
  read: true
  edit: true
stuff: >
  This is some stuff
---

Strictly follow da rules', "weird-model-id.md");
		eq(markdownString(weird, "description"), "General coding and planning agent", "weird model description");
		eq(markdownString(weird, "mode"), "subagent", "weird model mode");
		eq(markdownString(weird, "model"), "synthetic/hf:zai-org/GLM-4.7", "weird model id");
		final tools = require(UnknownNarrow.record(weird.data.get("tools")), "weird model tools");
		eq(UnknownNarrow.bool(tools.get("write")), true, "weird model write tool");
		eq(UnknownNarrow.bool(tools.get("read")), true, "weird model read tool");
		eq(markdownString(weird, "stuff"), "This is some stuff\n", "weird model folded stuff");
		eq(StringTools.trim(weird.content), "Strictly follow da rules", "weird model content");
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
		eq(ConfigPlugin.stringOption(shared.spec, "source"), "local", "plugin tuple options preserved");
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

	static function pluginPathResolution(root:String):Void {
		final worktree = directory(root, "plugin-resolution");
		final project = directory(worktree, "project");
		final opencodeDir = directory(project, ".opencode");
		write(opencodeDir, "plugin.ts", "export default {}");

		final packageDir = directory(opencodeDir, "package-plugin");
		write(packageDir, "package.json", '{"name":"package-plugin"}');
		write(packageDir, "index.ts", "export default {}");

		final indexDir = directory(opencodeDir, "index-plugin");
		write(indexDir, "index.ts", "export default {}");

		write(opencodeDir, "opencode.json",
			'{"plugin":["oh-my-opencode@2.4.3","@scope/pkg","./plugin.ts","./package-plugin",["./index-plugin",{"source":"tuple"}]]}');

		final config = ConfigLoader.loadProject(project, {defaultUsername: "fixture-user", worktree: worktree});
		final fileUrl = Url.pathToFileURL(NodePath.join(opencodeDir, "plugin.ts")).href;
		final packageUrl = Url.pathToFileURL(packageDir).href;
		final indexUrl = Url.pathToFileURL(NodePath.join(indexDir, "index.ts")).href;
		final names = [for (plugin in config.plugin) ConfigPlugin.specifier(plugin)];
		eq(names.indexOf("oh-my-opencode@2.4.3") != -1, true, "plugin package spec preserved");
		eq(names.indexOf("@scope/pkg") != -1, true, "plugin scoped package spec preserved");
		eq(names.indexOf(fileUrl) != -1, true, "relative plugin file resolved");
		eq(names.indexOf(packageUrl) != -1, true, "plugin package directory resolved");
		eq(names.indexOf(indexUrl) != -1, true, "plugin directory index fallback resolved");

		final tuple = require(findOrigin(config.pluginOrigins, indexUrl), "resolved tuple plugin origin");
		eq(ConfigPlugin.stringOption(tuple.spec, "source"), "tuple", "resolved plugin tuple options preserved");

		final option = new DynamicAccess<PluginOptionValue>();
		option.set("source", Unknown.fromBoundary("direct"));
		final direct = ConfigPlugin.resolveSpec({specifier: "./plugin.ts", options: option}, NodePath.join(opencodeDir, "opencode.json"));
		eq(ConfigPlugin.specifier(direct), fileUrl, "direct plugin resolver");
		eq(ConfigPlugin.stringOption(direct, "source"), "direct", "direct resolver preserves options");
	}

	static function agentColorConfig(root:String):Void {
		final dir = directory(root, "agent-color");
		write(dir, "opencode.json", '{"' + "$" + 'schema":"${ConfigInfo.DEFAULT_SCHEMA}","agent":{"build":{"color":"#FFA500"},"plan":{"color":"primary"}}}');
		final config = ConfigLoader.loadProject(dir, {defaultUsername: "fixture-user"});
		final agents = require(config.agent, "agent color map");
		eq(require(agents.get("build"), "build agent color").color, "#FFA500", "project config hex agent color");
		eq(require(agents.get("plan"), "plan agent color").color, "primary", "project config theme agent color");

		final runtime = new AgentRuntime(config);
		eq(require(runtime.get("build"), "runtime build agent").color, "#FFA500", "agent runtime hex color");
		eq(require(runtime.get("plan"), "runtime plan agent").color, "primary", "agent runtime theme color");
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
		final permission = new DynamicAccess<PermissionConfigValue>();
		permission.set("bash", "allow");
		patch.permission = permission;

		final next = ConfigWriter.updateLocal(dir, patch);
		eq(next.model, "new/model", "local update return model");
		eq(require(next.permission, "local update permission").get("bash"), "allow", "local update nested permission");

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

	static function managedConfig(root:String):Void {
		final dir = directory(root, "managed-config");
		write(dir, "opencode.json", '{"model":"user/model","share":"auto","enabled_providers":["openai"],"server":{"hostname":"0.0.0.0"}}');
		final managedText = ConfigManaged.parseManagedPlist('{
  "PayloadDisplayName": "OpenCode Managed",
  "PayloadIdentifier": "ai.opencode.managed.test",
  "PayloadType": "ai.opencode.managed",
  "PayloadUUID": "AAAA-BBBB-CCCC",
  "PayloadVersion": 1,
  "_manualProfile": true,
  "model": "managed/model",
  "share": "disabled",
  "enabled_providers": ["anthropic", "google"],
  "server": {"hostname": "127.0.0.1", "mdns": false},
  "permission": {"*": "ask", "grep": "allow"}
}');
		final config = ConfigLoader.loadProject(dir, {
			defaultUsername: "fixture-user",
			managedConfig: {text: managedText, source: "test:mobileconfig"},
		});

		eq(config.model, "managed/model", "managed config overrides model");
		eq(config.share, ShareDisabled, "managed config overrides share");
		eq(config.enabledProviders.join(","), "anthropic,google", "managed enabled providers");
		eq(config.server.hostname, "127.0.0.1", "managed server hostname");
		eq(config.server.mdns, false, "managed server mdns");
		final permission = require(config.permission, "managed permission");
		eq(permission.get("*"), "ask", "managed wildcard permission");
		eq(permission.get("grep"), "allow", "managed grep permission");
		contains(managedText, '"model"', "managed config field preserved");
		notContains(managedText, "PayloadDisplayName", "managed display metadata stripped");
		notContains(managedText, "PayloadUUID", "managed metadata stripped");
		notContains(managedText, "_manualProfile", "managed manual profile stripped");
	}

	static function dependencyBootstrap(root:String):Void {
		final fixture = configNpmFixture(NodePath.join(root, "config-npm-cache"));
		final dir = directory(root, "dependency-bootstrap");
		final success = ConfigDependencyRuntime.bootstrapPluginDependency(fixture.deps, dir, "1.2.3", false);
		eq(success.installed, true, "dependency bootstrap success");
		eq(success.error, null, "dependency bootstrap success error");
		eq(Fs.readFileSync(NodePath.join(dir, ".gitignore"), "utf8"), "node_modules\npackage.json\npackage-lock.json\nbun.lock\n.gitignore",
			"dependency bootstrap gitignore");
		eq(fixture.requests[0].dir, dir, "dependency bootstrap install dir");
		eq(fixture.requests[0].add.join(","), "@opencode-ai/plugin@1.2.3", "dependency bootstrap plugin version");

		final localDir = directory(root, "dependency-bootstrap-local");
		ConfigDependencyRuntime.bootstrapPluginDependency(fixture.deps, localDir, "1.2.3", true);
		eq(fixture.requests[1].add.join(","), "@opencode-ai/plugin", "dependency bootstrap local omits version");

		final keepDir = directory(root, "dependency-bootstrap-keep-gitignore");
		write(keepDir, ".gitignore", "custom\n");
		ConfigDependencyRuntime.bootstrapPluginDependency(fixture.deps, keepDir, "1.2.3", false);
		eq(Fs.readFileSync(NodePath.join(keepDir, ".gitignore"), "utf8"), "custom\n", "dependency bootstrap preserves gitignore");

		final failing = configNpmFixture(NodePath.join(root, "config-npm-failure"));
		failing.fail[0] = true;
		final failed = ConfigDependencyRuntime.bootstrapPluginDependency(failing.deps, directory(root, "dependency-bootstrap-failure"), "1.2.3", false);
		eq(failed.installed, false, "dependency bootstrap failure");
		contains(failed.error, "reify failed", "dependency bootstrap failure error");
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

	static function configNpmFixture(root:String):ConfigNpmFixture {
		final requests:Array<NpmReifyRequest> = [];
		final responses = new Map<String, NpmHttpResponse>();
		final fail = [false];
		Fs.mkdirSync(root, {recursive: true});
		return {
			requests: requests,
			responses: responses,
			fail: fail,
			deps: {
				cache: root,
				http: url -> responses.exists(url) ? responses.get(url) : {ok: false, body: ""},
				reify: request -> {
					if (fail[0])
						throw "reify failed";
					requests.push(request);
					Fs.mkdirSync(request.dir, {recursive: true});
					for (spec in request.add) {
						final name = NpmRuntime.packageName(spec);
						Fs.mkdirSync(NodePath.join(NodePath.join(request.dir, "node_modules"), name), {recursive: true});
					}
					return {edges: []};
				},
			},
		};
	}

	static function accountService(root:String, name:String, handler:AccountHttpRequest->Promise<AccountHttpResponse>):{
		final repo:AccountRepo;
		final service:AccountService;
	} {
		final repo = new AccountRepo(NodePath.join(root, name + ".db"));
		return {
			repo: repo,
			service: new AccountService(repo, handler),
		};
	}

	static function accountResponse<T>(status:Int, body:T):Promise<AccountHttpResponse> {
		return Promise.resolve({
			status: status,
			body: Unknown.fromBoundary(body),
		});
	}

	static function header(request:AccountHttpRequest, name:String):Null<String> {
		for (header in request.headers)
			if (header.name == name)
				return header.value;
		return null;
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

	static function restoreEnv(key:String, value:Null<String>):Void {
		if (value == null)
			NodeProcess.unsetEnv(key);
		else
			NodeProcess.setEnv(key, value);
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

	static function markdownString(document:MarkdownDocument, field:String):String {
		final value = UnknownNarrow.string(document.data.get(field));
		return value == null ? "" : value;
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
