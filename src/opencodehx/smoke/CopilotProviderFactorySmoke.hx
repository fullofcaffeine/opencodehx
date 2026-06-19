package opencodehx.smoke;

import haxe.DynamicAccess;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider;
import opencodehx.provider.copilot.CopilotOpenAICompatibleProvider.CopilotProviderModelKind;

class CopilotProviderFactorySmoke {
	public static function run():Void {
		defaultChatModel();
		apiKeyAndResponsesModel();
		customHeadersOverrideDefaults();
		languageModelAliasesChat();
		emptyBaseURLFails();
	}

	static function defaultChatModel():Void {
		final config = CopilotOpenAICompatibleProvider.chat(CopilotOpenAICompatibleProvider.settings(), "gpt-4o");
		eq(config.modelId, "gpt-4o", "default model id");
		eq(config.kind, CopilotProviderModelKind.Chat, "default kind");
		eq(config.provider, "openai-compatible.chat", "default provider id");
		eq(config.baseURL, "https://api.openai.com/v1", "default base url");
		eq(CopilotOpenAICompatibleProvider.url(config, "/chat/completions"), "https://api.openai.com/v1/chat/completions", "default url");
		eq(header(config.headers, "user-agent"), "ai-sdk/openai-compatible/0.1.0", "default user agent");
	}

	static function apiKeyAndResponsesModel():Void {
		final config = CopilotOpenAICompatibleProvider.responses(CopilotOpenAICompatibleProvider.settings("secret"), "gpt-4.1");
		eq(config.kind, CopilotProviderModelKind.Responses, "responses kind");
		eq(config.provider, "openai-compatible.responses", "responses provider id");
		eq(header(config.headers, "authorization"), "Bearer secret", "api key authorization");
	}

	static function customHeadersOverrideDefaults():Void {
		final headers = new DynamicAccess<String>();
		headers.set("Authorization", "Bearer custom");
		headers.set("X-Test", "one");
		headers.set("User-Agent", "fixture");

		final settings = CopilotOpenAICompatibleProvider.settings("secret", "https://example.test/v1/", "github-copilot", headers);
		headers.set("X-Test", "mutated");

		final config = CopilotOpenAICompatibleProvider.chat(settings, "claude-sonnet-4");
		eq(config.provider, "github-copilot.chat", "custom provider id");
		eq(config.baseURL, "https://example.test/v1", "custom base url");
		eq(header(config.headers, "authorization"), "Bearer custom", "custom authorization override");
		eq(header(config.headers, "x-test"), "one", "headers cloned before caller mutation");
		eq(header(config.headers, "user-agent"), "fixture ai-sdk/openai-compatible/0.1.0", "custom user agent suffix");
	}

	static function languageModelAliasesChat():Void {
		final config = CopilotOpenAICompatibleProvider.languageModel(CopilotOpenAICompatibleProvider.settings(), "gpt-4o-mini");
		eq(config.kind, CopilotProviderModelKind.Chat, "languageModel kind");
		eq(config.provider, "openai-compatible.chat", "languageModel provider id");
	}

	static function emptyBaseURLFails():Void {
		try {
			CopilotOpenAICompatibleProvider.chat(CopilotOpenAICompatibleProvider.settings(null, ""), "gpt-4o");
		} catch (error:haxe.Exception) {
			eq(error.message, "baseURL is required", "empty base url error");
			return;
		}
		throw "empty base url: expected failure";
	}

	static function header(headers:DynamicAccess<String>, key:String):String {
		final value = headers.get(key);
		if (value == null)
			throw 'missing header: ${key}';
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '$label: expected ${expected}, got ${actual}';
	}
}
