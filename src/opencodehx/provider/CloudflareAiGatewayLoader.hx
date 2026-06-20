package opencodehx.provider;

import genes.ts.Imports;
import genes.ts.Undefinable;
import haxe.Exception;
import opencodehx.externs.ai.AiGatewayProvider.AiGatewayFactory;
import opencodehx.externs.ai.AiGatewayProvider.AiGatewayMetadata;
import opencodehx.externs.ai.AiGatewayProvider.AiGatewayOptions;
import opencodehx.externs.ai.AiGatewayProvider.AiGatewaySettings;
import opencodehx.externs.ai.AiGatewayProvider.AiUnifiedProviderFactory;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiSdkBundledProvider;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

class CloudflareAiGatewayLoader {
	static final createAiGateway:AiGatewayFactory = Imports.namedImport("ai-gateway-provider", "createAiGateway", "createAiGateway");
	static final createUnified:AiUnifiedProviderFactory = Imports.namedImport("ai-gateway-provider/providers/unified", "createUnified", "createUnified");

	public static function sdk(provider:ProviderInfo, model:ProviderModel):AiSdkBundledProvider {
		return {
			languageModel: modelID -> languageModel(provider, model, modelID),
		};
	}

	public static function languageModel(provider:ProviderInfo, model:ProviderModel, modelID:String):AiLanguageModel {
		final gateway = createAiGateway(settings(provider, model));
		final unified = createUnified();
		return gateway.chat(unified.languageModel(modelID));
	}

	public static function settings(provider:ProviderInfo, model:ProviderModel):AiGatewaySettings {
		final accountID = ProviderOptionAccess.string(provider.options, "accountId", "");
		final gatewayID = ProviderOptionAccess.string(provider.options, "gatewayId", "");
		if (accountID == null || accountID == "" || gatewayID == null || gatewayID == "")
			throw new Exception('Provider ${provider.id} model ${model.id} needs Cloudflare accountId and gatewayId before SDK loading');
		final apiKey = ProviderOptionAccess.string(provider.options, "apiKey", provider.key);
		if (apiKey == null || apiKey == "")
			throw new Exception('Provider ${provider.id} model ${model.id} needs Cloudflare apiKey before SDK loading');
		return {
			accountId: accountID,
			gateway: gatewayID,
			apiKey: apiKey,
			options: gatewayOptions(provider.options),
		};
	}

	static function gatewayOptions(options:ProviderOptions):Undefinable<AiGatewayOptions> {
		final out:AiGatewayOptions = {
			cacheKey: stringOrAbsent(ProviderOptionAccess.string(options, "cacheKey", null)),
			cacheTtl: floatOrAbsent(ProviderOptionAccess.numberValue(options, "cacheTtl", null)),
			skipCache: boolOrAbsent(ProviderOptionAccess.bool(options, "skipCache", null)),
			collectLog: boolOrAbsent(ProviderOptionAccess.bool(options, "collectLog", null)),
			metadata: metadataOrAbsent(options),
		};
		return hasGatewayOptions(options) ? out : Undefinable.absent();
	}

	static function hasGatewayOptions(options:ProviderOptions):Bool {
		return ProviderOptionAccess.string(options, "cacheKey", null) != null
			|| ProviderOptionAccess.numberValue(options, "cacheTtl", null) != null
			|| ProviderOptionAccess.bool(options, "skipCache", null) != null
			|| ProviderOptionAccess.bool(options, "collectLog", null) != null
			|| options.exists("metadata");
	}

	static function metadataOrAbsent(options:ProviderOptions):Undefinable<AiGatewayMetadata> {
		if (!options.exists("metadata"))
			return Undefinable.absent();
		// Cloudflare metadata is provider-owned passthrough data. The registry
		// preserves the config object, this loader forwards it, and Haxe never
		// reads fields from the opaque record.
		final value = options.get("metadata");
		return value == null ? Undefinable.absent() : AiGatewayMetadata.fromBoundary(value);
	}

	static function stringOrAbsent(value:Null<String>):Undefinable<String> {
		return value == null ? Undefinable.absent() : value;
	}

	static function floatOrAbsent(value:Null<Float>):Undefinable<Float> {
		return value == null ? Undefinable.absent() : value;
	}

	static function boolOrAbsent(value:Null<Bool>):Undefinable<Bool> {
		return value == null ? Undefinable.absent() : value;
	}
}
