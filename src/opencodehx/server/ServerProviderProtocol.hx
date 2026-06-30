package opencodehx.server;

import genes.ts.JsonCodec;
import genes.ts.JsonObject;
import genes.ts.Unknown;
import haxe.Json as HaxeJson;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

typedef ProviderRouteModelMap = JsonObject;
typedef ProviderRouteDefaultModels = JsonObject;

typedef JsonEntry<T> = {
	final key:String;
	final value:T;
}

typedef ProviderRouteProvider = {
	final id:String;
	final name:String;
	final source:String;
	final env:Array<String>;
	@:optional final key:String;
	final options:ProviderOptions;
	final models:ProviderRouteModelMap;
}

typedef ConfigProvidersRouteResponse = {
	final providers:Array<ProviderRouteProvider>;
	@:native("default") final defaultModels:ProviderRouteDefaultModels;
}

typedef ProviderListRouteResponse = {
	final all:Array<ProviderRouteProvider>;
	@:native("default") final defaultModels:ProviderRouteDefaultModels;
	final connected:Array<String>;
}

/**
	Encodes provider registry records into upstream-shaped server JSON.

	Provider `options` are upstream's documented `Record<string, any>`
	passthrough boundary. `models` and `default` are also string-keyed JSON
	records because the wire contract is keyed by provider/model ID. This module
	keeps that record construction contained so routes do not leak Haxe `Map`
	values into response payloads.
**/
function encodeConfigProviders(registry:ProviderRegistry):ConfigProvidersRouteResponse {
	final providers = registry.all();
	return {
		providers: [for (provider in providers) encodeProvider(provider)],
		defaultModels: defaultModelIDs(providers),
	};
}

function encodeProviderList(providers:Array<ProviderInfo>, connected:Array<String>):ProviderListRouteResponse {
	return {
		all: [for (provider in providers) encodeProvider(provider)],
		defaultModels: defaultModelIDs(providers),
		connected: connected.copy(),
	};
}

function encodeProvider(provider:ProviderInfo):ProviderRouteProvider {
	return {
		id: provider.id.toString(),
		name: provider.name,
		source: provider.source,
		env: provider.env.copy(),
		key: provider.key,
		options: provider.options,
		models: modelMap(provider),
	};
}

function modelMap(provider:ProviderInfo):ProviderRouteModelMap {
	final entries:Array<JsonEntry<ProviderModel>> = [];
	for (model in sortedModels(provider))
		entries.push({key: model.id.toString(), value: model});
	return objectFromEntries(entries);
}

function defaultModelIDs(providers:Array<ProviderInfo>):ProviderRouteDefaultModels {
	final entries:Array<JsonEntry<String>> = [];
	for (provider in providers) {
		final models = sortedModels(provider);
		if (models.length > 0)
			entries.push({key: provider.id.toString(), value: models[0].id.toString()});
	}
	return objectFromEntries(entries);
}

function sortedModels(provider:ProviderInfo):Array<ProviderModel> {
	final models:Array<ProviderModel> = [];
	for (modelID in provider.models.keys())
		models.push(provider.models.get(modelID));
	return ProviderRegistry.sort(models);
}

function objectFromEntries<T>(entries:Array<JsonEntry<T>>):JsonObject {
	// Haxe cannot express computed-property object literals with a precise
	// recursive JSON-object type. Build this wire record through JSON's own
	// escaping/parsing rules, then validate the native object before returning it.
	final parts:Array<String> = [];
	for (entry in entries)
		parts.push(HaxeJson.stringify(entry.key) + ":" + HaxeJson.stringify(entry.value));
	final value = JsonCodec.narrowObject(Unknown.fromBoundary(HaxeJson.parse("{" + parts.join(",") + "}")));
	if (value == null)
		throw new haxe.Exception("provider route object encoding failed");
	return value;
}
