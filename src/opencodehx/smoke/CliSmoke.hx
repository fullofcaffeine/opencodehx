package opencodehx.smoke;

import genes.js.Async.await;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.cli.Cli;
import opencodehx.config.ConfigInfo;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.BetterSqlite;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;

class CliSmoke {
	public static function run():Void {
		final help = Cli.run(["--help"]);
		eq(help.exitCode, 0, "help exit");
		eq(help.stdout.indexOf("opencodehx run [message..]") != -1, true, "help mentions run");

		final version = Cli.run(["--version"]);
		eq(version.stdout, BuildInfo.version + "\n", "version output");

		final text = Cli.run(["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."]);
		eq(text.stdout, "Hello from the fake provider.\n", "run text output");

		final json = Cli.run(["run", "--format", "json", "Say", "hello", "from", "the", "fixture."]);
		final parsed:Dynamic = Json.parse(json.stdout);
		eq(Reflect.field(Reflect.field(parsed, "provider"), "id"), "openai", "run json provider");
		eq(Reflect.field(Reflect.field(parsed, "request"), "prompt"), "Say hello from the fixture.", "run json prompt");

		final missing = Cli.run(["run"]);
		eq(missing.exitCode, 1, "missing prompt exit");
		eq(missing.stderr.indexOf("You must provide a message") != -1, true, "missing prompt message");
	}

