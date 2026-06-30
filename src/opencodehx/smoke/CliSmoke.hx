package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.account.AccountError.AccountTransportError;
import opencodehx.cli.AccountDisplay;
import opencodehx.cli.AccountDisplay.AccountDisplayAccount;
import opencodehx.cli.AccountDisplay.AccountDisplayOrg;
import opencodehx.cli.Cli;
import opencodehx.cli.ErrorFormatter;
import opencodehx.cli.GitHubAction;
import opencodehx.cli.GitHubRemote;
import opencodehx.cli.CliImport;
import opencodehx.cli.CliImport.ShareImportItem;
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
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.SessionID;
import opencodehx.storage.SqliteSessionStore;

class CliSmoke {
	public static function run():Void {
		final smokeRoot = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cli-smoke-env-"));
		final originalXdg = NodeProcess.envValue("XDG_CONFIG_HOME");
		final originalXdgData = NodeProcess.envValue("XDG_DATA_HOME");
		final originalDb = NodeProcess.envValue("OPENCODE_DB");
		try {
			NodeProcess.setEnv("XDG_CONFIG_HOME", NodePath.join(smokeRoot, "xdg"));
			NodeProcess.setEnv("XDG_DATA_HOME", NodePath.join(smokeRoot, "data"));
			NodeProcess.unsetEnv("OPENCODE_DB");
			runIsolated();
			restoreEnv("XDG_CONFIG_HOME", originalXdg);
			restoreEnv("XDG_DATA_HOME", originalXdgData);
			restoreEnv("OPENCODE_DB", originalDb);
			Fs.rmSync(smokeRoot, {recursive: true, force: true});
		} catch (error:Dynamic) {
			restoreEnv("XDG_CONFIG_HOME", originalXdg);
			restoreEnv("XDG_DATA_HOME", originalXdgData);
			restoreEnv("OPENCODE_DB", originalDb);
			Fs.rmSync(smokeRoot, {recursive: true, force: true});
			throw error;
		}
	}

	static function runIsolated():Void {
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
		final parsed = parseRecord(json.stdout, "run json transcript");
		eq(providerID(parsed), "openai", "run json provider");
		eq(requestPrompt(parsed), "Say hello from the fixture.", "run json prompt");
		final defaultSessionID = requestSessionID(parsed);
		eq(defaultSessionID.indexOf("ses_"), 0, "run json default persisted session id");
		final defaultExport = Cli.run(["export", defaultSessionID]);
		eq(defaultExport.exitCode, 0, "run json default export exit");
		final defaultExportMessages = exportMessages(defaultExport.stdout, "run json default export");
		eq(defaultExportMessages.length, 2, "run json default export messages");
		final defaultResume = Cli.run([
			"run",
			"--session",
			defaultSessionID,
			"--format",
			"json",
			"Continue",
			"default",
			"store."
		]);
		eq(defaultResume.exitCode, 0, "run json default resume exit");
		eq(requestSessionID(parseRecord(defaultResume.stdout, "run json default resume")), defaultSessionID, "run json default resume session");
		final defaultContinue = Cli.run([
			"run",
			"--continue",
			"--format",
			"json",
			"Continue",
			"latest",
			"default",
			"store."
		]);
		eq(defaultContinue.exitCode, 0, "run json default continue exit");
		eq(requestSessionID(parseRecord(defaultContinue.stdout, "run json default continue")).indexOf("ses_"), 0, "run json default continue session id");

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
			eq(assistantPath(parseRecord(withDir.stdout, "run dir transcript")), NodePath.normalize(runDir), "run dir assistant path");
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
			final fileParts = messageParts(parseRecord(withFile.stdout, "run file transcript"), 0);
			eq(stringAt(fileParts, 0, "type", "run file first part"), "file", "run file part type");
			eq(stringAt(fileParts, 0, "filename", "run file first part"), "attached.txt", "run file part filename");
			eq(stringAt(fileParts, 0, "mime", "run file first part"), "text/plain", "run file part mime");
			eq(stringAt(fileParts, 0, "url", "run file first part").indexOf("file:"), 0, "run file part url");
			eq(stringAt(fileParts, 1, "mime", "run file directory part"), "application/x-directory", "run directory file part mime");
			eq(stringAt(fileParts, 2, "text", "run file text part"), "Use the attachments.", "run file text part");
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
		githubRemoteParser();
		githubActionHelpers();
		accountDisplayFormatting();
		importShareHelpers();
	}

