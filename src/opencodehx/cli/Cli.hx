package opencodehx.cli;

import genes.js.Async.await;
import genes.ts.Unknown;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.account.AccountStore;
import opencodehx.auth.AuthStore;
import opencodehx.cli.ErrorFormatter;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.AgentInfo;
import opencodehx.config.ConfigLoader;
import opencodehx.config.ConfigWriter;
import opencodehx.externs.node.Crypto;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Url;
import opencodehx.host.node.GlobalPaths;
import opencodehx.harness.TranscriptHarness;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;
import opencodehx.permission.PermissionRules;
import opencodehx.permission.PermissionRuntime;
import opencodehx.permission.PermissionTypes.PermissionRule;
import opencodehx.provider.AiSdkProvider.AiSdkMockModel;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.session.MessageTypes.WithParts;
import opencodehx.session.SessionExport;
import opencodehx.session.SessionID;
import opencodehx.session.SessionProcessor;
import opencodehx.session.SessionProcessor.SessionFileInput;
import opencodehx.session.SessionProcessor.SessionProcessorResult;
import opencodehx.session.SessionSystemPrompt;
import opencodehx.storage.SessionStore;
import opencodehx.storage.SqliteSessionStore;
import opencodehx.storage.StorageDatabasePath;
import opencodehx.storage.StorageError.StorageException;

typedef CliResult = {
	final handled:Bool;
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
}

typedef RunSessionSelection = {
	final directory:String;
	final sessionID:Null<String>;
	final forkParentID:Null<String>;
	final history:Array<WithParts>;
	final error:Null<String>;
}

typedef RunPersistence = {
	final store:Null<SessionStore>;
	final sessionID:Null<String>;
	final turnID:Null<String>;
	final turnTime:Null<Float>;
}

typedef RunAgentSelection = {
	final name:Null<String>;
	final info:Null<AgentInfo>;
	final error:Null<String>;
}

typedef RunFilesResult = {
	final files:Array<SessionFileInput>;
	final error:Null<String>;
}

typedef LiveDispatch = {
	final live:Bool;
	final error:Null<String>;
}

class Cli {
	static inline final FAKE_MODEL = "openai/gpt-5.2";
	static final runningServers:Array<OpenCodeServer> = [];
	static final runningListeners:Array<ServerListener> = [];

	public static function run(args:Array<String>):CliResult {
		if (args.length == 0)
			return pass();
		if (has(args, "--transcript-fixture"))
			return ok(TranscriptHarness.oneTurnJson());
		if (has(args, "--version") || has(args, "-v"))
			return ok(BuildInfo.version);
		if (args[0] == "run")
			return runCommand(args.slice(1));
		if (args[0] == "export")
			return exportCommand(args.slice(1));
		final surface = CliSurface.find(args);
		if (surface != null) {
			if (has(args, "--help") || has(args, "-h"))
				return ok(CliSurface.help(surface));
			return fail(CliSurface.notImplemented(surface));
		}
		if (has(args, "--help") || has(args, "-h"))
			return ok(CliSurface.topHelp());
		return fail('Unknown command: ${args[0]}\n\n${help()}');
	}

	@:async
	public static function runAsync(args:Array<String>):Promise<CliResult> {
		if (args.length == 0)
			return pass();
		if (has(args, "--transcript-fixture"))
			return ok(TranscriptHarness.oneTurnJson());
		if (has(args, "--version") || has(args, "-v"))
			return ok(BuildInfo.version);
		if (args[0] == "run")
			return @:await runCommandAsync(args.slice(1));
		if (args[0] == "serve")
			return @:await serveCommand(args.slice(1));
		if (args[0] == "export")
			return exportCommand(args.slice(1));
		final surface = CliSurface.find(args);
		if (surface != null) {
			if (has(args, "--help") || has(args, "-h"))
				return ok(CliSurface.help(surface));
			return fail(CliSurface.notImplemented(surface));
		}
		if (has(args, "--help") || has(args, "-h"))
			return ok(CliSurface.topHelp());
		return fail('Unknown command: ${args[0]}\n\n${help()}');
	}

