package opencodehx.cli;

import opencodehx.BuildInfo;
import opencodehx.harness.TranscriptHarness;
import opencodehx.session.SessionProcessor;

typedef CliResult = {
	final handled:Bool;
	final exitCode:Int;
	final stdout:String;
	final stderr:String;
}

class Cli {
	public static function run(args:Array<String>):CliResult {
		if (args.length == 0)
			return pass();
		if (has(args, "--transcript-fixture"))
			return ok(TranscriptHarness.oneTurnJson());
		if (has(args, "--version") || has(args, "-v"))
			return ok(BuildInfo.version);
		if (has(args, "--help") || has(args, "-h"))
			return ok(help());
		if (args[0] == "run")
			return runCommand(args.slice(1));
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
		final prompt = message(args);
		if (StringTools.trim(prompt) == "")
			return fail("You must provide a message or a command");
		final processed = SessionProcessor.run({
			prompt: prompt,
			directory: SessionProcessor.FIXTURE_DIRECTORY,
		});
		final transcript:Dynamic = SessionProcessor.toTranscript(processed);
		if (format == "json")
			return ok(haxe.Json.stringify(transcript, null, "  "));
		final messages:Array<Dynamic> = Reflect.field(transcript, "messages");
		final assistant = messages[1];
		final parts:Array<Dynamic> = Reflect.field(assistant, "parts");
		final text = Std.string(Reflect.field(parts[0], "text"));
		return ok(text);
	}

	static function message(args:Array<String>):String {
		final values:Array<String> = [];
		var i = 0;
		while (i < args.length) {
			final item = args[i];
			if (item == "--format" || item == "--model" || item == "-m" || item == "--agent" || item == "--variant" || item == "--dir") {
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

	static function help():String {
		return [
			"opencodehx " + BuildInfo.version,
			"",
			"Usage:",
			"  opencodehx run [message..] [--model provider/model] [--format default|json]",
			"",
			"Commands:",
			"  run       run opencodehx with a message",
			"",
			"Options:",
			"  -h, --help      show help",
			"  -v, --version   show version number",
		].join("\n");
	}

	static function runHelp():String {
		return [
			"opencodehx run [message..]",
			"",
			"run opencodehx with a message",
			"",
			"Options:",
			"  --model, -m   model to use in the format of provider/model",
			"  --format      format: default (formatted) or json (raw JSON events)",
		].join("\n");
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