	static function githubActionHelpers():Void {
		eq(GitHubAction.extractResponseText([textPart("prt_text", "Hello world")]), "Hello world", "github action text part");
		eq(GitHubAction.extractResponseText([textPart("prt_first", "First"), textPart("prt_last", "Last"),]), "Last", "github action last text part");
		eq(GitHubAction.extractResponseText([
			textPart("prt_help", "I'll help with that."),
			toolPart("prt_todo", "todowrite", "3 todos", "completed"),
		]), "I'll help with that.", "github action text before tool");
		eq(GitHubAction.extractResponseText([reasoningPart("prt_reasoning", "Let me think about this...")]), null, "github action reasoning only");
		eq(GitHubAction.extractResponseText([toolPart("prt_tool", "todowrite", "8 todos", "completed")]), null, "github action tool only");
		eq(GitHubAction.extractResponseText([
			toolPart("prt_read", "read", "src/file.ts", "completed"),
			toolPart("prt_edit", "edit", "src/file.ts", "completed"),
			toolPart("prt_bash", "bash", "bun test", "completed"),
		]), null, "github action multiple tools only");
		eq(GitHubAction.extractResponseText([toolPart("prt_running", "bash", "", "running")]), null, "github action running tool only");
		expectThrows(() -> GitHubAction.extractResponseText([]), "no parts returned", "github action empty parts");
		eq(GitHubAction.extractResponseText([stepStartPart("prt_step_start")]), null, "github action step-start only");
		eq(GitHubAction.extractResponseText([stepFinishPart("prt_step_finish")]), null, "github action step-finish only");
		eq(GitHubAction.extractResponseText([stepStartPart("prt_step_start2"), stepFinishPart("prt_step_finish2")]), null, "github action step parts only");
		eq(GitHubAction.extractResponseText([
			stepStartPart("prt_step_start3"),
			toolPart("prt_step_tool", "read", "src/file.ts", "completed"),
			textPart("prt_done", "Done"),
			stepFinishPart("prt_step_finish3"),
		]), "Done", "github action multi-step text");
		eq(GitHubAction.extractResponseText([
			reasoningPart("prt_internal", "Internal thinking..."),
			textPart("prt_final", "Final answer"),
		]), "Final answer", "github action text over reasoning");
		eq(GitHubAction.extractResponseText([
			toolPart("prt_tool_first", "read", "src/file.ts", "completed"),
			textPart("prt_found", "Here's what I found"),
		]), "Here's what I found", "github action text over tools");

		eq(GitHubAction.formatPromptTooLargeError([]), "PROMPT_TOO_LARGE: The prompt exceeds the model's context limit.",
			"github action prompt too large no files");
		final withFiles = GitHubAction.formatPromptTooLargeError([
			{filename: "screenshot.png", content: repeat("a", 400 * 1024)},
			{filename: "diagram.png", content: repeat("b", 200 * 1024)},
		]);
		contains(withFiles, "PROMPT_TOO_LARGE: The prompt exceeds the model's context limit.", "github action prompt prefix");
		contains(withFiles, "Files in prompt:", "github action prompt file heading");
		contains(withFiles, "screenshot.png (300 KB)", "github action prompt screenshot size");
		contains(withFiles, "diagram.png (150 KB)", "github action prompt diagram size");
		final multiple = GitHubAction.formatPromptTooLargeError([
			{filename: "img1.png", content: repeat("x", 4 * 1024)},
			{filename: "img2.jpg", content: repeat("y", 8 * 1024)},
			{filename: "img3.gif", content: repeat("z", 12 * 1024)},
		]);
		contains(multiple, "img1.png (3 KB)", "github action prompt img1 size");
		contains(multiple, "img2.jpg (6 KB)", "github action prompt img2 size");
		contains(multiple, "img3.gif (9 KB)", "github action prompt img3 size");
	}

	static function textPart(id:String, text:String):Part {
		return MessageCodec.decodePartRecord({
			id: id,
			sessionID: "ses_github_action",
			messageID: "msg_github_action",
			type: "text",
			text: text,
		}, 'github action ${id}');
	}

	static function reasoningPart(id:String, text:String):Part {
		return MessageCodec.decodePartRecord({
			id: id,
			sessionID: "ses_github_action",
			messageID: "msg_github_action",
			type: "reasoning",
			text: text,
			time: {start: 0},
		}, 'github action ${id}');
	}

	static function stepStartPart(id:String):Part {
		return MessageCodec.decodePartRecord({
			id: id,
			sessionID: "ses_github_action",
			messageID: "msg_github_action",
			type: "step-start",
		}, 'github action ${id}');
	}

	static function stepFinishPart(id:String):Part {
		return MessageCodec.decodePartRecord({
			id: id,
			sessionID: "ses_github_action",
			messageID: "msg_github_action",
			type: "step-finish",
			reason: "done",
			cost: 0,
			tokens: {
				input: 0,
				output: 0,
				reasoning: 0,
				cache: {read: 0, write: 0}
			},
		}, 'github action ${id}');
	}

	static function toolPart(id:String, tool:String, title:String, status:String):Part {
		if (status == "running") {
			return MessageCodec.decodePartRecord({
				id: id,
				sessionID: "ses_github_action",
				messageID: "msg_github_action",
				type: "tool",
				callID: 'call_${id}',
				tool: tool,
				state: {
					status: "running",
					input: {},
					time: {start: 0},
				},
			}, 'github action ${id}');
		}
		return MessageCodec.decodePartRecord({
			id: id,
			sessionID: "ses_github_action",
			messageID: "msg_github_action",
			type: "tool",
			callID: 'call_${id}',
			tool: tool,
			state: {
				status: "completed",
				input: {},
				output: "",
				title: title,
				metadata: {},
				time: {start: 0, end: 1},
			},
		}, 'github action ${id}');
	}