	static function runCommand(args:Array<String>):CliResult {
		if (has(args, "--help") || has(args, "-h"))
			return ok(runHelp());
		final format = option(args, "--format", "default");
		final model = option(args, "--model", option(args, "-m", FAKE_MODEL));
		if (format != "default" && format != "json")
			return fail('Invalid --format "${format}". Expected "default" or "json".');
		if (model != FAKE_MODEL)
			return fail('Only the fake provider model is available in this scaffold: ${FAKE_MODEL}');
		final directoryResult = runDirectory(args);
		final directoryError = directoryResult.error;
		if (directoryError != null)
			return fail(directoryError);
		final filesResult = runFiles(args, runFileBaseDirectory(args, directoryResult.directory));
		final filesError = filesResult.error;
		if (filesError != null)
			return fail(filesError);
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		final resume = runSessionSelection(args, directoryResult.directory);
		final resumeError = resume.error;
		if (resumeError != null)
			return fail(resumeError);
		final persistence = runPersistence(resume.sessionID, resume.forkParentID);
		try {
			final processed = SessionProcessor.run({
				prompt: prompt,
				directory: resume.directory,
				sessionID: resume.sessionID == null ? persistence.sessionID : resume.sessionID,
				turnID: persistence.turnID,
				turnTime: persistence.turnTime,
				parentSessionID: resume.forkParentID,
				store: persistence.store,
				files: filesResult.files,
			});
			closeStore(persistence.store);
			return formatRunResult(processed, format);
		} catch (error:haxe.Exception) {
			closeStore(persistence.store);
			return fail(ErrorFormatter.format(Unknown.fromBoundary(error)));
		}
	}

	@:async
	static function runCommandAsync(args:Array<String>):Promise<CliResult> {
		if (has(args, "--help") || has(args, "-h"))
			return ok(runHelp());
		final liveDispatch = shouldUseLiveAiSdk(args);
		if (liveDispatch.error != null)
			return fail(liveDispatch.error);
		if (liveDispatch.live)
			return @:await runLiveAiSdk(args);
		if (!has(args, "--mock-ai-sdk"))
			return runCommand(args);
		final format = option(args, "--format", "default");
		final model = option(args, "--model", option(args, "-m", FAKE_MODEL));
		final variant = option(args, "--variant", "");
		if (format != "default" && format != "json")
			return fail('Invalid --format "${format}". Expected "default" or "json".');
		if (model != FAKE_MODEL)
			return fail('The mock AI SDK harness currently provides only: ${FAKE_MODEL}');
		final directoryResult = runDirectory(args);
		final directoryError = directoryResult.error;
		if (directoryError != null)
			return fail(directoryError);
		final filesResult = runFiles(args, runFileBaseDirectory(args, directoryResult.directory));
		final filesError = filesResult.error;
		if (filesError != null)
			return fail(filesError);
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		final resume = runSessionSelection(args, directoryResult.directory);
		final resumeError = resume.error;
		if (resumeError != null)
			return fail(resumeError);
		final fixture = new FakeProvider();
		final persistence = runPersistence(resume.sessionID, resume.forkParentID);
		try {
			final processed = @:await SessionProcessor.runAiSdk({
				prompt: prompt,
				directory: resume.directory,
				sessionID: resume.sessionID == null ? persistence.sessionID : resume.sessionID,
				turnID: persistence.turnID,
				turnTime: persistence.turnTime,
				parentSessionID: resume.forkParentID,
				store: persistence.store,
				provider: fixture.info,
				model: fixture.model,
				language: AiSdkMockModel.text(["Hello ", "from the AI SDK session."]),
				files: filesResult.files,
				history: resume.history,
				variant: variant == "" ? null : variant,
			});
			closeStore(persistence.store);
			return formatRunResult(processed, format);
		} catch (error:haxe.Exception) {
			closeStore(persistence.store);
			return fail(ErrorFormatter.format(Unknown.fromBoundary(error)));
		}
	}

