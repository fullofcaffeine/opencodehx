package opencodehx.provider;

import genes.ts.Imports;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.Exception;
import opencodehx.externs.aws.AwsCredentialProviders.AwsCredentialProvider;
import opencodehx.externs.aws.AwsCredentialProviders.AwsNodeProviderChainFactory;
import opencodehx.externs.aws.AwsCredentialProviders.AwsNodeProviderChainOptions;
import opencodehx.externs.ai.AiSdk.AiAnthropicFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiAnthropicProviderFactory;
import opencodehx.externs.ai.AiSdk.AiAzureFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiAzureProviderFactory;
import opencodehx.externs.ai.AiSdk.AiBedrockFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiBedrockProviderFactory;
import opencodehx.externs.ai.AiSdk.AiGoogleFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiGoogleProviderFactory;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiOptionalHeaderMap;
import opencodehx.externs.ai.AiSdk.AiOpenAIFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiOpenAIProviderFactory;
import opencodehx.externs.ai.AiSdk.AiSdkBundledProvider;
import opencodehx.externs.ai.AiSdk.AiSdkFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiSdkProviderFactory;
import opencodehx.externs.ai.AiSdk.AiVertexAnthropicFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiVertexAnthropicProviderFactory;
import opencodehx.externs.ai.AiSdk.AiVertexFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiVertexProviderFactory;
import opencodehx.externs.ai.AiSdk.AiXaiFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiXaiProviderFactory;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;

/**
 * Closed selector for the bundled AI SDK model factory method.
 *
 * This intentionally has `to String` but not `from String`: the values are
 * chosen by typed provider/model rules, not accepted from arbitrary runtime
 * input. Keeping the abstract closed lets genes-ts emit the matching TypeScript
 * literal union instead of weakening the generated API to plain `string`.
 */
enum abstract AiSdkModelMethod(String) to String {
	final LanguageModel = "languageModel";
	final Chat = "chat";
	final Responses = "responses";
}

typedef AiSdkLanguageResolution = {
	final sdk:AiSdkBundledProvider;
	final language:AiLanguageModel;
	final sdkModelID:String;
	final method:AiSdkModelMethod;
}

class AiSdkLanguageLoader {
	static final createOpenAICompatible:AiSdkProviderFactory = Imports.namedImport("@ai-sdk/openai-compatible", "createOpenAICompatible",
		"createOpenAICompatible");
	static final createAmazonBedrock:AiBedrockProviderFactory = Imports.namedImport("@ai-sdk/amazon-bedrock", "createAmazonBedrock", "createAmazonBedrock");
	static final createAnthropic:AiAnthropicProviderFactory = Imports.namedImport("@ai-sdk/anthropic", "createAnthropic", "createAnthropic");
	static final createOpenAI:AiOpenAIProviderFactory = Imports.namedImport("@ai-sdk/openai", "createOpenAI", "createOpenAI");
	static final createXai:AiXaiProviderFactory = Imports.namedImport("@ai-sdk/xai", "createXai", "createXai");
	static final createAzure:AiAzureProviderFactory = Imports.namedImport("@ai-sdk/azure", "createAzure", "createAzure");
	static final createGoogle:AiGoogleProviderFactory = Imports.namedImport("@ai-sdk/google", "createGoogleGenerativeAI", "createGoogleGenerativeAI");
	static final createVertex:AiVertexProviderFactory = Imports.namedImport("@ai-sdk/google-vertex", "createVertex", "createVertex");
	static final createVertexAnthropic:AiVertexAnthropicProviderFactory = Imports.namedImport("@ai-sdk/google-vertex/anthropic", "createVertexAnthropic",
		"createVertexAnthropic");
	static final fromNodeProviderChain:AwsNodeProviderChainFactory = Imports.namedImport("@aws-sdk/credential-providers", "fromNodeProviderChain",
		"fromNodeProviderChain");

	public static function resolve(provider:ProviderInfo, model:ProviderModel):AiSdkLanguageResolution {
		final sdk = sdkFor(provider, model);
		return resolveWithSdk(sdk, provider, model);
	}

	public static function resolveWithSdk(sdk:AiSdkBundledProvider, provider:ProviderInfo, model:ProviderModel):AiSdkLanguageResolution {
		final sdkModelID = sdkModelID(provider, model);
		final method:AiSdkModelMethod = effectiveModelMethod(sdk, provider, model);
		return {
			sdk: sdk,
			language: loadModel(sdk, sdkModelID, method),
			sdkModelID: sdkModelID,
			method: method,
		};
	}

	static function sdkFor(provider:ProviderInfo, model:ProviderModel):AiSdkBundledProvider {
		return switch model.api.npm {
			case "@ai-sdk/openai-compatible":
				createOpenAICompatible(factoryOptions(provider, model));
			case "@ai-sdk/amazon-bedrock":
				createAmazonBedrock(bedrockFactoryOptions(provider, model));
			case "@ai-sdk/anthropic":
				createAnthropic(anthropicFactoryOptions(provider, model));
			case "@ai-sdk/openai":
				createOpenAI(openAIFactoryOptions(provider, model));
			case "@ai-sdk/xai":
				createXai(xaiFactoryOptions(provider, model));
			case "@ai-sdk/azure":
				createAzure(azureFactoryOptions(provider, model));
			case "@ai-sdk/google":
				createGoogle(googleFactoryOptions(provider, model));
			case "@ai-sdk/google-vertex":
				createVertex(vertexFactoryOptions(provider, model));
			case "@ai-sdk/google-vertex/anthropic":
				createVertexAnthropic(vertexAnthropicFactoryOptions(provider, model));
			case "ai-gateway-provider":
				CloudflareAiGatewayLoader.sdk(provider, model);
			case npm:
				throw new Exception('Unsupported bundled AI SDK provider: ${npm}');
		}
	}

