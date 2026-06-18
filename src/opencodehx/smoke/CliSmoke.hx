package opencodehx.smoke;

import haxe.Json;
import opencodehx.cli.Cli;

class CliSmoke {
	public static function run():Void {
		final help = Cli.run(["--help"]);
		eq(help.exitCode, 0, "help exit");
		eq(help.stdout.indexOf("opencodehx run [message..]") != -1, true, "help mentions run");

		final version = Cli.run(["--version"]);
		eq(version.stdout, "0.0.0\n", "version output");

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

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
