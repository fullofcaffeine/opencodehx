package opencodehx.provider;

import genes.ts.Imports;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiSdkBundledProvider;
import opencodehx.externs.ai.AiSdk.AiSdkFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiSdkProviderFactory;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;

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
		final baseURL = ProviderOptionAccess.baseURL(provider.options, model);
		if (baseURL == null || baseURL == "")
			throw 'Provider ${provider.id} model ${model.id} needs api/baseURL before SDK loading';
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		final includeUsage = ProviderOptionAccess.bool(provider.options, "includeUsage", true);
		return {
			name: provider.id.toString(),
			baseURL: baseURL,
			apiKey: stringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
			includeUsage: includeUsage == null ? Undefinable.absent() : includeUsage,
		};
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function headersOrAbsent(value:Null<DynamicAccess<String>>):Undefinable<DynamicAccess<String>> {
		return value == null ? Undefinable.absent() : value;
	}
}
