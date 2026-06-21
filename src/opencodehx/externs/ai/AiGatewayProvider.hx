package opencodehx.externs.ai;

import genes.ts.Undefinable;
import js.html.Headers;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.externs.ai.AiSdk.AiLanguageModelV3;

/**
 * Narrow externs for `ai-gateway-provider`.
 *
 * The package exposes a callable gateway object, but OpenCodeHX only needs the
 * stable `chat(model)` method for unified language-model routing. Keeping this
 * facade small avoids spreading the package's broader callable/provider surface
 * through application code.
 */
typedef AiGateway = {
	function chat(model:AiLanguageModelV3):AiLanguageModelV3;
}

typedef AiGatewayOptionsShape = {
	final cacheKey:Undefinable<String>;
	final cacheTtl:Undefinable<Float>;
	final skipCache:Undefinable<Bool>;
	final collectLog:Undefinable<Bool>;
	final metadata:Undefinable<AiGatewayMetadata>;
}

typedef AiGatewaySettingsShape = {
	final accountId:String;
	final gateway:String;
	final apiKey:Undefinable<String>;
	final options:Undefinable<AiGatewayOptions>;
}

typedef AiGatewayFactory = AiGatewaySettings->AiGateway;
typedef AiGatewayOptionParser = AiGatewayOptions->Headers;

typedef AiUnifiedProvider = {
	function languageModel(modelID:String):AiLanguageModelV3;
}

typedef AiUnifiedProviderFactory = Void->AiUnifiedProvider;

/**
 * Type-only bridge for Cloudflare AI Gateway metadata.
 *
 * Cloudflare accepts a JSON-ish record with primitive values plus bigint. The
 * backing type is intentionally opaque because values originate at the open
 * provider-options boundary and are forwarded, never inspected, by Haxe.
 */
@:ts.type("Record<string, number | string | boolean | null | bigint>")
abstract AiGatewayMetadata(Dynamic) {
	/**
	 * Names the dynamic provider-options boundary.
	 *
	 * The Cloudflare SDK owns the metadata schema and OpenCodeHX only forwards
	 * the value after preserving it from config. The cast is therefore contained
	 * at the SDK adapter edge instead of leaking Dynamic through route/provider
	 * logic.
	 */
	public static inline function fromBoundary(value:Dynamic):AiGatewayMetadata {
		return cast value;
	}
}

/**
 * Type-only bridge for `AiGatewayOptions`.
 *
 * The Haxe shape uses `Undefinable<T>` because absent options must emit as
 * JavaScript `undefined`, matching the package's exact optional-property type.
 */
@:forward(cacheKey, cacheTtl, skipCache, collectLog, metadata)
@:ts.type("import('ai-gateway-provider').AiGatewayOptions")
abstract AiGatewayOptions(AiGatewayOptionsShape) from AiGatewayOptionsShape to AiGatewayOptionsShape {}

/**
 * Type-only bridge for the API-token settings arm of `AiGatewaySettings`.
 */
@:forward(accountId, gateway, apiKey, options)
@:ts.type("import('ai-gateway-provider').AiGatewayAPISettings")
abstract AiGatewaySettings(AiGatewaySettingsShape) from AiGatewaySettingsShape to AiGatewaySettingsShape {}