	public static function sdkModelID(provider:ProviderInfo, model:ProviderModel):String {
		if (model.api.npm != "@ai-sdk/amazon-bedrock")
			return model.api.id;
		final region = ProviderOptionAccess.string(provider.options, "region", "us-east-1");
		return BedrockLanguageLoader.sdkModelID(model.api.id, region == null ? "us-east-1" : region);
	}

	public static function preferredModelMethod(provider:ProviderInfo, model:ProviderModel):AiSdkModelMethod {
		return switch model.api.npm {
			case "@ai-sdk/openai" | "@ai-sdk/xai":
				Responses;
			case "@ai-sdk/azure":
				usesCompletionUrls(provider, model) ? Chat : Responses;
			case "@ai-sdk/github-copilot":
				CopilotLanguageLoader.shouldUseResponsesApi(model.api.id) ? Responses : Chat;
			case _:
				switch provider.id.toString() {
					case "openai" | "xai":
						Responses;
					case "azure" | "azure-cognitive-services":
						usesCompletionUrls(provider, model) ? Chat : Responses;
					case _:
						LanguageModel;
				}
		}
	}

	public static function factoryOptions(provider:ProviderInfo, model:ProviderModel):AiSdkFactoryOptions {
		final baseURL = ProviderOptionAccess.baseURL(provider.options, model);
		if (baseURL == null || baseURL == "")
			throw new Exception('Provider ${provider.id} model ${model.id} needs api/baseURL before SDK loading');
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

	public static function anthropicFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiAnthropicFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			name: stringOrAbsent(provider.id.toString()),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
		};
	}

	public static function openAIFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiOpenAIFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			name: stringOrAbsent(provider.id.toString()),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			organization: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "organization", null)),
			project: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "project", null)),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
		};
	}

	public static function xaiFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiXaiFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
		};
	}

	public static function azureFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiAzureFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			resourceName: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "resourceName", null)),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
			apiVersion: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "apiVersion", null)),
			useDeploymentBasedUrls: boolOrAbsent(ProviderOptionAccess.bool(provider.options, "useDeploymentBasedUrls", null)),
		};
	}

	public static function googleFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiGoogleFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			name: stringOrAbsent(provider.id.toString()),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
		};
	}

	public static function vertexFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiVertexFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			project: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "project", null)),
			location: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "location", null)),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: optionalHeadersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
		};
	}

	public static function vertexAnthropicFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiVertexAnthropicFactoryOptions {
		return {
			project: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "project", null)),
			location: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "location", null)),
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			headers: optionalHeadersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
		};
	}

	static function bedrockCredentialProvider(provider:ProviderInfo):Undefinable<AwsCredentialProvider> {
		final profile = ProviderOptionAccess.string(provider.options, "profile", null);
		final options:AwsNodeProviderChainOptions = {profile: stringOrAbsent(profile)};
		return fromNodeProviderChain(options);
	}

	static function effectiveModelMethod(sdk:AiSdkBundledProvider, provider:ProviderInfo, model:ProviderModel):AiSdkModelMethod {
		if (canFallbackToLanguageModel(provider, model) && sdk.chat == null && sdk.responses == null)
			return LanguageModel;
		return preferredModelMethod(provider, model);
	}

	static function canFallbackToLanguageModel(provider:ProviderInfo, model:ProviderModel):Bool {
		return model.api.npm == "@ai-sdk/azure"
			|| model.api.npm == "@ai-sdk/github-copilot"
			|| provider.id == "azure"
			|| provider.id == "azure-cognitive-services"
			|| provider.id == "github-copilot";
	}

	static function loadModel(sdk:AiSdkBundledProvider, sdkModelID:String, method:AiSdkModelMethod):AiLanguageModel {
		return switch method {
			case LanguageModel:
				sdk.languageModel(sdkModelID);
			case Chat:
				final chat = sdk.chat;
				if (chat == null)
					throw new Exception('AI SDK provider does not expose chat(modelID) for ${sdkModelID}');
				chat(sdkModelID);
			case Responses:
				final responses = sdk.responses;
				if (responses == null)
					throw new Exception('AI SDK provider does not expose responses(modelID) for ${sdkModelID}');
				responses(sdkModelID);
		}
	}

	static function usesCompletionUrls(provider:ProviderInfo, model:ProviderModel):Bool {
		return ProviderOptionAccess.bool(model.options, "useCompletionUrls", ProviderOptionAccess.bool(provider.options, "useCompletionUrls", false)) == true;
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function nonEmptyStringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null || value == "" ? Undefinable.absent() : value;
	}

	static function boolOrAbsent(value:Null<Bool>):Undefinable<Bool> {
		return value == null ? Undefinable.absent() : value;
	}

	static function headersOrAbsent(value:Null<DynamicAccess<String>>):Undefinable<DynamicAccess<String>> {
		return value == null ? Undefinable.absent() : value;
	}

	static function optionalHeadersOrAbsent(value:Null<DynamicAccess<String>>):Undefinable<AiOptionalHeaderMap> {
		if (value == null)
			return Undefinable.absent();
		final result = new DynamicAccess<Undefinable<String>>();
		for (field in value.keys()) {
			final header = value.get(field);
			if (header != null)
				result.set(field, header);
		}
		return result;
	}
}