	@:async
	static function runLiveAiSdk(args:Array<String>):Promise<CliResult> {
		if (has(args, "--help") || has(args, "-h"))
			return ok(runHelp());
		final format = option(args, "--format", "default");
		final modelText = option(args, "--model", option(args, "-m", ""));
		final variant = option(args, "--variant", "");
		if (format != "default" && format != "json")
			return fail('Invalid --format "${format}". Expected "default" or "json".');
		final directoryResult = liveDirectory(args);
		final directoryError = directoryResult.error;
		if (directoryError != null)
			return fail(directoryError);
		final filesResult = runFiles(args, runFileBaseDirectory(args, directoryResult.directory));
		final filesError = filesResult.error;
		if (filesError != null)
			return fail(filesError);
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		final resume = runSessionSelection(args, directoryResult.directory);
		final resumeError = resume.error;
		if (resumeError != null)
			return fail(resumeError);
		var persistence:Null<RunPersistence> = null;
		try {
			final env = NodeProcess.env();
			final config = loadLocalRunConfig(resume.directory, env);
			final auth = AuthStore.load(env);
			final remote = @:await ConfigLoader.loadRemoteWellKnown(AuthStore.wellKnown(auth), {
				env: env,
				includeDefaultUsername: false,
			});
			final account = ConfigLoader.loadRemoteAccountConfigs(@:await AccountStore.loadRemoteConfigs(env), {
				env: env,
				includeDefaultUsername: false,
			});
			final mergedConfig = remote.merge(config).merge(account);
			final registry = new ProviderRegistry({
				config: mergedConfig,
				env: env,
				auth: auth,
			});
			final selectedAgent = runAgentSelection(mergedConfig, args);
			final agentError = selectedAgent.error;
			if (agentError != null)
				return fail(agentError);
			final resolvedModelText = runModelText(modelText, mergedConfig, selectedAgent.info);
			if (resolvedModelText == null || resolvedModelText == "")
				return fail("Live AI SDK runs require --model provider/model or config model for now.");
			final parsed = ProviderRegistry.parseModel(resolvedModelText);
			final provider = registry.getProvider(parsed.providerID);
			if (provider == null)
				return fail('Provider not available for live AI SDK run: ${parsed.providerID.toString()}');
			final model = registry.getModel(parsed.providerID, parsed.modelID);
			final language = registry.getLanguage(model);
			persistence = runPersistence(resume.sessionID, resume.forkParentID);
			final runSessionID = resume.sessionID == null ? persistence.sessionID : resume.sessionID;
			final permission = permissionRuntime(mergedConfig, args, runSessionID, selectedAgent.info);
			final selectedVariant = runVariantText(variant, selectedAgent.info);
			final processed = @:await SessionProcessor.runAiSdk({
				prompt: prompt,
				directory: resume.directory,
				sessionID: runSessionID,
				turnID: persistence.turnID,
				turnTime: persistence.turnTime,
				parentSessionID: resume.forkParentID,
				store: persistence.store,
				provider: provider,
				model: model,
				language: language,
				files: filesResult.files,
				history: resume.history,
				permission: permission,
				agent: selectedAgent.name,
				system: SessionSystemPrompt.build({
					directory: resume.directory,
					model: model,
					agent: selectedAgent.info,
					config: mergedConfig,
				}),
				agentOptions: runAgentOptions(selectedAgent.info),
				agentTemperature: selectedAgent.info == null ? null : selectedAgent.info.temperature,
				agentTopP: selectedAgent.info == null ? null : selectedAgent.info.top_p,
				disabledTools: runAgentDisabledTools(selectedAgent.info),
				variant: selectedVariant == "" ? null : selectedVariant,
			});
			closeStore(persistence.store);
			return formatRunResult(processed, format);
		} catch (error:haxe.Exception) {
			if (persistence != null)
				closeStore(persistence.store);
			return fail(ErrorFormatter.format(Unknown.fromBoundary(error)));
		}
	}

