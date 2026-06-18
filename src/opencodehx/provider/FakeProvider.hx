package opencodehx.provider;

typedef ProviderCapabilityIO = {
	final text:Bool;
	final image:Bool;
	final audio:Bool;
	final video:Bool;
	final pdf:Bool;
}

typedef ProviderCapabilities = {
	final toolcall:Bool;
	final attachment:Bool;
	final reasoning:Bool;
	final temperature:Bool;
	final interleaved:Bool;
	final input:ProviderCapabilityIO;
	final output:ProviderCapabilityIO;
}

typedef ProviderCost = {
	final input:Float;
	final output:Float;
	final cache:{
		final read:Float;
		final write:Float;
	};
}

typedef ProviderLimit = {
	final context:Float;
	final output:Float;
}

typedef ProviderModel = {
	final id:String;
	final providerID:String;
	final name:String;
	final capabilities:ProviderCapabilities;
	final api:{
		final id:String;
		final url:String;
		final npm:String;
	};
	final cost:ProviderCost;
	final limit:ProviderLimit;
	final status:String;
	final options:Dynamic;
	final headers:Dynamic;
	final release_date:String;
}

typedef ProviderInfo = {
	final id:String;
	final name:String;
	final source:String;
	final env:Array<String>;
	final options:Dynamic;
	final models:Dynamic;
}

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
		final models:Dynamic = {};
		Reflect.setField(models, model.id, model);
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
		};
	}
}
