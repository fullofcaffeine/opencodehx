package opencodehx.harness;

import haxe.Json;
import opencodehx.session.SessionProcessor;
import opencodehx.session.SessionProcessor.SessionTranscript;

class TranscriptHarness {
	public static function oneTurnJson(?prompt:String):String {
		return Json.stringify(oneTurn(prompt), null, "  ");
	}

	public static function oneTurn(?inputPrompt:String):SessionTranscript {
		final prompt = inputPrompt == null || StringTools.trim(inputPrompt) == "" ? "Say hello from the fixture." : inputPrompt;
		return SessionProcessor.toTranscript(SessionProcessor.run({
			prompt: prompt,
			directory: SessionProcessor.FIXTURE_DIRECTORY,
		}));
	}
}
