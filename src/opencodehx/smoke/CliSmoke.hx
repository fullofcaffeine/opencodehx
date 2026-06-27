package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.account.AccountError.AccountTransportError;
import opencodehx.cli.Cli;
import opencodehx.cli.ErrorFormatter;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigError.ConfigException;
import opencodehx.config.ConfigError.ConfigFailure;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.BetterSqlite;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.resource.Resources;
import opencodehx.resource.Resources.ResourcePaths;
import opencodehx.session.MessageCodec;
import opencodehx.session.SessionID;
import opencodehx.storage.SqliteSessionStore;

class CliSmoke {
	public static function run():Void {
		final help = Cli.run(["--help"]);
		eq(help.exitCode, 0, "help exit");
		eq(help.stdout.indexOf("run         run opencode with a message") != -1, true, "help mentions run");
		eq(help.stdout.indexOf("providers") != -1, true, "help mentions providers");
		eq(help.stdout.indexOf("--print-logs") != -1, true, "help mentions global print logs option");

		final runHelp = Cli.run(["run", "--help"]);
		eq(runHelp.exitCode, 0, "run help exit");
		eq(runHelp.stdout.indexOf("--file <value>") != -1, true, "run help mentions file option");
		eq(runHelp.stdout.indexOf("--dangerously-skip-permissions") != -1, true, "run help mentions permission skip option");

		final providersHelp = Cli.run(["auth", "login", "--help"]);
		eq(providersHelp.exitCode, 0, "providers alias help exit");
		eq(providersHelp.stdout.indexOf("opencodehx providers login [url]") != -1, true, "providers alias resolves canonical usage");
		eq(providersHelp.stdout.indexOf("-p, --provider <value>") != -1, true, "providers login help mentions provider alias");

		final pluginHelp = Cli.run(["plug", "--help"]);
		eq(pluginHelp.exitCode, 0, "plugin alias help exit");
		eq(pluginHelp.stdout.indexOf("Aliases: plug") != -1, true, "plugin help mentions alias");
		eq(pluginHelp.stdout.indexOf("-g, --global") != -1, true, "plugin help mentions global alias");

		final unsupported = Cli.run(["providers", "list"]);
		eq(unsupported.exitCode, 1, "known unsupported command exit");
		eq(unsupported.stderr.indexOf("Command not implemented yet: providers list") != -1, true, "known unsupported command message");

		final version = Cli.run(["--version"]);
		eq(version.stdout, BuildInfo.version + "\n", "version output");

		final text = Cli.run(["run", "--model", "openai/gpt-5.2", "Say", "hello", "from", "the", "fixture."]);
		eq(text.stdout, "Hello from the fake provider.\n", "run text output");

		final json = Cli.run(["run", "--format", "json", "Say", "hello", "from", "the", "fixture."]);
		final parsed:Dynamic = Json.parse(json.stdout);
		eq(Reflect.field(Reflect.field(parsed, "provider"), "id"), "openai", "run json provider");
		eq(Reflect.field(Reflect.field(parsed, "request"), "prompt"), "Say hello from the fixture.", "run json prompt");

		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cli-run-"));
		try {
			final runDir = NodePath.join(root, "project");
			Fs.mkdirSync(runDir, {recursive: true});
			final attachment = NodePath.join(runDir, "attached.txt");
			final attachmentDir = NodePath.join(runDir, "attached-dir");
			Fs.writeFileSync(attachment, "attached from smoke\n");
			Fs.mkdirSync(attachmentDir, {recursive: true});
			final withDir = Cli.run([
				"run",
				"--format",
				"json",
				"--dir",
				runDir,
				"Say",
				"hello",
				"from",
				"a",
				"workspace."
			]);
			eq(withDir.exitCode, 0, "run dir exit");
			eq(assistantPath(Json.parse(withDir.stdout)), NodePath.normalize(runDir), "run dir assistant path");
			final withFile = Cli.run([
				"run",
				"--format",
				"json",
				"--dir",
				runDir,
				"--file",
				"attached.txt",
				"-f",
				"attached-dir",
				"Use",
				"the",
				"attachments."
			]);
			eq(withFile.exitCode, 0, "run file exit");
			final fileParts = messageParts(Json.parse(withFile.stdout), 0);
			eq(Reflect.field(fileParts[0], "type"), "file", "run file part type");
			eq(Reflect.field(fileParts[0], "filename"), "attached.txt", "run file part filename");
			eq(Reflect.field(fileParts[0], "mime"), "text/plain", "run file part mime");
			eq(Std.string(Reflect.field(fileParts[0], "url")).indexOf("file:"), 0, "run file part url");
			eq(Reflect.field(fileParts[1], "mime"), "application/x-directory", "run directory file part mime");
			eq(Reflect.field(fileParts[2], "text"), "Use the attachments.", "run file text part");
			final missingFile = Cli.run(["run", "--dir", runDir, "--file", "missing.txt", "Hello"]);
			eq(missingFile.exitCode, 1, "run missing file exit");
			eq(missingFile.stderr.indexOf("File not found: missing.txt") != -1, true, "run missing file message");
			final missingDir = Cli.run(["run", "--dir", NodePath.join(root, "missing"), "Hello"]);
			eq(missingDir.exitCode, 1, "missing run dir exit");
			eq(missingDir.stderr.indexOf("Failed to resolve run directory") != -1, true, "missing run dir message");
			cliExport(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}

		final missing = Cli.run(["run"]);
		eq(missing.exitCode, 1, "missing prompt exit");
		eq(missing.stderr.indexOf("You must provide a message") != -1, true, "missing prompt message");

		diagnosticFormatting();
	}

	static function cliExport(root:String):Void {
		final dbPath = NodePath.join(root, "cli-export.sqlite");
		final store = new SqliteSessionStore(dbPath);
		store.upsertProject({id: "proj_cli_export", worktree: root, name: "CLI Export"});
		store.createSession({
			id: SessionID.make("ses_cli_export"),
			slug: "cli-export",
			projectID: "proj_cli_export",
			directory: root,
			title: "CLI export fixture",
			version: "0.0.0-test",
			time: {
				created: 10,
				updated: 20,
			},
		});
		store.createSession({
			id: SessionID.make("ses_cli_export_child"),
			slug: "cli-export-child",
			projectID: "proj_cli_export",
			parentID: SessionID.make("ses_cli_export"),
			directory: NodePath.join(root, "child"),
			title: "CLI export child fixture",
			version: "0.0.0-test",
			time: {
				created: 30,
				updated: 50,
			},
		});
		store.upsertMessage(MessageCodec.decodeInfoRecord({
			id: "msg_cli_export_user",
			sessionID: "ses_cli_export",
			role: "user",
			time: {created: 11},
			agent: "test",
			model: {providerID: "test", modelID: "test-model"},
			tools: {},
		}, "cli export message"));
		store.upsertPart(MessageCodec.decodePartRecord({
			id: "prt_cli_export_text",
			sessionID: "ses_cli_export",
			messageID: "msg_cli_export_user",
			type: "text",
			text: "Export this from CLI",
		}, "cli export part"), 11);
		store.close();

		final originalDb = NodeProcess.envValue("OPENCODE_DB");
		try {
			NodeProcess.setEnv("OPENCODE_DB", dbPath);
			final exported = Cli.run(["export", "ses_cli_export"]);
			eq(exported.exitCode, 0, "cli export exit");
			eq(exported.stderr, "Exporting session: ses_cli_export\n", "cli export stderr");
			final parsed:Dynamic = Json.parse(exported.stdout);
			eq(Reflect.field(Reflect.field(parsed, "info"), "id"), "ses_cli_export", "cli export info id");
			final messages:Array<Dynamic> = Reflect.field(parsed, "messages");
			eq(messages.length, 1, "cli export message count");
			final parts:Array<Dynamic> = Reflect.field(messages[0], "parts");
			eq(Reflect.field(parts[0], "text"), "Export this from CLI", "cli export raw text");

			final sanitized = Cli.run(["export", "--sanitize", "ses_cli_export"]);
			eq(sanitized.exitCode, 0, "cli export sanitized exit");
			final sanitizedParsed:Dynamic = Json.parse(sanitized.stdout);
			final sanitizedMessages:Array<Dynamic> = Reflect.field(sanitizedParsed, "messages");
			final sanitizedParts:Array<Dynamic> = Reflect.field(sanitizedMessages[0], "parts");
			eq(Reflect.field(sanitizedParts[0], "text"), "[redacted:text:prt_cli_export_text]", "cli export sanitized text");

			final missing = Cli.run(["export", "ses_cli_missing"]);
			eq(missing.exitCode, 1, "cli export missing exit");
			eq(missing.stderr.indexOf("Session not found: ses_cli_missing") != -1, true, "cli export missing message");

			final resumed = Cli.run([
				"run",
				"--format",
				"json",
				"--session",
				"ses_cli_export",
				"Resume",
				"this",
				"session."
			]);
			eq(resumed.exitCode, 0, "cli run session exit");
			final resumedParsed:Dynamic = Json.parse(resumed.stdout);
			eq(Reflect.field(Reflect.field(resumedParsed, "request"), "sessionID"), "ses_cli_export", "cli run session id");
			eq(assistantPath(resumedParsed), NodePath.normalize(root), "cli run session recovered directory");

			final overrideDir = NodePath.join(root, "resume-override");
			Fs.mkdirSync(overrideDir, {recursive: true});
			final resumedOverride = Cli.run([
				"run",
				"--format",
				"json",
				"--session",
				"ses_cli_export",
				"--dir",
				overrideDir,
				"Resume",
				"elsewhere."
			]);
			eq(resumedOverride.exitCode, 0, "cli run session dir override exit");
			eq(assistantPath(Json.parse(resumedOverride.stdout)), NodePath.normalize(overrideDir), "cli run session explicit dir");

			final missingRun = Cli.run(["run", "--session", "ses_cli_missing", "Hello"]);
			eq(missingRun.exitCode, 1, "cli run missing session exit");
			eq(missingRun.stderr.indexOf("Session not found: ses_cli_missing") != -1, true, "cli run missing session message");

			final continueRun = Cli.run(["run", "--continue", "--format", "json", "Hello"]);
			eq(continueRun.exitCode, 0, "cli run continue exit");
			final continueParsed:Dynamic = Json.parse(continueRun.stdout);
			eq(Reflect.field(Reflect.field(continueParsed, "request"), "sessionID"), "ses_cli_export", "cli run continue root session");
			eq(assistantPath(continueParsed), NodePath.normalize(root), "cli run continue recovered directory");

			final invalidFork = Cli.run(["run", "--fork", "Hello"]);
			eq(invalidFork.exitCode, 1, "cli run invalid fork exit");
			eq(invalidFork.stderr.indexOf("--fork requires --continue or --session") != -1, true, "cli run invalid fork message");

			final unsupportedFork = Cli.run(["run", "--session", "ses_cli_export", "--fork", "Hello"]);
			eq(unsupportedFork.exitCode, 1, "cli run fork unsupported exit");
			eq(unsupportedFork.stderr.indexOf("--fork is not wired") != -1, true, "cli run fork unsupported message");

			final persistedRun = Cli.run(["run", "--format", "json", "Persist", "this", "run."]);
			eq(persistedRun.exitCode, 0, "cli run persisted exit");
			final persistedParsed:Dynamic = Json.parse(persistedRun.stdout);
			final persistedSessionID = Std.string(Reflect.field(Reflect.field(persistedParsed, "request"), "sessionID"));
			eq(persistedSessionID.indexOf("ses_"), 0, "cli run persisted generated session id");
			final persistedExport = Cli.run(["export", persistedSessionID]);
			eq(persistedExport.exitCode, 0, "cli run persisted export exit");
			final persistedExportParsed:Dynamic = Json.parse(persistedExport.stdout);
			final persistedMessages:Array<Dynamic> = Reflect.field(persistedExportParsed, "messages");
			eq(persistedMessages.length, 2, "cli run persisted export messages");
			final persistedParts:Array<Dynamic> = Reflect.field(persistedMessages[0], "parts");
			eq(Reflect.field(persistedParts[0], "text"), "Persist this run.", "cli run persisted prompt");
			final appendedRun = Cli.run([
				"run",
				"--format",
				"json",
				"--session",
				persistedSessionID,
				"Append",
				"this",
				"run."
			]);
			eq(appendedRun.exitCode, 0, "cli run append persisted exit");
			final appendedExport = Cli.run(["export", persistedSessionID]);
			eq(appendedExport.exitCode, 0, "cli run append export exit");
			final appendedExportParsed:Dynamic = Json.parse(appendedExport.stdout);
			final appendedMessages:Array<Dynamic> = Reflect.field(appendedExportParsed, "messages");
			eq(appendedMessages.length, 4, "cli run append export messages");
			final appendedParts:Array<Dynamic> = Reflect.field(appendedMessages[2], "parts");
			eq(Reflect.field(appendedParts[0], "text"), "Append this run.", "cli run append prompt");
			restoreEnv("OPENCODE_DB", originalDb);
		} catch (error:Dynamic) {
			restoreEnv("OPENCODE_DB", originalDb);
			throw error;
		}
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

		final mockRoot = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cli-mock-"));
		final originalMockDb = NodeProcess.envValue("OPENCODE_DB");
		try {
			final mockDir = NodePath.join(mockRoot, "project");
			Fs.mkdirSync(mockDir, {recursive: true});
			final mockAttachment = NodePath.join(mockDir, "mock-attached.txt");
			Fs.writeFileSync(mockAttachment, "mock attached\n");
			final withDir = @:await Cli.runAsync([
				"run",
				"--mock-ai-sdk",
				"--format",
				"json",
				"--dir",
				mockDir,
				"Say",
				"hello",
				"from",
				"mock",
				"workspace."
			]);
			eq(withDir.exitCode, 0, "async cli dir exit");
			eq(assistantPath(Json.parse(withDir.stdout)), NodePath.normalize(mockDir), "async cli dir assistant path");
			final withFile = @:await Cli.runAsync([
				"run",
				"--mock-ai-sdk",
				"--format",
				"json",
				"--dir",
				mockDir,
				"--file",
				"mock-attached.txt",
				"Mock",
				"attachment."
			]);
			eq(withFile.exitCode, 0, "async cli file exit");
			final mockParts = messageParts(Json.parse(withFile.stdout), 0);
			eq(Reflect.field(mockParts[0], "type"), "file", "async cli file part type");
			eq(Reflect.field(mockParts[0], "filename"), "mock-attached.txt", "async cli file filename");
			eq(Reflect.field(mockParts[1], "text"), "Mock attachment.", "async cli file text part");
			NodeProcess.setEnv("OPENCODE_DB", NodePath.join(mockRoot, "mock-sdk.sqlite"));
			final persisted = @:await Cli.runAsync(["run", "--mock-ai-sdk", "--format", "json", "Persist", "through", "mock", "SDK."]);
			eq(persisted.exitCode, 0, "async cli persisted mock exit");
			final persistedParsed:Dynamic = Json.parse(persisted.stdout);
			final persistedSessionID = Std.string(Reflect.field(Reflect.field(persistedParsed, "request"), "sessionID"));
			eq(persistedSessionID.indexOf("ses_"), 0, "async cli persisted mock generated id");
			final exported = @:await Cli.runAsync(["export", persistedSessionID]);
			eq(exported.exitCode, 0, "async cli persisted mock export exit");
			final exportedMessages:Array<Dynamic> = Reflect.field(Json.parse(exported.stdout), "messages");
			eq(exportedMessages.length, 2, "async cli persisted mock message count");
			final resumed = @:await Cli.runAsync([
				"run",
				"--mock-ai-sdk",
				"--format",
				"json",
				"--session",
				persistedSessionID,
				"Append",
				"through",
				"mock",
				"SDK."
			]);
			eq(resumed.exitCode, 0, "async cli resumed mock exit");
			final resumedExport = @:await Cli.runAsync(["export", persistedSessionID]);
			eq(resumedExport.exitCode, 0, "async cli resumed mock export exit");
			final resumedMessages:Array<Dynamic> = Reflect.field(Json.parse(resumedExport.stdout), "messages");
			eq(resumedMessages.length, 4, "async cli resumed mock message count");
			restoreEnv("OPENCODE_DB", originalMockDb);
			Fs.rmSync(mockRoot, {recursive: true, force: true});
		} catch (error:Dynamic) {
			restoreEnv("OPENCODE_DB", originalMockDb);
			Fs.rmSync(mockRoot, {recursive: true, force: true});
			throw error;
		}

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
			eq(globalLoaded.stderr.indexOf("Model not found: global-live/missing") != -1, true, "live cli global config provider loaded");
			eq(globalLoaded.stderr.indexOf("Try: `opencode models`") != -1, true, "live cli global model diagnostic action");
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
			eq(projectLoaded.stderr.indexOf("Model not found: project-live/missing") != -1, true, "live cli project config provider loaded");
			final authLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "cloudflare-ai-gateway/missing", "Hello"]);
			eq(authLoaded.exitCode, 1, "live cli auth provider exit");
			eq(authLoaded.stderr.indexOf("Model not found: cloudflare-ai-gateway/missing") != -1, true, "live cli auth provider loaded");
			final remoteLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "remote-live/missing", "Hello"]);
			eq(remoteLoaded.exitCode, 1, "live cli remote well-known provider exit");
			eq(remoteLoaded.stderr.indexOf("Model not found: remote-live/missing") != -1, true, "live cli remote well-known provider loaded");
			eq(SmokeFetchStub.cliFetchedUrl(), "https://remote.example.com/.well-known/opencode", "live cli remote well-known URL normalized");
			writeAccountDatabase(NodePath.join(authDir, "opencode.db"), "https://account.example.com/");
			final accountLoaded = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "account-live/missing", "Hello"]);
			eq(accountLoaded.exitCode, 1, "live cli remote account provider exit");
			eq(accountLoaded.stderr.indexOf("Model not found: account-live/missing") != -1, true, "live cli remote account provider loaded");
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

	static function assistantPath(transcript:Dynamic):String {
		final messages:Array<Dynamic> = Reflect.field(transcript, "messages");
		final assistant:Dynamic = messages[1];
		final info:Dynamic = Reflect.field(assistant, "info");
		final path:Dynamic = Reflect.field(info, "path");
		return Std.string(Reflect.field(path, "cwd"));
	}

	static function messageParts(transcript:Dynamic, index:Int):Array<Dynamic> {
		final messages:Array<Dynamic> = Reflect.field(transcript, "messages");
		return Reflect.field(messages[index], "parts");
	}

	static function diagnosticFormatting():Void {
		final golden:Dynamic = Json.parse(Resources.text(ResourcePaths.known("errors/diagnostics.golden.json")));
		final cli:Dynamic = Reflect.field(golden, "cli");
		final account = ErrorFormatter.format(Unknown.fromBoundary(new AccountTransportError({
			method: "POST",
			url: "https://console.opencode.ai/auth/device/code",
		})));
		eq(account, Reflect.field(cli, "accountTransport"), "account transport diagnostic");

		final provider = ErrorFormatter.format(Unknown.fromBoundary(new ProviderException(ProviderFailure.ModelNotFound(ProviderID.make("fixture-provider"),
			ModelID.make("missing-model"), ["gpt-5.2", "gpt-5.1"]))));
		eq(provider, Reflect.field(cli, "providerModelNotFound"), "provider model diagnostic");

		final config = ErrorFormatter.format(Unknown.fromBoundary(new ConfigException(ConfigFailure.InvalidError("/workspace/opencode.json",
			["Unknown field provider.bad", "Invalid permission value"]))));
		eq(config, Reflect.field(cli, "configInvalid"), "config invalid diagnostic");
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
