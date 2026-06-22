package opencodehx.provider;

import genes.ts.Imports;
import genes.ts.Unknown;
import genes.ts.Undefinable;
import haxe.DynamicAccess;
import haxe.Exception;
import opencodehx.externs.aws.AwsCredentialProviders.AwsCredentialProvider;
import opencodehx.externs.aws.AwsCredentialProviders.AwsNodeProviderChainFactory;
import opencodehx.externs.aws.AwsCredentialProviders.AwsNodeProviderChainOptions;
import opencodehx.externs.ai.AiSdk.AiAnthropicFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiAnthropicProviderFactory;
import opencodehx.externs.ai.AiSdk.AiAlibabaFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiAlibabaProviderFactory;
import opencodehx.externs.ai.AiSdk.AiAzureFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiAzureProviderFactory;
import opencodehx.externs.ai.AiSdk.AiBedrockFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiBedrockProviderFactory;
import opencodehx.externs.ai.AiSdk.AiCerebrasFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiCerebrasProviderFactory;
import opencodehx.externs.ai.AiSdk.AiCohereFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiCohereProviderFactory;
import opencodehx.externs.ai.AiSdk.AiDeepInfraFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiDeepInfraProviderFactory;
import opencodehx.externs.ai.AiSdk.AiGatewayFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiGatewayProviderFactory;
import opencodehx.externs.ai.AiSdk.AiGitLabFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiGitLabFactoryOptionsShape;
import opencodehx.externs.ai.AiSdk.AiGitLabProviderFactory;
import opencodehx.externs.ai.AiSdk.AiGoogleFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiGoogleProviderFactory;
import opencodehx.externs.ai.AiSdk.AiGroqFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiGroqProviderFactory;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiMistralFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiMistralProviderFactory;
import opencodehx.externs.ai.AiSdk.AiOptionalHeaderMap;
import opencodehx.externs.ai.AiSdk.AiOpenAIFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiOpenAIProviderFactory;
import opencodehx.externs.ai.AiSdk.AiOpenRouterCompatibility;
import opencodehx.externs.ai.AiSdk.AiOpenRouterFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiOpenRouterProviderFactory;
import opencodehx.externs.ai.AiSdk.AiPerplexityFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiPerplexityProviderFactory;
import opencodehx.externs.ai.AiSdk.AiSdkBundledProvider;
import opencodehx.externs.ai.AiSdk.AiSdkFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiSdkProviderFactory;
import opencodehx.externs.ai.AiSdk.AiSimpleFactoryOptionsShape;
import opencodehx.externs.ai.AiSdk.AiTogetherAIFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiTogetherAIProviderFactory;
import opencodehx.externs.ai.AiSdk.AiVercelFactoryOptions;
import opencodehx.externs.ai.AiSdk.AiVercelProviderFactory;
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
	static final createMistral:AiMistralProviderFactory = Imports.namedImport("@ai-sdk/mistral", "createMistral", "createMistral");
	static final createGroq:AiGroqProviderFactory = Imports.namedImport("@ai-sdk/groq", "createGroq", "createGroq");
	static final createCohere:AiCohereProviderFactory = Imports.namedImport("@ai-sdk/cohere", "createCohere", "createCohere");
	static final createPerplexity:AiPerplexityProviderFactory = Imports.namedImport("@ai-sdk/perplexity", "createPerplexity", "createPerplexity");
	static final createOpenRouter:AiOpenRouterProviderFactory = Imports.namedImport("@openrouter/ai-sdk-provider", "createOpenRouter", "createOpenRouter");
	static final createDeepInfra:AiDeepInfraProviderFactory = Imports.namedImport("@ai-sdk/deepinfra", "createDeepInfra", "createDeepInfra");
	static final createCerebras:AiCerebrasProviderFactory = Imports.namedImport("@ai-sdk/cerebras", "createCerebras", "createCerebras");
	static final createGateway:AiGatewayProviderFactory = Imports.namedImport("@ai-sdk/gateway", "createGateway", "createGateway");
	static final createTogetherAI:AiTogetherAIProviderFactory = Imports.namedImport("@ai-sdk/togetherai", "createTogetherAI", "createTogetherAI");
	static final createVercel:AiVercelProviderFactory = Imports.namedImport("@ai-sdk/vercel", "createVercel", "createVercel");
	static final createAlibaba:AiAlibabaProviderFactory = Imports.namedImport("@ai-sdk/alibaba", "createAlibaba", "createAlibaba");
	static final createGitLab:AiGitLabProviderFactory = Imports.namedImport("gitlab-ai-provider", "createGitLab", "createGitLab");
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
			case "@ai-sdk/mistral":
				createMistral(mistralFactoryOptions(provider, model));
			case "@ai-sdk/groq":
				createGroq(groqFactoryOptions(provider, model));
			case "@ai-sdk/cohere":
				createCohere(cohereFactoryOptions(provider, model));
			case "@ai-sdk/perplexity":
				createPerplexity(perplexityFactoryOptions(provider, model));
			case "@openrouter/ai-sdk-provider":
				createOpenRouter(openRouterFactoryOptions(provider, model));
			case "@ai-sdk/deepinfra":
				createDeepInfra(deepInfraFactoryOptions(provider, model));
			case "@ai-sdk/cerebras":
				createCerebras(cerebrasFactoryOptions(provider, model));
			case "@ai-sdk/gateway":
				createGateway(gatewayFactoryOptions(provider, model));
			case "@ai-sdk/togetherai":
				createTogetherAI(togetherAIFactoryOptions(provider, model));
			case "@ai-sdk/vercel":
				createVercel(vercelFactoryOptions(provider, model));
			case "@ai-sdk/alibaba":
				createAlibaba(alibabaFactoryOptions(provider, model));
			case "gitlab-ai-provider":
				createGitLab(gitLabFactoryOptions(provider, model));
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

	public static function mistralFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiMistralFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function groqFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiGroqFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function cohereFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiCohereFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function perplexityFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiPerplexityFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function openRouterFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiOpenRouterFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
			compatibility: openRouterCompatibilityOrAbsent(ProviderOptionAccess.string(provider.options, "compatibility", null)),
			extraBody: unknownRecordOrAbsent(ProviderOptionAccess.unknownRecord(provider.options, "extraBody")),
			api_keys: stringMapOrAbsent(ProviderOptionAccess.stringMap(provider.options, "api_keys")),
			appName: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "appName", null)),
			appUrl: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "appUrl", null)),
		};
	}

	public static function deepInfraFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiDeepInfraFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function cerebrasFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiCerebrasFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function gatewayFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiGatewayFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function togetherAIFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiTogetherAIFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function vercelFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiVercelFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function alibabaFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiAlibabaFactoryOptions {
		return simpleFactoryOptions(provider, model);
	}

	public static function gitLabFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiGitLabFactoryOptions {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		final options:AiGitLabFactoryOptionsShape = {
			instanceUrl: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "instanceUrl",
				ProviderOptionAccess.baseURL(provider.options, model))),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
			name: stringOrAbsent(provider.id.toString()),
			featureFlags: boolMapOrAbsent(ProviderOptionAccess.boolMap(provider.options, "featureFlags")),
			aiGatewayUrl: nonEmptyStringOrAbsent(ProviderOptionAccess.string(provider.options, "aiGatewayUrl", null)),
			aiGatewayHeaders: headersOrAbsent(ProviderOptionAccess.stringMap(provider.options, "aiGatewayHeaders")),
		};
		return options;
	}

	static function simpleFactoryOptions(provider:ProviderInfo, model:ProviderModel):AiSimpleFactoryOptionsShape {
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		return {
			baseURL: nonEmptyStringOrAbsent(ProviderOptionAccess.baseURL(provider.options, model)),
			apiKey: nonEmptyStringOrAbsent(apiKey),
			headers: headersOrAbsent(ProviderOptionAccess.headers(provider.options, model.headers)),
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

	static function boolMapOrAbsent(value:Null<DynamicAccess<Bool>>):Undefinable<DynamicAccess<Bool>> {
		return value == null ? Undefinable.absent() : value;
	}

	static function stringMapOrAbsent(value:Null<DynamicAccess<String>>):Undefinable<DynamicAccess<String>> {
		return value == null ? Undefinable.absent() : value;
	}

	static function unknownRecordOrAbsent(value:Null<DynamicAccess<Unknown>>):Undefinable<DynamicAccess<Unknown>> {
		return value == null ? Undefinable.absent() : value;
	}

	static function openRouterCompatibilityOrAbsent(value:Null<String>):Undefinable<AiOpenRouterCompatibility> {
		return switch value {
			case "strict":
				AiOpenRouterCompatibility.Strict;
			case "compatible":
				AiOpenRouterCompatibility.Compatible;
			case _:
				Undefinable.absent();
		}
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
