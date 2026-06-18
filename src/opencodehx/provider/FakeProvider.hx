package opencodehx.provider;

import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;

enum FakeProviderEvent {
	StreamStart;
	TextDelta(text:String);
	Finish(reason:String);
}

class FakeProvider {
	public final model:ProviderModel;
	public final info:ProviderInfo;

	final reply:String;

	public function new(?reply:String) {
		this.reply = reply == null ? "Hello from the fake provider." : reply;
		model = makeModel();
		final models = new Map<String, ProviderModel>();
		models.set(model.id.toString(), model);
		info = {
			id: model.providerID,
			name: "Test Provider",
			source: "config",
			env: [],
			options: {},
			models: models,
		};
	}

	public function stream(prompt:String):Array<FakeProviderEvent> {
		return [StreamStart, TextDelta(replyFor(prompt)), Finish("stop")];
	}

	function replyFor(prompt:String):String {
		if (StringTools.trim(prompt) == "")
			return reply;
		return reply;
	}

	static function makeModel():ProviderModel {
		return {
			id: "gpt-5.2",
			providerID: "openai",
			name: "Test Model",
			capabilities: {
				toolcall: true,
				attachment: false,
				reasoning: false,
				temperature: true,
				interleaved: false,
				input: {
					text: true,
					image: false,
					audio: false,
					video: false,
					pdf: false
				},
				output: {
					text: true,
					image: false,
					audio: false,
					video: false,
					pdf: false
				},
			},
			api: {id: "gpt-5.2", url: "https://example.com", npm: "@ai-sdk/openai"},
			cost: {input: 0, output: 0, cache: {read: 0, write: 0}},
			limit: {context: 200000, output: 10000},
			status: "active",
			options: {},
			headers: {},
			release_date: "2025-01-01",
			variants: {},
		};
	}
}