	static function exportCommand(args:Array<String>):CliResult {
		final surface = CliSurface.find(["export"]);
		if (has(args, "--help") || has(args, "-h"))
			return ok(surface == null ? "opencodehx export [sessionID]" : CliSurface.help(surface));
		final sessionIDText = positional(args);
		if (sessionIDText == "")
			return fail("Session ID required for non-interactive export.");
		final sessionID = SessionID.make(sessionIDText);
		final progress = 'Exporting session: ${sessionID.toString()}\n';
		var store:Null<SessionStore> = null;
		try {
			final env = NodeProcess.env();
			final dbPath = StorageDatabasePath.path(env, "latest");
			Fs.mkdirSync(NodePath.dirname(dbPath), {recursive: true});
			store = new SqliteSessionStore(dbPath);
			final data = SessionExport.exportData(store, sessionID, has(args, "--sanitize"));
			store.close();
			return {
				handled: true,
				exitCode: 0,
				stdout: Json.stringify(data, null, "  ") + "\n",
				stderr: progress,
			};
		} catch (error:StorageException) {
			if (store != null)
				store.close();
			return {
				handled: true,
				exitCode: 1,
				stdout: "",
				stderr: progress + 'Session not found: ${sessionID.toString()}\n',
			};
		} catch (error:haxe.Exception) {
			if (store != null)
				store.close();
			return {
				handled: true,
				exitCode: 1,
				stdout: "",
				stderr: progress + ErrorFormatter.format(Unknown.fromBoundary(error)) + "\n",
			};
		}
	}

	static function runPersistence(resumedSessionID:Null<String>, forkParentID:Null<String>):RunPersistence {
		final dbPath = StorageDatabasePath.path(NodeProcess.env(), "latest");
		Fs.mkdirSync(NodePath.dirname(dbPath), {recursive: true});
		if (resumedSessionID != null && forkParentID == null) {
			return {
				store: new SqliteSessionStore(dbPath),
				sessionID: null,
				turnID: freshTurnID(),
				turnTime: currentTurnTime(),
			};
		}
		return {
			store: new SqliteSessionStore(dbPath),
			sessionID: freshSessionID(),
			turnID: null,
			turnTime: null,
		};
	}

	static function freshSessionID():String {
		return "ses_" + StringTools.replace(Crypto.randomUUID(), "-", "").substr(0, 20);
	}

	static function freshTurnID():String {
		return "turn_" + StringTools.replace(Crypto.randomUUID(), "-", "").substr(0, 20);
	}

	static function currentTurnTime():Float {
		return new js.lib.Date().getTime();
	}

	static function closeStore(store:Null<SessionStore>):Void {
		if (store != null)
			store.close();
	}

	static function runSessionSelection(args:Array<String>, fallbackDirectory:String):RunSessionSelection {
		if (has(args, "--fork") && !has(args, "--continue") && option(args, "--session", option(args, "-s", "")) == "")
			return {
				directory: fallbackDirectory,
				sessionID: null,
				forkParentID: null,
				history: [],
				error: "--fork requires --continue or --session"
			};

		var sessionIDText = option(args, "--session", option(args, "-s", ""));
		final shouldContinue = has(args, "--continue");
		if (sessionIDText == "" && !shouldContinue)
			return {
				directory: fallbackDirectory,
				sessionID: null,
				forkParentID: null,
				history: [],
				error: null
			};

		var store:Null<SessionStore> = null;
		try {
			final env = NodeProcess.env();
			final dbPath = StorageDatabasePath.path(env, "latest");
			Fs.mkdirSync(NodePath.dirname(dbPath), {recursive: true});
			store = new SqliteSessionStore(dbPath);
			if (sessionIDText == "") {
				final sessions = store.listSessions(50);
				for (session in sessions) {
					if (session.parentID == null) {
						sessionIDText = session.id.toString();
						break;
					}
				}
				if (sessionIDText == "") {
					store.close();
					return {
						directory: fallbackDirectory,
						sessionID: null,
						forkParentID: null,
						history: [],
						error: "No sessions found to continue."
					};
				}
			}
			final recovered = SessionProcessor.recover(store, sessionIDText, 40);
			store.close();
			final explicitDirectory = option(args, "--dir", "") != "";
			final directory = explicitDirectory ? fallbackDirectory : recovered.session.directory;
			if (has(args, "--fork")) {
				return {
					directory: directory,
					sessionID: null,
					forkParentID: recovered.session.id.toString(),
					history: recovered.messages,
					error: null,
				};
			}
			return {
				directory: directory,
				sessionID: recovered.session.id.toString(),
				forkParentID: null,
				history: recovered.messages,
				error: null,
			};
		} catch (error:StorageException) {
			if (store != null)
				store.close();
			return {
				directory: fallbackDirectory,
				sessionID: null,
				forkParentID: null,
				history: [],
				error: 'Session not found: ${sessionIDText}'
			};
		} catch (error:haxe.Exception) {
			if (store != null)
				store.close();
			return {
				directory: fallbackDirectory,
				sessionID: null,
				forkParentID: null,
				history: [],
				error: ErrorFormatter.format(Unknown.fromBoundary(error))
			};
		}
	}