	static function importShareHelpers():Void {
		eq(CliImport.parseShareUrl("https://opncd.ai/share/Jsj3hNIW"), "Jsj3hNIW", "import share URL opncd");
		eq(CliImport.parseShareUrl("https://custom.example.com/share/abc123"), "abc123", "import share URL custom");
		eq(CliImport.parseShareUrl("http://localhost:3000/share/test_id-123"), "test_id-123", "import share URL localhost");
		eq(CliImport.parseShareUrl("https://opncd.ai/s/Jsj3hNIW"), null, "import legacy share URL rejected");
		eq(CliImport.parseShareUrl("https://opncd.ai/share/"), null, "import empty share URL rejected");
		eq(CliImport.parseShareUrl("https://opncd.ai/share/id/extra"), null, "import extra share path rejected");
		eq(CliImport.parseShareUrl("not-a-url"), null, "import invalid share URL rejected");

		eq(CliImport.shouldAttachShareAuthHeaders("https://control.example.com/share/abc", "https://control.example.com"), true,
			"import same-origin auth headers");
		eq(CliImport.shouldAttachShareAuthHeaders("https://other.example.com/share/abc", "https://control.example.com"), false,
			"import other-origin auth headers");
		eq(CliImport.shouldAttachShareAuthHeaders("https://control.example.com:443/share/abc", "https://control.example.com"), true,
			"import default port same-origin auth headers");
		eq(CliImport.shouldAttachShareAuthHeaders("not-a-url", "https://control.example.com"), false, "import invalid origin auth headers");

		final transformed = CliImport.transformShareData([
			ShareImportItem.Session({id: "sess-1", title: "Test"}),
			ShareImportItem.Message({id: "msg-1", sessionID: "sess-1"}),
			ShareImportItem.Part({id: "part-1", messageID: "msg-1"}),
			ShareImportItem.Part({id: "part-2", messageID: "msg-1"}),
		]);
		eq(transformed == null, false, "import transformed present");
		eq(transformed.info.id, "sess-1", "import transformed session");
		eq(transformed.messages.length, 1, "import transformed message count");
		eq(transformed.messages[0].parts.length, 2, "import transformed part count");
		eq(CliImport.transformShareData([]), null, "import empty share data rejected");
		eq(CliImport.transformShareData([ShareImportItem.Message({id: "msg-1", sessionID: "sess-1"})]), null, "import share data without session rejected");
		eq(CliImport.transformShareData([ShareImportItem.Session({id: "sess-1"})]), null, "import share data without messages rejected");
	}

	static function accountDisplayFormatting():Void {
		final account:AccountDisplayAccount = {email: "one@example.com", url: "https://one.example.com"};
		final org:AccountDisplayOrg = {id: "org-1", name: "One"};
		eq(stripKnownCliAnsi(AccountDisplay.formatAccountLabel(account, false)), "one@example.com https://one.example.com", "account label url");
		eq(stripKnownCliAnsi(AccountDisplay.formatAccountLabel(account, true)), "one@example.com https://one.example.com (active)", "account label active");
		eq(stripKnownCliAnsi(AccountDisplay.formatOrgLine(account, org, true)), "  \u25cf One  one@example.com  https://one.example.com  org-1",
			"account org line active");
	}

	static function stripKnownCliAnsi(value:String):String {
		return value.split(AccountDisplay.TEXT_HIGHLIGHT_BOLD)
			.join("")
			.split(AccountDisplay.TEXT_SUCCESS)
			.join("")
			.split(AccountDisplay.TEXT_DIM)
			.join("")
			.split(AccountDisplay.TEXT_NORMAL)
			.join("");
	}

	static function githubRemoteParser():Void {
		parsedRemote("https://github.com/sst/opencode.git", "sst", "opencode", "https .git");
		parsedRemote("https://github.com/sst/opencode", "sst", "opencode", "https");
		parsedRemote("git@github.com:sst/opencode.git", "sst", "opencode", "git ssh .git");
		parsedRemote("git@github.com:sst/opencode", "sst", "opencode", "git ssh");
		parsedRemote("ssh://git@github.com/sst/opencode.git", "sst", "opencode", "ssh url .git");
		parsedRemote("ssh://git@github.com/sst/opencode", "sst", "opencode", "ssh url");
		parsedRemote("http://github.com/owner/repo", "owner", "repo", "http");
		parsedRemote("https://github.com/my-org/my-repo.git", "my-org", "my-repo", "hyphen names");
		parsedRemote("git@github.com:my_org/my_repo.git", "my_org", "my_repo", "underscore names");
		parsedRemote("https://github.com/org123/repo456", "org123", "repo456", "number names");
		parsedRemote("https://github.com/socketio/socket.io.git", "socketio", "socket.io", "dot repo .git");
		parsedRemote("https://github.com/vuejs/vue.js", "vuejs", "vue.js", "dot repo");
		parsedRemote("git@github.com:mrdoob/three.js.git", "mrdoob", "three.js", "git dot repo");
		parsedRemote("https://github.com/jashkenas/backbone.git", "jashkenas", "backbone", "backbone");

		missingRemote("https://gitlab.com/owner/repo.git", "gitlab https");
		missingRemote("git@gitlab.com:owner/repo.git", "gitlab ssh");
		missingRemote("https://bitbucket.org/owner/repo", "bitbucket");
		missingRemote("not-a-url", "invalid url");
		missingRemote("", "empty");
		missingRemote("github.com", "host only");
		missingRemote("https://github.com/", "missing owner");
		missingRemote("https://github.com/owner", "missing repo");
		missingRemote("https://github.com/owner/repo/tree/main", "tree path");
		missingRemote("https://github.com/owner/repo/blob/main/file.ts", "blob path");
	}

	static function parsedRemote(url:String, owner:String, repo:String, label:String):Void {
		final parsed = GitHubRemote.parse(url);
		eq(parsed == null, false, 'github remote $label present');
		eq(parsed.owner, owner, 'github remote $label owner');
		eq(parsed.repo, repo, 'github remote $label repo');
	}

