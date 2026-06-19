package opencodehx.provider;

import haxe.DynamicAccess;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.copilot.CopilotChatLanguageModel;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider.CopilotOpenAICompatibleModelConfig;

using StringTools;

typedef CopilotChatLanguageResolution = {
	final language:CopilotChatLanguageModel;
	final sdkModelID:String;
	final modelConfig:CopilotOpenAICompatibleModelConfig;
}

/**
 * Registry loader for OpenCode's Haxe-owned GitHub Copilot chat provider path.
 *
 * Upstream maps `@ai-sdk/github-copilot` to a local provider package and then
 * chooses `chat(...)` or `responses(...)` by model ID. OpenCodeHX currently has
 * the chat model ported; response-model support is kept explicit so callers do
 * not accidentally route a responses-only model through chat semantics.
 */
class CopilotLanguageLoader {
	public static function canResolveChat(model:ProviderModel):Bool {
		return model.api.npm == "@ai-sdk/github-copilot" && !shouldUseResponsesApi(model.api.id);
	}

	public static function shouldUseResponsesApi(modelID:String):Bool {
		if (!modelID.startsWith("gpt-"))
			return false;
		if (modelID.startsWith("gpt-5-mini"))
			return false;
		final rest = modelID.substr("gpt-".length);
		final dash = rest.indexOf("-");
		final majorText = dash == -1 ? rest : rest.substr(0, dash);
		final major = Std.parseInt(majorText);
		if (major == null)
			return false;
		final present:Int = major;
		return present >= 5;
	}

	public static function resolveChat(provider:ProviderInfo, model:ProviderModel):CopilotChatLanguageResolution {
		if (model.api.npm != "@ai-sdk/github-copilot")
			throw 'Provider ${provider.id} model ${model.id} is not a GitHub Copilot SDK model';
		if (shouldUseResponsesApi(model.api.id))
			throw 'Provider ${provider.id} model ${model.id} should use the Copilot responses API, which is not ported yet';

		final baseURL = ProviderOptionAccess.baseURL(provider.options, model);
		if (baseURL == null || baseURL == "")
			throw 'Provider ${provider.id} model ${model.id} needs api/baseURL before Copilot loading';

		final settings = CopilotOpenAICompatibleProvider.settings(ProviderOptionAccess.string(provider.options, "apiKey", provider.key), baseURL,
			provider.id.toString(), headersOrEmpty(ProviderOptionAccess.headers(provider.options, model.headers)));
		final modelConfig = CopilotOpenAICompatibleProvider.chat(settings, model.api.id);
		return {
			language: new CopilotChatLanguageModel({
				modelConfig: modelConfig,
				includeUsage: ProviderOptionAccess.bool(provider.options, "includeUsage", false) == true,
				supportsStructuredOutputs: ProviderOptionAccess.bool(provider.options, "supportsStructuredOutputs", false) == true,
			}),
			sdkModelID: model.api.id,
			modelConfig: modelConfig,
		};
	}

	static function headersOrEmpty(value:Null<DynamicAccess<String>>):DynamicAccess<String> {
		return value == null ? new DynamicAccess<String>() : value;
	}
}
