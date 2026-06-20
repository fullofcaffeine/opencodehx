package opencodehx.smoke;

import genes.js.Async.await;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.cli.Cli;
import opencodehx.config.ConfigInfo;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
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
		try {
			final xdg = NodePath.join(root, "xdg");
			final global = NodePath.join(xdg, "opencode");
			final project = NodePath.join(root, "project");
			Fs.mkdirSync(global, {recursive: true});
			Fs.mkdirSync(project, {recursive: true});
			Fs.writeFileSync(NodePath.join(global, "opencode.json"),
				'{"' + "$" +
				'schema":"${ConfigInfo.DEFAULT_SCHEMA}","provider":{"global-live":{"npm":"@ai-sdk/openai-compatible","name":"Global Live","options":{"baseURL":"https://global.example.com","apiKey":"global-key"},"models":{"chat":{"name":"Chat"}}}}}');
			Fs.writeFileSync(NodePath.join(project, "opencode.json"),
				'{"' + "$" +
				'schema":"${ConfigInfo.DEFAULT_SCHEMA}","provider":{"project-live":{"npm":"@ai-sdk/openai-compatible","name":"Project Live","options":{"baseURL":"https://project.example.com","apiKey":"project-key"},"models":{"chat":{"name":"Chat"}}}}}');
			final originalXdg = NodeProcess.envValue("XDG_CONFIG_HOME");
			NodeProcess.setEnv("XDG_CONFIG_HOME", xdg);
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
			if (originalXdg == null)
				NodeProcess.unsetEnv("XDG_CONFIG_HOME");
			else
				NodeProcess.setEnv("XDG_CONFIG_HOME", originalXdg);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			NodeProcess.unsetEnv("XDG_CONFIG_HOME");
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