	static function missingRemote(url:String, label:String):Void {
		eq(GitHubRemote.parse(url), null, 'github remote $label rejected');
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
			final parsed = parseRecord(exported.stdout, "cli export");
			eq(exportInfoID(parsed), "ses_cli_export", "cli export info id");
			final messages = requiredArrayField(parsed, "messages", "cli export messages");
			eq(messages.length, 1, "cli export message count");
			final parts = messagePartsFromArray(messages, 0, "cli export first message");
			eq(stringAt(parts, 0, "text", "cli export first part"), "Export this from CLI", "cli export raw text");

			final sanitized = Cli.run(["export", "--sanitize", "ses_cli_export"]);
			eq(sanitized.exitCode, 0, "cli export sanitized exit");
			final sanitizedParsed = parseRecord(sanitized.stdout, "cli export sanitized");
			final sanitizedMessages = requiredArrayField(sanitizedParsed, "messages", "cli export sanitized messages");
			final sanitizedParts = messagePartsFromArray(sanitizedMessages, 0, "cli export sanitized first message");
			eq(stringAt(sanitizedParts, 0, "text", "cli export sanitized first part"), "[redacted:text:prt_cli_export_text]", "cli export sanitized text");

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
			final resumedParsed = parseRecord(resumed.stdout, "cli run session transcript");
			eq(requestSessionID(resumedParsed), "ses_cli_export", "cli run session id");
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
			eq(assistantPath(parseRecord(resumedOverride.stdout, "cli run session dir override transcript")), NodePath.normalize(overrideDir),
				"cli run session explicit dir");

			final missingRun = Cli.run(["run", "--session", "ses_cli_missing", "Hello"]);
			eq(missingRun.exitCode, 1, "cli run missing session exit");
			eq(missingRun.stderr.indexOf("Session not found: ses_cli_missing") != -1, true, "cli run missing session message");

			final continueRun = Cli.run(["run", "--continue", "--format", "json", "Hello"]);
			eq(continueRun.exitCode, 0, "cli run continue exit");
			final continueParsed = parseRecord(continueRun.stdout, "cli run continue transcript");
			eq(requestSessionID(continueParsed), "ses_cli_export", "cli run continue root session");
			eq(assistantPath(continueParsed), NodePath.normalize(root), "cli run continue recovered directory");

			final invalidFork = Cli.run(["run", "--fork", "Hello"]);
			eq(invalidFork.exitCode, 1, "cli run invalid fork exit");
			eq(invalidFork.stderr.indexOf("--fork requires --continue or --session") != -1, true, "cli run invalid fork message");

			final forkedRun = Cli.run([
				"run",
				"--session",
				"ses_cli_export",
				"--fork",
				"--format",
				"json",
				"Fork",
				"this",
				"session."
			]);
			eq(forkedRun.exitCode, 0, "cli run fork exit");
			final forkedParsed = parseRecord(forkedRun.stdout, "cli run fork transcript");
			final forkedSessionID = requestSessionID(forkedParsed);
			eq(forkedSessionID.indexOf("ses_"), 0, "cli run fork generated session id");
			eq(forkedSessionID == "ses_cli_export", false, "cli run fork uses child session id");
			final forkedExport = Cli.run(["export", forkedSessionID]);
			eq(forkedExport.exitCode, 0, "cli run fork export exit");
			final forkedExportParsed = parseRecord(forkedExport.stdout, "cli run fork export");
			eq(exportParentID(forkedExportParsed), "ses_cli_export", "cli run fork parent id");
			final forkedMessages = requiredArrayField(forkedExportParsed, "messages", "cli run fork export messages");
			eq(forkedMessages.length, 2, "cli run fork export messages");
			final forkedParts = messagePartsFromArray(forkedMessages, 0, "cli run fork first message");
			eq(stringAt(forkedParts, 0, "text", "cli run fork first part"), "Fork this session.", "cli run fork prompt");

			final persistedRun = Cli.run(["run", "--format", "json", "Persist", "this", "run."]);
			eq(persistedRun.exitCode, 0, "cli run persisted exit");
			final persistedParsed = parseRecord(persistedRun.stdout, "cli run persisted transcript");
			final persistedSessionID = requestSessionID(persistedParsed);
			eq(persistedSessionID.indexOf("ses_"), 0, "cli run persisted generated session id");
			final persistedExport = Cli.run(["export", persistedSessionID]);
			eq(persistedExport.exitCode, 0, "cli run persisted export exit");
			final persistedExportParsed = parseRecord(persistedExport.stdout, "cli run persisted export");
			final persistedMessages = requiredArrayField(persistedExportParsed, "messages", "cli run persisted export messages");
			eq(persistedMessages.length, 2, "cli run persisted export messages");
			final persistedParts = messagePartsFromArray(persistedMessages, 0, "cli run persisted first message");
			eq(stringAt(persistedParts, 0, "text", "cli run persisted first part"), "Persist this run.", "cli run persisted prompt");
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
			final appendedExportParsed = parseRecord(appendedExport.stdout, "cli run append export");
			final appendedMessages = requiredArrayField(appendedExportParsed, "messages", "cli run append export messages");
			eq(appendedMessages.length, 4, "cli run append export messages");
			final appendedParts = messagePartsFromArray(appendedMessages, 2, "cli run append third message");
			eq(stringAt(appendedParts, 0, "text", "cli run append first part"), "Append this run.", "cli run append prompt");
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
		final parsed = parseRecord(json.stdout, "async cli json transcript");
		eq(providerID(parsed), "openai", "async cli json provider");
		eq(requestPrompt(parsed), "Say hello through the SDK.", "async cli json prompt");
		final events = requiredArrayField(parsed, "events", "async cli events");
		eq(stringAt(events, 0, "type", "async cli first event"), "start", "async cli start event");
		eq(stringAt(events, 1, "text", "async cli second event"), "Hello ", "async cli first delta");

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
			eq(assistantPath(parseRecord(withDir.stdout, "async cli dir transcript")), NodePath.normalize(mockDir), "async cli dir assistant path");
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
			final mockParts = messageParts(parseRecord(withFile.stdout, "async cli file transcript"), 0);
			eq(stringAt(mockParts, 0, "type", "async cli file first part"), "file", "async cli file part type");
			eq(stringAt(mockParts, 0, "filename", "async cli file first part"), "mock-attached.txt", "async cli file filename");
			eq(stringAt(mockParts, 1, "text", "async cli file second part"), "Mock attachment.", "async cli file text part");
			NodeProcess.setEnv("OPENCODE_DB", NodePath.join(mockRoot, "mock-sdk.sqlite"));
			final persisted = @:await Cli.runAsync(["run", "--mock-ai-sdk", "--format", "json", "Persist", "through", "mock", "SDK."]);
			eq(persisted.exitCode, 0, "async cli persisted mock exit");
			final persistedParsed = parseRecord(persisted.stdout, "async cli persisted mock transcript");
			final persistedSessionID = requestSessionID(persistedParsed);
			eq(persistedSessionID.indexOf("ses_"), 0, "async cli persisted mock generated id");
			final exported = @:await Cli.runAsync(["export", persistedSessionID]);
			eq(exported.exitCode, 0, "async cli persisted mock export exit");
			final exportedMessages = exportMessages(exported.stdout, "async cli persisted mock export");
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
			final resumedMessages = exportMessages(resumedExport.stdout, "async cli resumed mock export");
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
		eq(liveMissingModel.stderr.indexOf("require --model provider/model or config model") != -1, true, "live cli missing model message");

		final liveMissingProvider = @:await Cli.runAsync(["run", "--live-ai-sdk", "--model", "missing-provider/model", "Hello"]);
		eq(liveMissingProvider.exitCode, 1, "live cli missing provider exit");
		eq(liveMissingProvider.stderr.indexOf("Provider not available") != -1, true, "live cli missing provider message");

		final liveRoot = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cli-live-"));
		final originalLiveXdg = NodeProcess.envValue("XDG_CONFIG_HOME");
		final originalLiveXdgData = NodeProcess.envValue("XDG_DATA_HOME");
		final originalLiveDb = NodeProcess.envValue("OPENCODE_DB");
		final originalLiveFetch = SmokeFetchStub.installCliLiveSuccess();
		try {
			final liveXdg = NodePath.join(liveRoot, "xdg");
			final liveXdgData = NodePath.join(liveRoot, "data");
			final liveDir = NodePath.join(liveRoot, "project");
			final liveAttachment = NodePath.join(liveDir, "live-attached.txt");
			final liveConfig = NodePath.join(liveXdg, "opencode");
			Fs.mkdirSync(liveConfig, {recursive: true});
			Fs.mkdirSync(NodePath.join(liveXdgData, "opencode"), {recursive: true});
			Fs.mkdirSync(liveDir, {recursive: true});
			Fs.writeFileSync(liveAttachment, "live attached\n");
			Fs.writeFileSync(NodePath.join(liveConfig, "opencode.json"),
				'{"' + "$" +
				'schema":"${ConfigInfo.DEFAULT_SCHEMA}","model":"local-live/chat","provider":{"local-live":{"npm":"@ai-sdk/openai-compatible","name":"Local Live","options":{"baseURL":"https://local-live.example.com/v1","apiKey":"local-key"},"models":{"chat":{"name":"Chat"}}}}}');
			NodeProcess.setEnv("XDG_CONFIG_HOME", liveXdg);
			NodeProcess.setEnv("XDG_DATA_HOME", liveXdgData);
			NodeProcess.setEnv("OPENCODE_DB", NodePath.join(liveRoot, "live.sqlite"));
			final liveRun = @:await Cli.runAsync([
				"run",
				"--model",
				"local-live/chat",
				"--format",
				"json",
				"--dir",
				liveDir,
				"--file",
				"live-attached.txt",
				"Hello",
				"live."
			]);
			eq(liveRun.exitCode, 0, "live cli local success exit");
			final liveParsed = parseRecord(liveRun.stdout, "live cli local transcript");
			eq(providerID(liveParsed), "local-live", "live cli local provider");
			eq(requestPrompt(liveParsed), "Hello live.", "live cli local prompt");
			eq(assistantText(liveParsed), "Hello from local live.", "live cli local assistant text");
			eq(SmokeFetchStub.liveFetchedUrl(), "https://local-live.example.com/v1/chat/completions", "live cli local request URL");
			eq(SmokeFetchStub.liveAuth(), "Bearer local-key", "live cli local auth header");
			final liveBody = SmokeFetchStub.liveRequestBody();
			eq(liveBody != null && liveBody.indexOf('"stream":true') != -1, true, "live cli local streaming request");
			eq(assistantPath(liveParsed), NodePath.normalize(liveDir), "live cli local assistant path");
			final liveUserParts = messageParts(liveParsed, 0);
			eq(stringAt(liveUserParts, 0, "type", "live cli local file part"), "file", "live cli local file part type");
			eq(stringAt(liveUserParts, 0, "filename", "live cli local file part"), "live-attached.txt", "live cli local file filename");
			final liveSessionID = requestSessionID(liveParsed);
			eq(liveSessionID.indexOf("ses_"), 0, "live cli local persisted session id");
			final liveExport = @:await Cli.runAsync(["export", liveSessionID]);
			eq(liveExport.exitCode, 0, "live cli local export exit");
			final liveExportMessages = exportMessages(liveExport.stdout, "live cli local export");
			eq(liveExportMessages.length, 2, "live cli local export message count");
			final liveExportParts = messagePartsFromArray(liveExportMessages, 0, "live cli local export first message");
			eq(stringAt(liveExportParts, 0, "filename", "live cli local export first part"), "live-attached.txt", "live cli local export file");
			final liveAppend = @:await Cli.runAsync([
				"run",
				"--live-ai-sdk",
				"--model",
				"local-live/chat",
				"--format",
				"json",
				"--session",
				liveSessionID,
				"Append",
				"live."
			]);
			eq(liveAppend.exitCode, 0, "live cli local append exit");
			final liveAppendParsed = parseRecord(liveAppend.stdout, "live cli local append transcript");
			eq(requestSessionID(liveAppendParsed), liveSessionID, "live cli local append session");
			final liveAppendExport = @:await Cli.runAsync(["export", liveSessionID]);
			eq(liveAppendExport.exitCode, 0, "live cli local append export exit");
			final liveAppendMessages = exportMessages(liveAppendExport.stdout, "live cli local append export");
			eq(liveAppendMessages.length, 4, "live cli local append export message count");
			final liveAppendParts = messagePartsFromArray(liveAppendMessages, 2, "live cli local append third message");
			eq(stringAt(liveAppendParts, 0, "text", "live cli local append first part"), "Append live.", "live cli local appended prompt");
			final liveContinue = @:await Cli.runAsync([
				"run",
				"--live-ai-sdk",
				"--model",
				"local-live/chat",
				"--format",
				"json",
				"--continue",
				"Continue",
				"live."
			]);
			eq(liveContinue.exitCode, 0, "live cli local continue exit");
			final liveContinueParsed = parseRecord(liveContinue.stdout, "live cli local continue transcript");
			eq(requestSessionID(liveContinueParsed), liveSessionID, "live cli local continue session");
			final liveContinueExport = @:await Cli.runAsync(["export", liveSessionID]);
			eq(liveContinueExport.exitCode, 0, "live cli local continue export exit");
			final liveContinueMessages = exportMessages(liveContinueExport.stdout, "live cli local continue export");
			eq(liveContinueMessages.length, 6, "live cli local continue export message count");
			final liveContinueParts = messagePartsFromArray(liveContinueMessages, 4, "live cli local continue fifth message");
			eq(stringAt(liveContinueParts, 0, "text", "live cli local continue first part"), "Continue live.", "live cli local continued prompt");
			final liveFork = @:await Cli.runAsync([
				"run",
				"--live-ai-sdk",
				"--model",
				"local-live/chat",
				"--format",
				"json",
				"--continue",
				"--fork",
				"Fork",
				"live."
			]);
			eq(liveFork.exitCode, 0, "live cli local fork exit");
			final liveForkParsed = parseRecord(liveFork.stdout, "live cli local fork transcript");
			final liveForkSessionID = requestSessionID(liveForkParsed);
			eq(liveForkSessionID.indexOf("ses_"), 0, "live cli local fork session id");
			eq(liveForkSessionID == liveSessionID, false, "live cli local fork child session");
			final liveForkExport = @:await Cli.runAsync(["export", liveForkSessionID]);
			eq(liveForkExport.exitCode, 0, "live cli local fork export exit");
			final liveForkExportParsed = parseRecord(liveForkExport.stdout, "live cli local fork export");
			eq(exportParentID(liveForkExportParsed), liveSessionID, "live cli local fork parent");
			final liveForkMessages = requiredArrayField(liveForkExportParsed, "messages", "live cli local fork export messages");
			eq(liveForkMessages.length, 2, "live cli local fork export message count");
			final liveForkParts = messagePartsFromArray(liveForkMessages, 0, "live cli local fork first message");
			eq(stringAt(liveForkParts, 0, "text", "live cli local fork first part"), "Fork live.", "live cli local fork prompt");

			final liveConfiguredRoot = NodePath.join(liveRoot, "configured-data");
			NodeProcess.setEnv("XDG_DATA_HOME", liveConfiguredRoot);
			NodeProcess.unsetEnv("OPENCODE_DB");
			final liveConfigured = @:await Cli.runAsync(["run", "--format", "json", "--dir", liveDir, "Hello", "configured", "live."]);
			eq(liveConfigured.exitCode, 0, "live cli plain config model exit");
			final liveConfiguredParsed = parseRecord(liveConfigured.stdout, "live cli plain config model transcript");
			eq(providerID(liveConfiguredParsed), "local-live", "live cli plain config model provider");
			eq(requestPrompt(liveConfiguredParsed), "Hello configured live.", "live cli plain config model prompt");
			eq(assistantText(liveConfiguredParsed), "Hello from local live.", "live cli plain config model assistant text");
			SmokeFetchStub.restore(originalLiveFetch);
			restoreEnv("XDG_CONFIG_HOME", originalLiveXdg);
			restoreEnv("XDG_DATA_HOME", originalLiveXdgData);
			restoreEnv("OPENCODE_DB", originalLiveDb);
			Fs.rmSync(liveRoot, {recursive: true, force: true});
		} catch (error:Dynamic) {
			SmokeFetchStub.restore(originalLiveFetch);
			restoreEnv("XDG_CONFIG_HOME", originalLiveXdg);
			restoreEnv("XDG_DATA_HOME", originalLiveXdgData);
			restoreEnv("OPENCODE_DB", originalLiveDb);
			Fs.rmSync(liveRoot, {recursive: true, force: true});
			throw error;
		}

		final liveFailureRoot = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-cli-live-failure-"));
		final originalLiveFailureXdg = NodeProcess.envValue("XDG_CONFIG_HOME");
		final originalLiveFailureXdgData = NodeProcess.envValue("XDG_DATA_HOME");
		final originalLiveFailureDb = NodeProcess.envValue("OPENCODE_DB");
		final originalLiveFailureFetch = SmokeFetchStub.installCliLiveFailure();
		try {
			final liveFailureXdg = NodePath.join(liveFailureRoot, "xdg");
			final liveFailureXdgData = NodePath.join(liveFailureRoot, "data");
			final liveFailureConfig = NodePath.join(liveFailureXdg, "opencode");
			Fs.mkdirSync(liveFailureConfig, {recursive: true});
			Fs.mkdirSync(NodePath.join(liveFailureXdgData, "opencode"), {recursive: true});
			Fs.writeFileSync(NodePath.join(liveFailureConfig, "opencode.json"),
				'{"' + "$" +
				'schema":"${ConfigInfo.DEFAULT_SCHEMA}","provider":{"local-fail":{"npm":"@ai-sdk/openai-compatible","name":"Local Fail","options":{"baseURL":"https://local-fail.example.com/v1","apiKey":"fail-key"},"models":{"chat":{"name":"Chat"}}}}}');
			NodeProcess.setEnv("XDG_CONFIG_HOME", liveFailureXdg);
			NodeProcess.setEnv("XDG_DATA_HOME", liveFailureXdgData);
			NodeProcess.setEnv("OPENCODE_DB", NodePath.join(liveFailureRoot, "live-failure.sqlite"));
			final liveFailure = @:await Cli.runAsync([
				"run",
				"--live-ai-sdk",
				"--model",
				"local-fail/chat",
				"--format",
				"json",
				"Fail",
				"live."
			]);
			eq(liveFailure.exitCode, 0, "live cli local failure exit");
			final liveFailureParsed = parseRecord(liveFailure.stdout, "live cli local failure transcript");
			eq(providerID(liveFailureParsed), "local-fail", "live cli local failure provider");
			eq(hasTranscriptEvent(liveFailureParsed, "error", "local live failure"), true, "live cli local failure event");
			eq(hasTranscriptEvent(liveFailureParsed, "error", "No output generated. Check the stream for errors."), true,
				"live cli local failure no-output event");
			eq(assistantFinish(liveFailureParsed), "error", "live cli local failure assistant finish");
			eq(SmokeFetchStub.liveFetchedUrl(), "https://local-fail.example.com/v1/chat/completions", "live cli local failure request URL");
			eq(SmokeFetchStub.liveAuth(), "Bearer fail-key", "live cli local failure auth header");
			final liveFailureSessionID = requestSessionID(liveFailureParsed);
			final liveFailureExport = @:await Cli.runAsync(["export", liveFailureSessionID]);
			eq(liveFailureExport.exitCode, 0, "live cli local failure export exit");
			final liveFailureExportParsed = parseRecord(liveFailureExport.stdout, "live cli local failure export");
			eq(assistantFinish(liveFailureExportParsed), "error", "live cli local failure export assistant finish");
			eq(assistantText(liveFailureExportParsed), "", "live cli local failure export empty assistant text");
			SmokeFetchStub.restore(originalLiveFailureFetch);
			restoreEnv("XDG_CONFIG_HOME", originalLiveFailureXdg);
			restoreEnv("XDG_DATA_HOME", originalLiveFailureXdgData);
			restoreEnv("OPENCODE_DB", originalLiveFailureDb);
			Fs.rmSync(liveFailureRoot, {recursive: true, force: true});
		} catch (error:Dynamic) {
			SmokeFetchStub.restore(originalLiveFailureFetch);
			restoreEnv("XDG_CONFIG_HOME", originalLiveFailureXdg);
			restoreEnv("XDG_DATA_HOME", originalLiveFailureXdgData);
			restoreEnv("OPENCODE_DB", originalLiveFailureDb);
			Fs.rmSync(liveFailureRoot, {recursive: true, force: true});
			throw error;
		}

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

	static function parseRecord(text:String, label:String):UnknownRecord {
		return requiredRecord(Unknown.fromBoundary(Json.parse(text)), label);
	}

	static function requiredRecord(raw:Unknown, label:String):UnknownRecord {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			throw '${label}: expected object';
		return record;
	}

	static function requiredArray(raw:Unknown, label:String):UnknownArray {
		final array = UnknownNarrow.array(raw);
		if (array == null)
			throw '${label}: expected array';
		return array;
	}

	static function requiredString(raw:Unknown, label:String):String {
		final text = UnknownNarrow.string(raw);
		if (text == null)
			throw '${label}: expected string';
		return text;
	}

	static function requiredRecordField(record:UnknownRecord, field:String, label:String):UnknownRecord {
		return requiredRecord(record.get(field), '${label}.${field}');
	}

	static function requiredArrayField(record:UnknownRecord, field:String, label:String):UnknownArray {
		return requiredArray(record.get(field), '${label}.${field}');
	}

	static function providerID(transcript:UnknownRecord):String {
		return requiredString(requiredRecordField(transcript, "provider", "transcript").get("id"), "transcript.provider.id");
	}

	static function requestPrompt(transcript:UnknownRecord):String {
		return requiredString(requiredRecordField(transcript, "request", "transcript").get("prompt"), "transcript.request.prompt");
	}

	static function requestSessionID(transcript:UnknownRecord):String {
		return requiredString(requiredRecordField(transcript, "request", "transcript").get("sessionID"), "transcript.request.sessionID");
	}

	static function exportInfoID(exported:UnknownRecord):String {
		return requiredString(requiredRecordField(exported, "info", "export").get("id"), "export.info.id");
	}

	static function exportParentID(exported:UnknownRecord):String {
		return requiredString(requiredRecordField(exported, "info", "export").get("parentID"), "export.info.parentID");
	}

	static function exportMessages(text:String, label:String):UnknownArray {
		return requiredArrayField(parseRecord(text, label), "messages", label);
	}

	static function messageRecord(transcript:UnknownRecord, index:Int, label:String):UnknownRecord {
		return messageRecordFromArray(requiredArrayField(transcript, "messages", '${label} transcript'), index, label);
	}

	static function messageRecordFromArray(messages:UnknownArray, index:Int, label:String):UnknownRecord {
		return requiredRecord(messages.get(index), '${label}.messages[${index}]');
	}

	static function messageParts(transcript:UnknownRecord, index:Int):UnknownArray {
		return messagePartsFromArray(requiredArrayField(transcript, "messages", "transcript"), index, "transcript");
	}

	static function messagePartsFromArray(messages:UnknownArray, index:Int, label:String):UnknownArray {
		return requiredArrayField(messageRecordFromArray(messages, index, label), "parts", '${label}.messages[${index}]');
	}

	static function recordAt(array:UnknownArray, index:Int, label:String):UnknownRecord {
		return requiredRecord(array.get(index), '${label}[${index}]');
	}

	static function stringAt(array:UnknownArray, index:Int, field:String, label:String):String {
		return requiredString(recordAt(array, index, label).get(field), '${label}[${index}].${field}');
	}

	static function assistantPath(transcript:UnknownRecord):String {
		final info = requiredRecordField(messageRecord(transcript, 1, "assistant path"), "info", "assistant path");
		final path = requiredRecordField(info, "path", "assistant path info");
		return requiredString(path.get("cwd"), "assistant path cwd");
	}

	static function assistantText(transcript:UnknownRecord):String {
		final parts = messageParts(transcript, 1);
		for (index in 0...parts.length) {
			final part = requiredRecord(parts.get(index), 'assistant text part ${index}');
			if (UnknownNarrow.string(part.get("type")) == "text")
				return requiredString(part.get("text"), 'assistant text part ${index}.text');
		}
		return "";
	}

	static function assistantFinish(transcript:UnknownRecord):String {
		final info = requiredRecordField(messageRecord(transcript, 1, "assistant finish"), "info", "assistant finish");
		return requiredString(info.get("finish"), "assistant finish");
	}

	static function hasTranscriptEvent(transcript:UnknownRecord, type:String, message:String):Bool {
		final events = requiredArrayField(transcript, "events", "transcript");
		for (index in 0...events.length) {
			final event = requiredRecord(events.get(index), 'transcript.events[${index}]');
			if (UnknownNarrow.string(event.get("type")) == type && UnknownNarrow.string(event.get("message")) == message)
				return true;
		}
		return false;
	}

	static function diagnosticFormatting():Void {
		final golden = parseRecord(Resources.text(ResourcePaths.known("errors/diagnostics.golden.json")), "diagnostics golden");
		final cli = requiredRecordField(golden, "cli", "diagnostics golden");
		final account = ErrorFormatter.format(Unknown.fromBoundary(new AccountTransportError({
			method: "POST",
			url: "https://console.opencode.ai/auth/device/code",
		})));
		eq(account, requiredString(cli.get("accountTransport"), "diagnostics golden cli accountTransport"), "account transport diagnostic");

		final provider = ErrorFormatter.format(Unknown.fromBoundary(new ProviderException(ProviderFailure.ModelNotFound(ProviderID.make("fixture-provider"),
			ModelID.make("missing-model"), ["gpt-5.2", "gpt-5.1"]))));
		eq(provider, requiredString(cli.get("providerModelNotFound"), "diagnostics golden cli providerModelNotFound"), "provider model diagnostic");

		final config = ErrorFormatter.format(Unknown.fromBoundary(new ConfigException(ConfigFailure.InvalidError("/workspace/opencode.json",
			["Unknown field provider.bad", "Invalid permission value"]))));
		eq(config, requiredString(cli.get("configInvalid"), "diagnostics golden cli configInvalid"), "config invalid diagnostic");
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

	static function contains(actual:String, needle:String, label:String):Void {
		if (actual.indexOf(needle) < 0)
			throw '$label: expected "${actual}" to contain "${needle}"';
	}

	static function expectThrows(run:() -> Void, needle:String, label:String):Void {
		try {
			run();
		} catch (error:haxe.Exception) {
			if (Std.string(error).indexOf(needle) >= 0)
				return;
			throw '$label: wrong error ${Std.string(error)}';
		}
		throw '$label: expected throw';
	}

	static function repeat(value:String, count:Int):String {
		final out = new StringBuf();
		for (_ in 0...count)
			out.add(value);
		return out.toString();
	}
}
