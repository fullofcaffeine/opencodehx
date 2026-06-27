package opencodehx.plugin;

import genes.ts.Undefinable;
import opencodehx.provider.ProviderTypes.ProviderIDs;

typedef CloudflareChatParamsInput = {
	final model:CloudflareChatParamsModel;
}

typedef CloudflareChatParamsModel = {
	final providerID:String;
	final api:CloudflareChatParamsApi;
	final capabilities:CloudflareChatParamsCapabilities;
}

typedef CloudflareChatParamsApi = {
	final id:String;
}

typedef CloudflareChatParamsCapabilities = {
	final reasoning:Bool;
}

typedef CloudflareChatParamsOutput = {
	var maxOutputTokens:Undefinable<Float>;
}

class PluginCloudflare {
	public static function applyChatParams(input:CloudflareChatParamsInput, output:CloudflareChatParamsOutput):CloudflareChatParamsOutput {
		if (input.model.providerID == ProviderIDs.known("cloudflare-ai-gateway")
			&& StringTools.startsWith(input.model.api.id, "openai/")
			&& input.model.capabilities.reasoning) {
			output.maxOutputTokens = Undefinable.absent();
		}
		return output;
	}
}
