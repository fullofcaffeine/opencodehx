package opencodehx.server;

import genes.ts.JsonCodec;
import genes.ts.JsonObject;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.Json as HaxeJson;
import opencodehx.plugin.PluginAuthHooks.PluginAuthHook;
import opencodehx.plugin.PluginAuthHooks.PluginAuthMethod;
import opencodehx.plugin.PluginAuthHooks.PluginAuthMethodType;
import opencodehx.plugin.PluginAuthHooks.PluginAuthPrompt;
import opencodehx.plugin.PluginAuthHooks.PluginAuthPromptWhen;
import opencodehx.plugin.PluginAuthHooks.PluginAuthPromptWhenOp;
import opencodehx.plugin.PluginAuthHooks.PluginAuthSelectOption;
import opencodehx.plugin.PluginAuthHooks.PluginAuthInput;
import opencodehx.plugin.PluginAuthHooks.PluginAuthAuthorizationMethod;
import opencodehx.provider.ProviderAuthRuntime.ProviderAuthRuntimeAuthorization;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.server.ServerProtocol.DecodeResult;

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

typedef ProviderAuthRouteResponse = JsonObject;

typedef ProviderAuthRouteWhen = {
	final key:String;
	final op:PluginAuthPromptWhenOp;
	final value:String;
}

typedef ProviderAuthRouteSelectOption = JsonObject;
typedef ProviderAuthRoutePrompt = JsonObject;
typedef ProviderAuthRouteMethod = JsonObject;

typedef ProviderAuthAuthorizeRouteRequest = {
	final method:Int;
	final inputs:Null<Array<PluginAuthInput>>;
}

typedef ProviderAuthCallbackRouteRequest = {
	final method:Int;
	final code:Null<String>;
}

