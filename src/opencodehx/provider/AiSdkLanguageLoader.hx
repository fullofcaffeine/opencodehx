package opencodehx.provider;

import genes.ts.Imports;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import opencodehx.externs.aws.AwsCredentialProviders.AwsCredentialProvider;
import opencodehx.externs.aws.AwsCredentialProviders.AwsNodeProviderChainFactory;
import opencodehx.externs.aws.AwsCredentialProviders.AwsNodeProviderChainOptions;
import opencodehx.externs.ai.AiSdk.AiBedrockFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiBedrockProviderFactory;
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
}

class AiSdkLanguageLoader {
	static final createOpenAICompatible:AiSdkProviderFactory = Imports.namedImport("@ai-sdk/openai-compatible", "createOpenAICompatible",
		"createOpenAICompatible");
	static final createAmazonBedrock:AiBedrockProviderFactory = Imports.namedImport("@ai-sdk/amazon-bedrock", "createAmazonBedrock", "createAmazonBedrock");
	static final fromNodeProviderChain:AwsNodeProviderChainFactory = Imports.namedImport("@aws-sdk/credential-providers", "fromNodeProviderChain",
		"fromNodeProviderChain");

	public static function resolve(provider:ProviderInfo, model:ProviderModel):AiSdkLanguageResolution {
		final sdk = sdkFor(provider, model);
		final sdkModelID = sdkModelID(provider, model);
		return {
			sdk: sdk,
			language: sdk.languageModel(sdkModelID),
			sdkModelID: sdkModelID,
		};
	}

	static function sdkFor(provider:ProviderInfo, model:ProviderModel):AiSdkBundledProvider {
		return switch model.api.npm {
			case "@ai-sdk/openai-compatible":
				createOpenAICompatible(factoryOptions(provider, model));
			case "@ai-sdk/amazon-bedrock":
				createAmazonBedrock(bedrockFactoryOptions(provider, model));
			case npm:
				throw 'Unsupported bundled AI SDK provider: ${npm}';
		}
	}

	public static function sdkModelID(provider:ProviderInfo, model:ProviderModel):String {
		if (model.api.npm != "@ai-sdk/amazon-bedrock")
			return model.api.id;
		final region = ProviderOptionAccess.string(provider.options, "region", "us-east-1");
		return BedrockLanguageLoader.sdkModelID(model.api.id, region == null ? "us-east-1" : region);
	}

	public static function factoryOptions(provider:ProviderInfo, model:ProviderModel):AiSdkFactoryOptions {
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

	public static function bedrockFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiBedrockFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			region: stringOrAbsent(ProviderOptionAccess.string(provider.options, "region", "us-east-1")),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
			credentialProvider: apiKey == null || apiKey == "" ? bedrockCredentialProvider(provider) : Undefinable.absent(),
		};
	}

	static function bedrockCredentialProvider(provider:ProviderInfo):Undefinable<AwsCredentialProvider> {
		final profile = ProviderOptionAccess.string(provider.options, "profile", null);
		final options:AwsNodeProviderChainOptions = {profile: stringOrAbsent(profile)};
		return fromNodeProviderChain(options);
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function nonEmptyStringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null || value == "" ? Undefinable.absent() : value;
	}

	static function headersOrAbsent(value:Null<DynamicAccess<String>>):Undefinable<DynamicAccess<String>> {
		return value == null ? Undefinable.absent() : value;
	}
}
