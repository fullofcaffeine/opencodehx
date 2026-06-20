package opencodehx.smoke;

import genes.js.Async.await;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.cli.Cli;

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
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