typedef ProviderAuthAuthorizationRouteResponse = {
	final url:String;
	final method:PluginAuthAuthorizationMethod;
	final instructions:String;
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

function encodeProviderAuthMethods(hooks:Array<PluginAuthHook>):ProviderAuthRouteResponse {
	final entries:Array<JsonEntry<Array<ProviderAuthRouteMethod>>> = [];
	for (hook in hooks)
		entries.push({
			key: hook.provider.toString(),
			value: [for (method in hook.methods) encodeAuthMethod(method)],
		});
	return objectFromEntries(entries);
}

function encodeProviderAuthAuthorization(authorization:ProviderAuthRuntimeAuthorization):ProviderAuthAuthorizationRouteResponse {
	return {
		url: authorization.url,
		method: authorization.method,
		instructions: authorization.instructions,
	};
}

function decodeProviderAuthAuthorize(raw:Unknown):DecodeResult<ProviderAuthAuthorizeRouteRequest> {
	return switch decodeMethod(raw) {
		case Rejected(message):
			Rejected(message);
		case Decoded(method):
			switch decodeInputs(raw) {
				case Rejected(message):
					Rejected(message);
				case Decoded(inputs):
					Decoded({method: method, inputs: inputs});
			}
	}
}

function decodeProviderAuthCallback(raw:Unknown):DecodeResult<ProviderAuthCallbackRouteRequest> {
	return switch decodeMethod(raw) {
		case Rejected(message):
			Rejected(message);
		case Decoded(method):
			switch decodeOptionalString(raw, "code") {
				case Rejected(message):
					Rejected(message);
				case Decoded(code):
					Decoded({method: method, code: code});
			}
	}
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

function encodeAuthMethod(method:PluginAuthMethod):ProviderAuthRouteMethod {
	final parts = [jsonField("type", method.type), jsonField("label", method.label),];
	final prompts = method.prompts.orNull();
	if (prompts != null)
		parts.push(jsonField("prompts", encodeAuthPrompts(prompts)));
	return objectFromParts(parts);
}

function encodeAuthPrompts(prompts:Array<PluginAuthPrompt>):Array<ProviderAuthRoutePrompt> {
	return [for (prompt in prompts) encodeAuthPrompt(prompt)];
}

function encodeAuthPrompt(prompt:PluginAuthPrompt):ProviderAuthRoutePrompt {
	return switch prompt {
		case Text(value):
			final parts = [
				jsonField("type", "text"),
				jsonField("key", value.key),
				jsonField("message", value.message),
			];
			final placeholder = value.placeholder.orNull();
			final when = value.when.orNull();
			if (placeholder != null)
				parts.push(jsonField("placeholder", placeholder));
			if (when != null)
				parts.push(jsonField("when", encodeAuthWhen(when)));
			objectFromParts(parts);
		case Select(value):
			final parts = [
				jsonField("type", "select"),
				jsonField("key", value.key),
				jsonField("message", value.message),
				jsonField("options", [for (option in value.options) encodeAuthOption(option)]),
			];
			final when = value.when.orNull();
			if (when != null)
				parts.push(jsonField("when", encodeAuthWhen(when)));
			objectFromParts(parts);
	};
}

function encodeAuthWhen(when:PluginAuthPromptWhen):ProviderAuthRouteWhen {
	return {
		key: when.key,
		op: when.op,
		value: when.value,
	};
}

function encodeAuthOption(option:PluginAuthSelectOption):ProviderAuthRouteSelectOption {
	final parts = [jsonField("label", option.label), jsonField("value", option.value),];
	final hint = option.hint.orNull();
	if (hint != null)
		parts.push(jsonField("hint", hint));
	return objectFromParts(parts);
}

function decodeMethod(raw:Unknown):DecodeResult<Int> {
	final record = UnknownNarrow.record(raw);
	if (record == null)
		return Rejected("body: expected object");
	if (!record.hasOwn("method"))
		return Rejected("method: expected integer");
	final method = UnknownNarrow.int32(record.get("method"));
	return method == null || method < 0 ? Rejected("method: expected non-negative integer") : Decoded(method);
}

function decodeInputs(raw:Unknown):DecodeResult<Null<Array<PluginAuthInput>>> {
	final record = UnknownNarrow.record(raw);
	if (record == null)
		return Rejected("body: expected object");
	if (!record.hasOwn("inputs") || UnknownNarrow.isNull(record.get("inputs")) || UnknownNarrow.isUndefined(record.get("inputs")))
		return Decoded(null);
	final inputRecord = UnknownNarrow.record(record.get("inputs"));
	if (inputRecord == null)
		return Rejected("inputs: expected object");
	final out:Array<PluginAuthInput> = [];
	for (key in inputRecord.keys()) {
		final value = UnknownNarrow.string(inputRecord.get(key));
		if (value == null)
			return Rejected('inputs.${key}: expected string');
		out.push({key: key, value: value});
	}
	out.sort((left, right) -> compareString(left.key, right.key));
	return Decoded(out);
}

function decodeOptionalString(raw:Unknown, field:String):DecodeResult<Null<String>> {
	final record = UnknownNarrow.record(raw);
	if (record == null)
		return Rejected("body: expected object");
	if (!record.hasOwn(field) || UnknownNarrow.isNull(record.get(field)) || UnknownNarrow.isUndefined(record.get(field)))
		return Decoded(null);
	final value = UnknownNarrow.string(record.get(field));
	return value == null ? Rejected('${field}: expected string') : Decoded(value);
}

function compareString(left:String, right:String):Int {
	if (left == right)
		return 0;
	return left < right ? -1 : 1;
}

function objectFromEntries<T>(entries:Array<JsonEntry<T>>):JsonObject {
	// Haxe cannot express computed-property object literals with a precise
	// recursive JSON-object type. Build this wire record through JSON's own
	// escaping/parsing rules, then validate the native object before returning it.
	final parts:Array<String> = [];
	for (entry in entries)
		parts.push(jsonField(entry.key, entry.value));
	return objectFromParts(parts);
}

function objectFromParts(parts:Array<String>):JsonObject {
	final value = JsonCodec.narrowObject(Unknown.fromBoundary(HaxeJson.parse("{" + parts.join(",") + "}")));
	if (value == null)
		throw new haxe.Exception("provider route object encoding failed");
	return value;
}

function jsonField<T>(key:String, value:T):String {
	return HaxeJson.stringify(key) + ":" + HaxeJson.stringify(value);
}
