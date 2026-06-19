package opencodehx.provider;

import genes.ts.Imports;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiSdkBundledProvider;
import opencodehx.externs.ai.AiSdk.AiSdkFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiSdkProviderFactory;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

typedef AiSdkLanguageResolution = {
	final sdk:AiSdkBundledProvider;
	final language:AiLanguageModel;
	final sdkModelID:String;
	final options:AiSdkFactoryOptions;
}

class AiSdkLanguageLoader {
	static final createOpenAICompatible:AiSdkProviderFactory = Imports.namedImport("@ai-sdk/openai-compatible", "createOpenAICompatible",
		"createOpenAICompatible");

	public static function resolve(provider:ProviderInfo, model:ProviderModel):AiSdkLanguageResolution {
		final sdk = sdkFor(provider, model);
		final sdkModelID = model.api.id;
		return {
			sdk: sdk,
			language: sdk.languageModel(sdkModelID),
			sdkModelID: sdkModelID,
			options: factoryOptions(provider, model),
		};
	}

	static function sdkFor(provider:ProviderInfo, model:ProviderModel):AiSdkBundledProvider {
		return switch model.api.npm {
			case "@ai-sdk/openai-compatible":
				createOpenAICompatible(factoryOptions(provider, model));
			case npm:
				throw 'Unsupported bundled AI SDK provider: ${npm}';
		}
	}

	static function factoryOptions(provider:ProviderInfo, model:ProviderModel):AiSdkFactoryOptions {
		final baseURL = baseURL(provider.options, model);
		if (baseURL == null || baseURL == "")
			throw 'Provider ${provider.id} model ${model.id} needs api/baseURL before SDK loading';
		final apiKey = optionString(provider.options, "apiKey", provider.key);
		final includeUsage = optionBool(provider.options, "includeUsage", true);
		return {
			name: provider.id.toString(),
			baseURL: baseURL,
			apiKey: stringOrAbsent(apiKey),
			headers: headersOrAbsent(headers(provider.options, model.headers)),
			includeUsage: includeUsage == null ? Undefinable.absent() : includeUsage,
		};
	}

	static function baseURL(options:ProviderOptions, model:ProviderModel):Null<String> {
		final configured = optionString(options, "baseURL", null);
		if (configured != null && configured != "")
			return configured;
		return model.api.url;
	}

	static function headers(options:ProviderOptions, modelHeaders:ProviderHeaders):Null<DynamicAccess<String>> {
		final result = new DynamicAccess<String>();
		copyStringFields(Reflect.field(options, "headers"), result);
		for (field in modelHeaders.keys())
			result.set(field, modelHeaders.get(field));
		return empty(result) ? null : result;
	}

	static function optionString(options:ProviderOptions, field:String, fallback:Null<String>):Null<String> {
		final value = Reflect.field(options, field);
		return Std.isOfType(value, String) ? Std.string(value) : fallback;
	}

	static function optionBool(options:ProviderOptions, field:String, fallback:Null<Bool>):Null<Bool> {
		final value = Reflect.field(options, field);
		return Std.isOfType(value, Bool) ? value : fallback;
	}

	static function copyStringFields(source:Dynamic, target:DynamicAccess<String>):Void {
		// Provider options are SDK passthrough data. Only string-valued headers are
		// narrowed here before crossing into the typed OpenAI-compatible factory.
		if (source == null || !Reflect.isObject(source))
			return;
		if (Std.isOfType(source, Array) || Std.isOfType(source, String) || Std.isOfType(source, Bool) || Std.isOfType(source, Float)
			|| Std.isOfType(source, Int))
			return;
		for (field in Reflect.fields(source)) {
			final value = Reflect.field(source, field);
			if (Std.isOfType(value, String))
				target.set(field, Std.string(value));
		}
	}

	static function empty(value:DynamicAccess<String>):Bool {
		for (_ in value.keys())
			return false;
		return true;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function headersOrAbsent(value:Null<DynamicAccess<String>>):Undefinable<DynamicAccess<String>> {
		return value == null ? Undefinable.absent() : value;
	}
}
