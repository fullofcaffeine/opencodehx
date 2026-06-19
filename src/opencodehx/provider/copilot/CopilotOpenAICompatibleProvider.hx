package opencodehx.provider.copilot;

import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.Exception;

using StringTools;

enum abstract CopilotProviderModelKind(String) from String to String {
	final Chat = "chat";
	final Responses = "responses";
}

typedef CopilotOpenAICompatibleProviderSettings = {
	final apiKey:Undefinable<String>;
	final baseURL:Undefinable<String>;
	final name:Undefinable<String>;
	final headers:DynamicAccess<String>;
}

typedef CopilotOpenAICompatibleModelConfig = {
	final modelId:String;
	final provider:String;
	final baseURL:String;
	final kind:CopilotProviderModelKind;
	final headers:DynamicAccess<String>;
}

class CopilotOpenAICompatibleProvider {
	public static inline final VERSION = "0.1.0";
	public static inline final DEFAULT_BASE_URL = "https://api.openai.com/v1";
	public static inline final DEFAULT_PROVIDER_NAME = "openai-compatible";

	public static function settings(?apiKey:String, ?baseURL:String, ?name:String, ?headers:DynamicAccess<String>):CopilotOpenAICompatibleProviderSettings {
		return {
			apiKey: stringOrAbsent(apiKey),
			baseURL: stringOrAbsent(baseURL),
			name: stringOrAbsent(name),
			headers: cloneHeaders(headers),
		};
	}

	public static function languageModel(settings:CopilotOpenAICompatibleProviderSettings, modelId:String):CopilotOpenAICompatibleModelConfig {
		return chat(settings, modelId);
	}

	public static function chat(settings:CopilotOpenAICompatibleProviderSettings, modelId:String):CopilotOpenAICompatibleModelConfig {
		return model(settings, modelId, CopilotProviderModelKind.Chat);
	}

	public static function responses(settings:CopilotOpenAICompatibleProviderSettings, modelId:String):CopilotOpenAICompatibleModelConfig {
		return model(settings, modelId, CopilotProviderModelKind.Responses);
	}

	public static function url(config:CopilotOpenAICompatibleModelConfig, path:String):String {
		return config.baseURL + path;
	}

	public static function resolveBaseURL(settings:CopilotOpenAICompatibleProviderSettings):String {
		final configured = settings.baseURL.orNull();
		final baseURL = withoutTrailingSlash(configured == null ? DEFAULT_BASE_URL : configured);
		if (baseURL == "")
			throw new Exception("baseURL is required");
		return baseURL;
	}

	public static function resolveProviderName(settings:CopilotOpenAICompatibleProviderSettings):String {
		final configured = settings.name.orNull();
		if (configured == null || configured == "")
			return DEFAULT_PROVIDER_NAME;
		return configured;
	}

	public static function requestHeaders(settings:CopilotOpenAICompatibleProviderSettings):DynamicAccess<String> {
		final result = new DynamicAccess<String>();
		final apiKey = settings.apiKey.orNull();
		if (apiKey != null && apiKey != "")
			result.set("authorization", 'Bearer ${apiKey}');

		copyNormalizedHeaders(settings.headers, result);
		appendUserAgentSuffix(result);
		return result;
	}

	static function model(settings:CopilotOpenAICompatibleProviderSettings, modelId:String, kind:CopilotProviderModelKind):CopilotOpenAICompatibleModelConfig {
		return {
			modelId: modelId,
			provider: resolveProviderName(settings) + "." + kind,
			baseURL: resolveBaseURL(settings),
			kind: kind,
			headers: requestHeaders(settings),
		};
	}

	static function withoutTrailingSlash(value:String):String {
		if (value.endsWith("/"))
			return value.substr(0, value.length - 1);
		return value;
	}

	static function appendUserAgentSuffix(headers:DynamicAccess<String>):Void {
		final suffix = 'ai-sdk/openai-compatible/${VERSION}';
		final current = headers.get("user-agent");
		if (current == null || current == "") {
			headers.set("user-agent", suffix);
			return;
		}
		headers.set("user-agent", current + " " + suffix);
	}

	static function copyNormalizedHeaders(source:DynamicAccess<String>, target:DynamicAccess<String>):Void {
		for (key in source.keys()) {
			final value = source.get(key);
			if (value != null)
				target.set(key.toLowerCase(), value);
		}
	}

	static function cloneHeaders(source:Null<DynamicAccess<String>>):DynamicAccess<String> {
		final result = new DynamicAccess<String>();
		if (source == null)
			return result;

		for (key in source.keys()) {
			final value = source.get(key);
			if (value != null)
				result.set(key, value);
		}
		return result;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		if (value == null)
			return Undefinable.absent();
		final present:String = value;
		return present;
	}
}