	@:async
	public static function runAsync():Promise<Void> {
		final text = @:await Cli.runAsync(["run", "--mock-ai-sdk", "Say", "hello", "through", "the", "SDK."]);
		eq(text.exitCode, 0, "async cli exit");
		eq(text.stdout, "Hello from the AI SDK session.\n", "async cli text output");

		final json = @:await Cli.runAsync([
			"run",
			"--mock-ai-sdk",
			"--format",
			"json",
			"Say",
			"hello",
			"through",
			"the",
			"SDK."
		]);
		final parsed:Dynamic = Json.parse(json.stdout);
		eq(Reflect.field(Reflect.field(parsed, "provider"), "id"), "openai", "async cli json provider");
		eq(Reflect.field(Reflect.field(parsed, "request"), "prompt"), "Say hello through the SDK.", "async cli json prompt");
		final events:Array<Dynamic> = Reflect.field(parsed, "events");
		eq(Reflect.field(events[0], "type"), "start", "async cli start event");
		eq(Reflect.field(events[1], "text"), "Hello ", "async cli first delta");

		final unsupported = @:await Cli.runAsync(["run", "--mock-ai-sdk", "--model", "anthropic/claude", "Hello"]);
		eq(unsupported.exitCode, 1, "async cli unsupported model exit");
		eq(unsupported.stderr.indexOf("mock AI SDK harness") != -1, true, "async cli unsupported model message");

		final liveMissingModel = @:await Cli.runAsync(["run", "--live-ai-sdk", "Hello"]);
		eq(liveMissingModel.exitCode, 1, "live cli missing model exit");
		eq(liveMissingModel.stderr.indexOf("require --model") != -1, true, "live cli missing model message");

		final liveMissingProvider = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "missing-provider/model", "Hello"]);
		eq(liveMissingProvider.exitCode, 1, "live cli missing provider exit");
		eq(liveMissingProvider.stderr.indexOf("Provider not available") != -1, true, "live cli missing provider message");

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cli-"));
		var originalXdg:Null<String> = null;
		var originalXdgData:Null<String> = null;
		var originalCloudflareAccount:Null<String> = null;
		var originalCloudflareGateway:Null<String> = null;
		var originalCloudflareToken:Null<String> = null;
		var originalCloudflareAiGatewayToken:Null<String> = null;
		final originalFetch = SmokeFetchStub.installCliRemote();
		try {
			final xdg = NodePath.join(root, "xdg");
			final global = NodePath.join(xdg, "opencode");
			final project = NodePath.join(root, "project");
			Fs.mkdirSync(global, {recursive: true});
			Fs.mkdirSync(project, {recursive: true});
			final xdgData = NodePath.join(root, "data");
			final authDir = NodePath.join(xdgData, "opencode");
			Fs.mkdirSync(authDir, {recursive: true});
			Fs.writeFileSync(NodePath.join(global, "opencode.json"),
				'{"' + "$" +
				'schema":"${ConfigInfo.DEFAULT_SCHEMA}","provider":{"global-live":{"npm":"@ai-sdk/openai-compatible","name":"Global Live","options":{"baseURL":"https://global.example.com","apiKey":"global-key"},"models":{"chat":{"name":"Chat"}}}}}');
			Fs.writeFileSync(NodePath.join(project, "opencode.json"),
				'{"' + "$" +
				'schema":"${ConfigInfo.DEFAULT_SCHEMA}","provider":{"project-live":{"npm":"@ai-sdk/openai-compatible","name":"Project Live","options":{"baseURL":"https://project.example.com","apiKey":"project-key"},"models":{"chat":{"name":"Chat"}}}}}');
			Fs.writeFileSync(NodePath.join(authDir, "auth.json"),
				'{"cloudflare-ai-gateway":{"type":"api","key":"auth-cf-token","metadata":{"accountId":"auth-account","gatewayId":"auth-gateway"}},' +
				'"https://remote.example.com/":{"type":"wellknown","key":"LIVE_REMOTE_TOKEN","token":"remote-live-token"}}');
			originalXdg = NodeProcess.envValue("XDG_CONFIG_HOME");
			originalXdgData = NodeProcess.envValue("XDG_DATA_HOME");
			originalCloudflareAccount = NodeProcess.envValue("CLOUDFLARE_ACCOUNT_ID");
			originalCloudflareGateway = NodeProcess.envValue("CLOUDFLARE_GATEWAY_ID");
			originalCloudflareToken = NodeProcess.envValue("CLOUDFLARE_API_TOKEN");
			originalCloudflareAiGatewayToken = NodeProcess.envValue("CF_AIG_TOKEN");
			NodeProcess.setEnv("XDG_CONFIG_HOME", xdg);
			NodeProcess.setEnv("XDG_DATA_HOME", xdgData);
			NodeProcess.unsetEnv("CLOUDFLARE_ACCOUNT_ID");
			NodeProcess.unsetEnv("CLOUDFLARE_GATEWAY_ID");
			NodeProcess.unsetEnv("CLOUDFLARE_API_TOKEN");
			NodeProcess.unsetEnv("CF_AIG_TOKEN");
			final globalLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "global-live/missing", "Hello"]);
			eq(globalLoaded.exitCode, 1, "live cli global config provider exit");
			eq(globalLoaded.stderr.indexOf("Provider model not found: global-live/missing") != -1, true, "live cli global config provider loaded");
			final projectLoaded = @:await Cli.runAsync([
				"run",
				"--live-ai-sdk",
				"--model",
				"project-live/missing",
				"--dir",
				project,
				"Hello"
			]);
			eq(projectLoaded.exitCode, 1, "live cli project config provider exit");
			eq(projectLoaded.stderr.indexOf("Provider model not found: project-live/missing") != -1, true, "live cli project config provider loaded");
			final authLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "cloudflare-ai-gateway/missing", "Hello"]);
			eq(authLoaded.exitCode, 1, "live cli auth provider exit");
			eq(authLoaded.stderr.indexOf("Provider model not found: cloudflare-ai-gateway/missing") != -1, true, "live cli auth provider loaded");
			final remoteLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "remote-live/missing", "Hello"]);
			eq(remoteLoaded.exitCode, 1, "live cli remote well-known provider exit");
			eq(remoteLoaded.stderr.indexOf("Provider model not found: remote-live/missing") != -1, true, "live cli remote well-known provider loaded");
			eq(SmokeFetchStub.cliFetchedUrl(), "https://remote.example.com/.well-known/opencode", "live cli remote well-known URL normalized");
			writeAccountDatabase(NodePath.join(authDir, "opencode.db"), "https://account.example.com/");
			final accountLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "account-live/missing", "Hello"]);
			eq(accountLoaded.exitCode, 1, "live cli remote account provider exit");
			eq(accountLoaded.stderr.indexOf("Provider model not found: account-live/missing") != -1, true, "live cli remote account provider loaded");
			eq(SmokeFetchStub.cliFetchedUrl(), "https://account.example.com/api/config", "live cli remote account URL normalized");
			eq(SmokeFetchStub.cliAccountAuth(), "Bearer account-live-token", "live cli remote account auth header");
			eq(SmokeFetchStub.cliAccountOrg(), "org-live", "live cli remote account org header");
			SmokeFetchStub.restore(originalFetch);
			restoreEnv("XDG_CONFIG_HOME", originalXdg);
			restoreEnv("XDG_DATA_HOME", originalXdgData);
			restoreEnv("CLOUDFLARE_ACCOUNT_ID", originalCloudflareAccount);
			restoreEnv("CLOUDFLARE_GATEWAY_ID", originalCloudflareGateway);
			restoreEnv("CLOUDFLARE_API_TOKEN", originalCloudflareToken);
			restoreEnv("CF_AIG_TOKEN", originalCloudflareAiGatewayToken);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Haxe JS catch values can be host-native values here. Re-throw after
			// restoring the mutated test env so failure diagnostics keep the cause.
			SmokeFetchStub.restore(originalFetch);
			restoreEnv("XDG_CONFIG_HOME", originalXdg);
			restoreEnv("XDG_DATA_HOME", originalXdgData);
			restoreEnv("CLOUDFLARE_ACCOUNT_ID", originalCloudflareAccount);
			restoreEnv("CLOUDFLARE_GATEWAY_ID", originalCloudflareGateway);
			restoreEnv("CLOUDFLARE_API_TOKEN", originalCloudflareToken);
			restoreEnv("CF_AIG_TOKEN", originalCloudflareAiGatewayToken);
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function writeAccountDatabase(path:String, url:String):Void {
		final db = new BetterSqlite(path);
		try {
			db.exec("create table account (id text primary key, email text not null, url text not null, access_token text not null, refresh_token text not null, token_expiry integer)");
			db.exec("create table account_state (id integer primary key, active_account_id text, active_org_id text)");
			final account:Array<Dynamic> = [
				"account-live",
				"user@example.com",
				url,
				"account-live-token",
				"refresh-token",
				9999999999999.0
			];
			db.run("insert into account (id, email, url, access_token, refresh_token, token_expiry) values (?, ?, ?, ?, ?, ?)", account);
			final state:Array<Dynamic> = [1, "account-live", "org-live"];
			db.run("insert into account_state (id, active_account_id, active_org_id) values (?, ?, ?)", state);
			db.close();
		} catch (error:Dynamic) {
			// better-sqlite3 can throw native JS errors while creating this smoke
			// fixture. Re-throw after cleanup so the failed SQL operation remains visible.
			db.close();
			throw error;
		}
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
}