	@:async
	static function serveCommand(args:Array<String>):Promise<CliResult> {
		final surface = CliSurface.find(["serve"]);
		if (has(args, "--help") || has(args, "-h"))
			return ok(surface == null ? "opencodehx serve" : CliSurface.help(surface));
		final port = parsePort(option(args, "--port", "0"));
		if (port == null)
			return fail('Invalid --port "${option(args, "--port", "0")}". Expected an integer from 0 to 65535.');
		final hostname = option(args, "--hostname", has(args, "--mdns") ? "0.0.0.0" : "127.0.0.1");
		final env = NodeProcess.env();
		final dbDir = NodePath.join(GlobalPaths.data(env), "server");
		Fs.mkdirSync(dbDir, {recursive: true});
		final server = new OpenCodeServer({
			directory: NodeProcess.cwd(),
			dbPath: NodePath.join(dbDir, "server.sqlite"),
			hostname: hostname,
		});
		try {
			final listener = @:await server.listen(port, hostname);
			runningServers.push(server);
			runningListeners.push(listener);
			return ok('opencodehx server listening on ${listener.url}');
		} catch (error:haxe.Exception) {
			server.close();
			return fail(ErrorFormatter.format(Unknown.fromBoundary(error)));
		}
	}

	static function runDirectory(args:Array<String>):{final directory:String; final error:Null<String>;} {
		final raw = option(args, "--dir", "");
		if (raw == "")
			return {directory: SessionProcessor.FIXTURE_DIRECTORY, error: null};
		final resolved = NodePath.isAbsolute(raw) ? raw : NodePath.resolve(NodeProcess.cwd(), raw);
		try {
			if (!Fs.statSync(resolved).isDirectory())
				return {directory: SessionProcessor.FIXTURE_DIRECTORY, error: 'Run directory is not a directory: ${raw}'};
			return {directory: NodePath.normalize(resolved), error: null};
		} catch (error:haxe.Exception) {
			return {directory: SessionProcessor.FIXTURE_DIRECTORY, error: 'Failed to resolve run directory: ${raw}'};
		}
	}

	static function runFileBaseDirectory(args:Array<String>, runDirectory:String):String {
		return option(args, "--dir", "") == "" ? NodeProcess.cwd() : runDirectory;
	}

	static function runFiles(args:Array<String>, baseDirectory:String):RunFilesResult {
		final files:Array<SessionFileInput> = [];
		var i = 0;
		while (i < args.length) {
			final item = args[i];
			if (item == "--file" || item == "-f") {
				if (i + 1 >= args.length)
					return {files: files, error: 'Missing value for ${item}'};
				final raw = args[i + 1];
				final resolved = NodePath.isAbsolute(raw) ? raw : NodePath.resolve(baseDirectory, raw);
				try {
					if (!Fs.existsSync(resolved))
						return {files: files, error: 'File not found: ${raw}'};
					final stat = Fs.statSync(resolved);
					files.push({
						mime: stat.isDirectory() ? "application/x-directory" : "text/plain",
						url: Url.pathToFileURL(resolved).href,
						filename: NodePath.basename(resolved),
					});
				} catch (error:haxe.Exception) {
					return {files: files, error: 'File not found: ${raw}'};
				}
				i += 2;
				continue;
			}
			i++;
		}
		return {files: files, error: null};
	}

