package opencodehx.harness;

import haxe.Json;
import opencodehx.session.SessionProcessor;

typedef TranscriptTurn = {
	final provider:{
		final id:String;
		final modelID:String;
		final source:String;
	};
	final request:{
		final sessionID:String;
		final prompt:String;
		final system:Array<String>;
		final tools:Array<String>;
	};
	final events:Array<Dynamic>;
	final messages:Array<Dynamic>;
}

class TranscriptHarness {
	public static function oneTurnJson(?prompt:String):String {
		return Json.stringify(oneTurn(prompt), null, "  ");
	}

	public static function oneTurn(?inputPrompt:String):TranscriptTurn {
		final prompt = inputPrompt == null || StringTools.trim(inputPrompt) == "" ? "Say hello from the fixture." : inputPrompt;
		return cast SessionProcessor.toTranscript(SessionProcessor.run({
			prompt: prompt,
			directory: SessionProcessor.FIXTURE_DIRECTORY,
		}));
	}
}
