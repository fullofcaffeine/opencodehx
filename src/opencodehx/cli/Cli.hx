package opencodehx.cli;

import genes.js.Async.await;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.account.AccountStore;
import opencodehx.auth.AuthStore;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigLoader;
import opencodehx.config.ConfigWriter;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.GlobalPaths;
import opencodehx.harness.TranscriptHarness;
import opencodehx.host.node.NodeProcess;
import opencodehx.host.node.NodePath;
import opencodehx.provider.AiSdkProvider.AiSdkMockModel;
import opencodehx.provider.FakeProvider;
import opencodehx.provider.ProviderRegistry;
import opencodehx.server.OpenCodeServer;
import opencodehx.server.ServerTypes.ServerListener;
import opencodehx.session.MessageTypes.Part;
import opencodehx.session.SessionProcessor;
import opencodehx.session.SessionProcessor.SessionProcessorResult;

typedef CliResult = {
	final handled:Bool;
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
}

class Cli {
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
		final model = option(args, "--model", option(args, "-m", "openai/gpt-5.2"));
		if (format != "default" && format != "json")
			return fail('Invalid --format "${format}". Expected "default" or "json".');
		if (model != "openai/gpt-5.2")
			return fail('Only the fake provider model is available in this scaffold: openai/gpt-5.2');
		final directoryResult = runDirectory(args);
		final directoryError = directoryResult.error;
		if (directoryError != null)
			return fail(directoryError);
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		final processed = SessionProcessor.run({
			prompt: prompt,
			directory: directoryResult.directory,
		});
		return formatRunResult(processed, format);
	}

	@:async
	static function runCommandAsync(args:Array<String>):Promise<CliResult> {
		if (has(args, "--live-ai-sdk"))
			return @:await runLiveAiSdk(args);
		if (!has(args, "--mock-ai-sdk"))
			return runCommand(args);
		if (has(args, "--help") || has(args, "-h"))
			return ok(runHelp());
		final format = option(args, "--format", "default");
		final model = option(args, "--model", option(args, "-m", "openai/gpt-5.2"));
		if (format != "default" && format != "json")
			return fail('Invalid --format "${format}". Expected "default" or "json".');
		if (model != "openai/gpt-5.2")
			return fail('The mock AI SDK harness currently provides only: openai/gpt-5.2');
		final directoryResult = runDirectory(args);
		final directoryError = directoryResult.error;
		if (directoryError != null)
			return fail(directoryError);
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		final fixture = new FakeProvider();
		final processed = @:await SessionProcessor.runAiSdk({
			prompt: prompt,
			directory: directoryResult.directory,
			provider: fixture.info,
			model: fixture.model,
			language: AiSdkMockModel.text(["Hello ", "from the AI SDK session."]),
		});
		return formatRunResult(processed, format);
	}

	@:async
	static function runLiveAiSdk(args:Array<String>):Promise<CliResult> {
		if (has(args, "--help") || has(args, "-h"))
			return ok(runHelp());
		final format = option(args, "--format", "default");
		final modelText = option(args, "--model", option(args, "-m", ""));
		if (format != "default" && format != "json")
			return fail('Invalid --format "${format}". Expected "default" or "json".');
		if (modelText == "")
			return fail("Live AI SDK runs require --model provider/model for now.");
		final directoryResult = liveDirectory(args);
		final directoryError = directoryResult.error;
		if (directoryError != null)
			return fail(directoryError);
		final directory = directoryResult.directory;
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		try {
			final env = NodeProcess.env();
			final config = ConfigInfo.empty("cli");
			config.merge(ConfigWriter.loadGlobal(GlobalPaths.config(env), {env: env}));
			config.merge(ConfigLoader.loadProject(directory, {
				defaultUsername: config.username == null ? "cli" : config.username,
				worktree: directory,
				env: env,
				includeDefaultUsername: false,
			}));
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
			final parsed = ProviderRegistry.parseModel(modelText);
			final provider = registry.getProvider(parsed.providerID);
			if (provider == null)
				return fail('Provider not available for live AI SDK run: ${parsed.providerID.toString()}');
			final model = registry.getModel(parsed.providerID, parsed.modelID);
			final language = registry.getLanguage(model);
			final processed = @:await SessionProcessor.runAiSdk({
				prompt: prompt,
				directory: directory,
				provider: provider,
				model: model,
				language: language,
			});
			return formatRunResult(processed, format);
		} catch (error:haxe.Exception) {
			return fail(error.message == null ? Std.string(error) : error.message);
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
			return fail(error.message == null ? Std.string(error) : error.message);
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

	static function liveDirectory(args:Array<String>):{final directory:String; final error:Null<String>;} {
		final raw = option(args, "--dir", "");
		if (raw == "")
			return {directory: NodeProcess.cwd(), error: null};
		try {
			final resolved = NodePath.isAbsolute(raw) ? raw : NodePath.resolve(NodeProcess.cwd(), raw);
			NodeProcess.chdir(resolved);
			return {directory: NodeProcess.cwd(), error: null};
		} catch (error:haxe.Exception) {
			return {directory: NodeProcess.cwd(), error: 'Failed to change directory to ${raw}'};
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
		lines.push("  --live-ai-sdk   run through the provider registry and real AI SDK model");
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