	static function permissionRuntime(config:ConfigInfo, args:Array<String>, sessionID:Null<String>, ?agent:AgentInfo):Null<PermissionRuntime> {
		final rulesets:Array<Array<PermissionRule>> = [];
		if (agent != null)
			rulesets.push(PermissionRules.fromConfig(agent.permission));
		rulesets.push(PermissionRules.fromConfig(config.permission));
		// PermissionRules uses last-match semantics, so config-level rules are
		// appended after agent defaults and can still enforce global denies.
		final rules = PermissionRules.merge(rulesets);
		if (rules.length == 0 && !has(args, "--dangerously-skip-permissions"))
			return null;
		return new PermissionRuntime({
			ruleset: rules,
			sessionID: sessionID == null ? "" : sessionID,
			prompt: has(args, "--dangerously-skip-permissions") ? (_->{reply: "once"}) : null,
		});
	}

	static function runAgentSelection(config:ConfigInfo, args:Array<String>):RunAgentSelection {
		var name = option(args, "--agent", "");
		if (name == "" && config.defaultAgent != null)
			name = config.defaultAgent;
		if (name == "")
			return {name: null, info: null, error: null};
		final agents = config.agent;
		if (agents == null)
			return {name: name, info: null, error: 'Agent not available for live AI SDK run: ${name}'};
		final agent = agents.get(name);
		if (agent == null)
			return {name: name, info: null, error: 'Agent not available for live AI SDK run: ${name}'};
		if (agent.disable == true)
			return {name: name, info: null, error: 'Agent is disabled for live AI SDK run: ${name}'};
		return {name: name, info: agent, error: null};
	}

	static function runModelText(cliModel:String, config:ConfigInfo, agent:Null<AgentInfo>):Null<String> {
		if (cliModel != "")
			return cliModel;
		if (agent != null && agent.model != null && agent.model != "")
			return agent.model;
		return config.model;
	}

	static function runVariantText(cliVariant:String, agent:Null<AgentInfo>):String {
		if (cliVariant != "")
			return cliVariant;
		if (agent != null && agent.variant != null)
			return agent.variant;
		return "";
	}

	static function runAgentOptions(agent:Null<AgentInfo>):Null<ProviderOptions> {
		if (agent == null || agent.options == null)
			return null;
		return agent.options;
	}

	static function runAgentDisabledTools(agent:Null<AgentInfo>):Null<Array<String>> {
		if (agent == null || agent.tools == null)
			return null;
		final disabled:Array<String> = [];
		for (tool in agent.tools.keys()) {
			if (agent.tools.get(tool) == false)
				pushUnique(disabled, normalizedToolID(tool));
		}
		return disabled.length == 0 ? null : disabled;
	}

	static function normalizedToolID(tool:String):String {
		return tool == "patch" ? "apply_patch" : tool;
	}

	static function pushUnique(values:Array<String>, value:String):Void {
		if (values.indexOf(value) == -1)
			values.push(value);
	}

	static function liveDirectory(args:Array<String>):{final directory:String; final error:Null<String>;} {
		final raw = option(args, "--dir", "");
		if (raw == "")
			return {directory: NodeProcess.cwd(), error: null};
		try {
			final resolved = NodePath.isAbsolute(raw) ? raw : NodePath.resolve(NodeProcess.cwd(), raw);
			if (!Fs.statSync(resolved).isDirectory())
				return {directory: NodeProcess.cwd(), error: 'Run directory is not a directory: ${raw}'};
			return {directory: NodePath.normalize(resolved), error: null};
		} catch (error:haxe.Exception) {
			return {directory: NodeProcess.cwd(), error: 'Failed to resolve run directory: ${raw}'};
		}
	}

	static function formatRunResult(processed:SessionProcessorResult, format:String):CliResult {
		final transcript:Dynamic = SessionProcessor.toTranscript(processed);
		if (format == "json")
			return ok(haxe.Json.stringify(transcript, null, "  "));
		return ok(assistantText(processed));
	}

	static function assistantText(processed:SessionProcessorResult):String {
		if (processed.messages.length < 2)
			return "";
		for (part in processed.messages[1].parts) {
			switch part {
				case TextPart(text):
					return text.text;
				case _:
			}
		}
		return "";
	}

	static function message(args:Array<String>):String {
		final values:Array<String> = [];
		var i = 0;
		while (i < args.length) {
			final item = args[i];
			if (valueOption(item)) {
				i += 2;
				continue;
			}
			if (item == "--")
				i++;
			else if (StringTools.startsWith(item, "-"))
				i++;
			else {
				values.push(item);
				i++;
			}
		}
		return values.join(" ");
	}

