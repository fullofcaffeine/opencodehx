package opencodehx.smoke;

import haxe.Json;
import opencodehx.harness.TranscriptHarness;
import opencodehx.session.MessageCodec;

class ProviderSmoke {
	public static function run():Void {
		final transcript = TranscriptHarness.oneTurn();
		eq(transcript.provider.id, "openai", "provider id");
		eq(transcript.provider.modelID, "gpt-5.2", "model id");
		eq(transcript.events.length, 3, "event count");
		eq(Reflect.field(transcript.events[1], "text"), "Hello from the fake provider.", "delta text");
		eq(transcript.messages.length, 2, "message count");

		final encoded = TranscriptHarness.oneTurnJson();
		final parsed:Dynamic = Json.parse(encoded);
		final first = Reflect.field(cast parsed.messages[0], "info");
		eq(Reflect.field(first, "role"), "user", "encoded user role");
		MessageCodec.decodeWithParts(parsed.messages[1], "provider-smoke-assistant");
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