	static function positional(args:Array<String>):String {
		var i = 0;
		while (i < args.length) {
			final item = args[i];
			if (valueOption(item)) {
				i += 2;
				continue;
			}
			if (item == "--")
				i++;
			else if (StringTools.startsWith(item, "-"))
				i++;
			else
				return item;
		}
		return "";
	}

	static function valueOption(item:String):Bool {
		return item == "--format" || item == "--model" || item == "-m" || item == "--agent" || item == "--variant" || item == "--dir"
			|| item == "--command" || item == "--session" || item == "-s" || item == "--file" || item == "-f" || item == "--title" || item == "--attach"
			|| item == "--password" || item == "-p" || item == "--port" || item == "--hostname" || item == "--mdns-domain" || item == "--cors";
	}

	static function option(args:Array<String>, name:String, fallback:String):String {
		for (i in 0...args.length - 1) {
			if (args[i] == name)
				return args[i + 1];
		}
		return fallback;
	}

	static function loadLocalRunConfig(directory:String, env:Dynamic):ConfigInfo {
		final config = ConfigInfo.empty("cli");
		config.merge(ConfigWriter.loadGlobal(GlobalPaths.config(env), {env: env}));
		config.merge(ConfigLoader.loadProject(directory, {
			defaultUsername: config.username == null ? "cli" : config.username,
			worktree: directory,
			env: env,
			includeDefaultUsername: false,
		}));
		return config;
	}

	static function optionMaybe(args:Array<String>, name:String):Null<String> {
		if (args.length < 2)
			return null;
		for (i in 0...args.length - 1) {
			if (args[i] == name)
				return args[i + 1];
		}
		return null;
	}

	static function shouldUseLiveAiSdk(args:Array<String>):LiveDispatch {
		if (has(args, "--live-ai-sdk"))
			return {live: true, error: null};
		if (has(args, "--mock-ai-sdk"))
			return {live: false, error: null};
		final model = optionMaybe(args, "--model");
		final shortModel = model == null ? optionMaybe(args, "-m") : model;
		if (shortModel != null)
			return {live: shortModel != FAKE_MODEL, error: null};
		final directoryResult = liveDirectory(args);
		if (directoryResult.error != null)
			return {live: false, error: null};
		try {
			final config = loadLocalRunConfig(directoryResult.directory, NodeProcess.env());
			final selectedAgent = runAgentSelection(config, args);
			final model = runModelText("", config, selectedAgent.info);
			return {live: model != null && model != "" && model != FAKE_MODEL, error: null};
		} catch (error:haxe.Exception) {
			return {live: false, error: ErrorFormatter.format(Unknown.fromBoundary(error))};
		}
	}

	static function has(args:Array<String>, flag:String):Bool {
		return args.indexOf(flag) != -1;
	}

	static function parsePort(value:String):Null<Int> {
		final parsed = Std.parseInt(value);
		if (parsed == null || parsed < 0 || parsed > 65535)
			return null;
		return parsed;
	}

	static function help():String {
		return CliSurface.topHelp();
	}

	static function runHelp():String {
		final surface = CliSurface.find(["run"]);
		final lines = [surface == null ? "opencodehx run [message..]" : CliSurface.help(surface)];
		lines.push("");
		lines.push("OpenCodeHX harness options:");
		lines.push("  --mock-ai-sdk   run through the credential-free AI SDK session harness");
		lines.push("  --live-ai-sdk   force the provider registry and real AI SDK model path");
		return lines.join("\n");
	}

	static function ok(stdout:String):CliResult {
		return {
			handled: true,
			exitCode: 0,
			stdout: stdout + "\n",
			stderr: ""
		};
	}

	static function fail(stderr:String):CliResult {
		return {
			handled: true,
			exitCode: 1,
			stdout: "",
			stderr: stderr + "\n"
		};
	}

	static function pass():CliResult {
		return {
			handled: false,
			exitCode: 0,
			stdout: "",
			stderr: ""
		};
	}
}
