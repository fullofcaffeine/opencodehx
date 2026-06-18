package opencodehx.provider;

import haxe.Json;
import js.Syntax;
import opencodehx.config.ConfigInfo;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ParsedModelRef;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;

typedef ProviderRegistryInput = {
	final config:ConfigInfo;
	@:optional final env:Dynamic;
	@:optional final auth:Dynamic;
	@:optional final database:Map<String, ProviderInfo>;
}

class ProviderRegistry {
	final providers:Map<String, ProviderInfo>;
	final config:ConfigInfo;

	public function new(input:ProviderRegistryInput) {
		config = input.config;
		providers = build(input);
	}

	public function list():Map<String, ProviderInfo> {
		return providers;
	}

	public function all():Array<ProviderInfo> {
		final result:Array<ProviderInfo> = [];
		for (id in providers.keys())
			result.push(providers.get(id));
		result.sort((a, b) -> Reflect.compare(a.id.toString(), b.id.toString()));
		return result;
	}

	public function getProvider(providerID:ProviderID):ProviderInfo {
		return providers.get(providerID.toString());
	}

	public function getModel(providerID:ProviderID, modelID:ModelID):ProviderModel {
		final provider = providers.get(providerID.toString());
		if (provider == null)
			throw notFound(providerID, modelID, providerSuggestions(providerID.toString()));
		final model = provider.models.get(modelID.toString());
		if (model == null)
			throw notFound(providerID, modelID, modelSuggestions(provider, modelID.toString()));
		return model;
	}

	public function closest(providerID:ProviderID, query:Array<String>):Null<ParsedModelRef> {
		final provider = providers.get(providerID.toString());
		if (provider == null)
			return null;
		for (item in query) {
			for (modelID in provider.models.keys()) {
				if (modelID.indexOf(item) != -1)
					return {providerID: providerID, modelID: ModelID.make(modelID)};
			}
		}
		return null;
	}

	public function defaultModel():ParsedModelRef {
		if (config.model != null)
			return parseModel(config.model);
		final available = all();
		if (available.length == 0)
			throw new ProviderException(NoProviders);
		final provider = available[0];
		final model = sortedModels(provider.models)[0];
		if (model == null)
			throw new ProviderException(NoProviders);
		return {providerID: provider.id, modelID: model.id};
	}

	public function smallModel(providerID:ProviderID):Null<ProviderModel> {
		if (config.smallModel != null) {
			final parsed = parseModel(config.smallModel);
			return getModel(parsed.providerID, parsed.modelID);
		}
		final provider = providers.get(providerID.toString());
		if (provider == null)
			return null;
		var priority = [
			"claude-haiku-4-5",
			"claude-haiku-4.5",
			"3-5-haiku",
			"3.5-haiku",
			"gemini-3-flash",
			"gemini-2.5-flash",
			"gpt-5-nano"
		];
		if (StringTools.startsWith(providerID.toString(), "opencode"))
			priority = ["gpt-5-nano"];
		if (StringTools.startsWith(providerID.toString(), "github-copilot"))
			priority = ["gpt-5-mini", "claude-haiku-4.5"].concat(priority);
		for (needle in priority) {
			for (modelID in provider.models.keys()) {
				if (modelID.indexOf(needle) != -1)
					return provider.models.get(modelID);
			}
		}
		return null;
	}

	public static function parseModel(model:String):ParsedModelRef {
		final parts = model.split("/");
		final providerID = parts.shift();
		return {
			providerID: ProviderID.make(providerID == null ? "" : providerID),
			modelID: ModelID.make(parts.join("/")),
		};
	}

	static function build(input:ProviderRegistryInput):Map<String, ProviderInfo> {
		final database = input.database == null ? defaultDatabase() : cloneProviders(input.database);
		final providers = new Map<String, ProviderInfo>();
		final disabled = stringSet(input.config.disabledProviders);
		final enabled = input.config.enabledProviders == null ? null : stringSet(input.config.enabledProviders);
		final configProviders = providerConfigEntries(input.config.provider);

		for (configDatabaseID in configProviders.keys()) {
			final configDatabaseValue = configProviders.get(configDatabaseID);
			final configuredProvider = providerFromConfig(configDatabaseID, configDatabaseValue, database.get(configDatabaseID));
			database.set(configDatabaseID, configuredProvider);
		}

		final env = input.env == null ? Syntax.code("({ ...process.env })") : input.env;
		for (envProviderID in database.keys()) {
			if (disabled.exists(envProviderID))
				continue;
			final envProvider = database.get(envProviderID);
			final envKey = firstEnv(envProvider.env, env);
			if (envKey == null)
				continue;
			providers.set(envProviderID, withPatch(envProvider, {
				source: "env",
				key: envProvider.env.length == 1 ? envKey : null,
			}));
		}

		final auths = authEntries(input.auth);
		for (authProviderID in auths.keys()) {
			if (disabled.exists(authProviderID))
				continue;
			final authEntry = auths.get(authProviderID);
			if (authEntry.type != "api")
				continue;
			final authProvider = database.get(authProviderID);
			if (authProvider != null)
				providers.set(authProviderID, withPatch(authProvider, {source: "api", key: authEntry.key}));
		}

		for (configLoadID in configProviders.keys()) {
			if (disabled.exists(configLoadID))
				continue;
			final configLoadValue = configProviders.get(configLoadID);
			final configBaseProvider = database.get(configLoadID);
			if (configBaseProvider == null)
				continue;
			providers.set(configLoadID, withPatch(providers.exists(configLoadID) ? providers.get(configLoadID) : configBaseProvider, {
				source: "config",
				env: strings(Reflect.field(configLoadValue, "env"), configBaseProvider.env),
				name: stringOr(Reflect.field(configLoadValue, "name"), configBaseProvider.name),
				options: mergeObject(configBaseProvider.options, Reflect.field(configLoadValue, "options")),
			}));
		}

		final bedrock = database.get("amazon-bedrock");
		if (bedrock != null && !disabled.exists("amazon-bedrock")) {
			final bedrockAlreadyLoaded = providers.exists("amazon-bedrock");
			final bedrockBase = bedrockAlreadyLoaded ? providers.get("amazon-bedrock") : bedrock;
			final bedrockResolved = bedrockOptions(bedrockBase, bedrock, env, auths.get("amazon-bedrock"));
			if (bedrockAlreadyLoaded || bedrockResolved.autoload) {
				providers.set("amazon-bedrock", withPatch(bedrockBase, {
					source: bedrockAlreadyLoaded ? bedrockBase.source : "custom",
					options: bedrockResolved.autoload ? bedrockResolved.options : bedrockBase.options,
				}));
			}
		}

		for (filterProviderID in database.keys()) {
			if (!providers.exists(filterProviderID))
				continue;
			if (enabled != null && !enabled.exists(filterProviderID)) {
				providers.remove(filterProviderID);
				continue;
			}
			if (disabled.exists(filterProviderID)) {
				providers.remove(filterProviderID);
				continue;
			}
			final filterConfig = configProviders.get(filterProviderID);
			final filtered = filterProviderModels(providers.get(filterProviderID), filterConfig);
			if (filtered.models.iterator().hasNext())
				providers.set(filterProviderID, filtered);
			else
				providers.remove(filterProviderID);
		}
		return providers;
	}

	static function providerFromConfig(id:String, config:Dynamic, existing:Null<ProviderInfo>):ProviderInfo {
		final providerID = ProviderID.make(id);
		final env = strings(Reflect.field(config, "env"), existing == null ? [] : existing.env);
		final name = stringOr(Reflect.field(config, "name"), existing == null ? id : existing.name);
		final options:ProviderOptions = cast mergeObject(existing == null ? {} : existing.options, Reflect.field(config, "options"));
		final models = existing == null ? new Map<String, ProviderModel>() : cloneModels(existing.models);
		final modelConfig:Dynamic = Reflect.field(config, "models");
		if (isRecord(modelConfig)) {
			for (modelID in Reflect.fields(modelConfig)) {
				final modelData = Reflect.field(modelConfig, modelID);
				models.set(modelID, modelFromConfig(providerID, modelID, modelData, models.get(modelID), config, existing));
			}
		}
		return {
			id: providerID,
			name: name,
			source: "config",
			env: env,
			options: options,
			models: models,
		};
	}

	static function modelFromConfig(providerID:ProviderID, modelID:String, data:Dynamic, existing:Null<ProviderModel>, providerConfig:Dynamic,
			existingProvider:Null<ProviderInfo>):ProviderModel {
		final upstreamID = stringOr(Reflect.field(data, "id"), existing == null ? modelID : existing.api.id);
		final modelName = stringOr(Reflect.field(data, "name"), existing == null ? modelID : existing.name);
		final apiConfig:Dynamic = Reflect.field(data, "provider");
		final npm = stringOr(isRecord(apiConfig) ? Reflect.field(apiConfig, "npm") : null,
			stringOr(Reflect.field(providerConfig, "npm"), existing == null ? "@ai-sdk/openai-compatible" : existing.api.npm));
		final apiUrl = stringOr(isRecord(apiConfig) ? Reflect.field(apiConfig, "api") : null,
			stringOr(Reflect.field(providerConfig, "api"), existing == null ? "" : existing.api.url));
		return {
			id: ModelID.make(modelID),
			providerID: providerID,
			name: modelName,
			family: stringOr(Reflect.field(data, "family"), existing == null ? "" : existing.family),
			api: {
				id: upstreamID,
				url: apiUrl,
				npm: npm
			},
			status: stringOr(Reflect.field(data, "status"), existing == null ? "active" : existing.status),
			capabilities: {
				temperature: boolOr(Reflect.field(data, "temperature"), existing == null ? false : existing.capabilities.temperature),
				reasoning: boolOr(Reflect.field(data, "reasoning"), existing == null ? false : existing.capabilities.reasoning),
				attachment: boolOr(Reflect.field(data, "attachment"), existing == null ? false : existing.capabilities.attachment),
				toolcall: boolOr(Reflect.field(data, "tool_call"), existing == null ? true : existing.capabilities.toolcall),
				input: modality(Reflect.field(data, "modalities"), "input", existing == null ? null : existing.capabilities.input, true),
				output: modality(Reflect.field(data, "modalities"), "output", existing == null ? null : existing.capabilities.output, true),
				interleaved: Reflect.hasField(data,
					"interleaved") ? Reflect.field(data, "interleaved") : existing == null ? false : existing.capabilities.interleaved,
			},
			cost: costFrom(Reflect.field(data, "cost"), existing == null ? null : existing.cost),
			options: cast mergeObject(existing == null ? {} : existing.options, Reflect.field(data, "options")),
			headers: cast mergeObject(existing == null ? {} : existing.headers, Reflect.field(data, "headers")),
			limit: limitFrom(Reflect.field(data, "limit"), existing == null ? null : existing.limit),
			release_date: stringOr(Reflect.field(data, "release_date"), existing == null ? "" : existing.release_date),
			variants: cast mergeObject(existing == null ? {} : existing.variants, Reflect.field(data, "variants")),
		};
	}

	static function defaultDatabase():Map<String, ProviderInfo> {
		final result = new Map<String, ProviderInfo>();
		final anthropic = provider("anthropic", "Anthropic", ["ANTHROPIC_API_KEY"], [
			model("anthropic", "claude-sonnet-4-20250514", "Claude Sonnet 4", "@ai-sdk/anthropic", "https://api.anthropic.com/v1", 200000, 64000,
				{
					reasoning: true,
					attachment: true
				}),
			model("anthropic", "claude-haiku-4-5", "Claude Haiku 4.5", "@ai-sdk/anthropic", "https://api.anthropic.com/v1", 200000, 32000,
				{reasoning: true, attachment: true}),
		]);
		add(result, withPatch(anthropic, {options: {headers: {"anthropic-beta": "interleaved-thinking-2025-05-14,fine-grained-tool-streaming-2025-05-14"}}}));
		add(result, provider("openai", "OpenAI", ["OPENAI_API_KEY"], [
			model("openai", "gpt-5.2", "GPT-5.2", "@ai-sdk/openai", "https://api.openai.com/v1", 200000, 10000, {
				reasoning: true
			}),
			model("openai", "gpt-5-nano", "GPT-5 nano", "@ai-sdk/openai", "https://api.openai.com/v1", 200000, 10000, {reasoning: true}),
		]));
		add(result, provider("amazon-bedrock", "Amazon Bedrock", ["AWS_ACCESS_KEY_ID", "AWS_BEARER_TOKEN_BEDROCK"], [
			model("amazon-bedrock", "anthropic.claude-sonnet-4-20250514-v1:0", "Claude Sonnet 4", "@ai-sdk/amazon-bedrock", "", 200000, 64000,
				{
					reasoning: true,
					attachment: true
				}),
			model("amazon-bedrock", "global.anthropic.claude-haiku-4-5-20250929-v1:0", "Claude Haiku 4.5", "@ai-sdk/amazon-bedrock", "", 200000, 32000,
				{reasoning: true, attachment: true}),
		]));
		add(result, provider("opencode", "opencode", [], [
			model("opencode", "gpt-5-nano", "GPT-5 nano", "@ai-sdk/openai-compatible", "https://api.opencode.ai/v1", 200000, 10000, {
				reasoning: true
			}),
		]));
		return result;
	}

	static function provider(id:String, name:String, env:Array<String>, models:Array<ProviderModel>):ProviderInfo {
		final map = new Map<String, ProviderModel>();
		for (model in models)
			map.set(model.id.toString(), model);
		return {
			id: ProviderID.make(id),
			name: name,
			source: "custom",
			env: env,
			options: {},
			models: map,
		};
	}

	static function model(providerID:String, id:String, name:String, npm:String, url:String, context:Float, output:Float, flags:Dynamic):ProviderModel {
		final reasoning = boolOr(Reflect.field(flags, "reasoning"), false);
		final attachment = boolOr(Reflect.field(flags, "attachment"), false);
		return {
			id: ModelID.make(id),
			providerID: ProviderID.make(providerID),
			name: name,
			api: {id: id, url: url, npm: npm},
			status: "active",
			capabilities: {
				temperature: true,
				reasoning: reasoning,
				attachment: attachment,
				toolcall: true,
				input: {
					text: true,
					image: attachment,
					audio: false,
					video: false,
					pdf: attachment
				},
				output: {
					text: true,
					image: false,
					audio: false,
					video: false,
					pdf: false
				},
				interleaved: false,
			},
			cost: {input: 0, output: 0, cache: {read: 0, write: 0}},
			limit: {context: context, output: output},
			options: {},
			headers: {},
			release_date: "",
			variants: {},
		};
	}

	static function filterProviderModels(provider:ProviderInfo, configEntry:Dynamic):ProviderInfo {
		final models = new Map<String, ProviderModel>();
		final whitelistValues = configEntry == null ? null : optionalStrings(Reflect.field(configEntry, "whitelist"));
		final whitelist = whitelistValues == null ? null : stringSet(whitelistValues);
		final blacklistValues = configEntry == null ? null : optionalStrings(Reflect.field(configEntry, "blacklist"));
		final blacklist = blacklistValues == null ? new Map<String, Bool>() : stringSet(blacklistValues);
		for (modelID in provider.models.keys()) {
			final model = provider.models.get(modelID);
			if (model.status == "deprecated")
				continue;
			if (whitelist != null && !whitelist.exists(modelID))
				continue;
			if (blacklist.exists(modelID))
				continue;
			models.set(modelID, model);
		}
		return withPatch(provider, {models: models});
	}

	static function sortedModels(models:Map<String, ProviderModel>):Array<ProviderModel> {
		final result:Array<ProviderModel> = [];
		for (id in models.keys())
			result.push(models.get(id));
		result.sort((a, b) -> {
			final pa = priority(a.id.toString());
			final pb = priority(b.id.toString());
			if (pa != pb)
				return pb - pa;
			final la = a.id.toString().indexOf("latest") == -1 ? 1 : 0;
			final lb = b.id.toString().indexOf("latest") == -1 ? 1 : 0;
			if (la != lb)
				return la - lb;
			return Reflect.compare(b.id.toString(), a.id.toString());
		});
		return result;
	}

	static function priority(id:String):Int {
		final filters = ["gpt-5", "claude-sonnet-4", "big-pickle", "gemini-3-pro"];
		for (index in 0...filters.length) {
			if (id.indexOf(filters[index]) != -1)
				return index;
		}
		return -1;
	}

	static function providerConfigEntries(data:Dynamic):Map<String, Dynamic> {
		final result = new Map<String, Dynamic>();
		if (!isRecord(data))
			return result;
		for (id in Reflect.fields(data))
			result.set(id, Reflect.field(data, id));
		return result;
	}

	static function authEntries(data:Dynamic):Map<String, {final type:String; final key:String; final metadata:Dynamic;}> {
		final result = new Map<String, {final type:String; final key:String; final metadata:Dynamic;}>();
		var raw = data;
		if (raw == null) {
			final text:Null<String> = Syntax.code("process.env.OPENCODE_AUTH_CONTENT ?? null");
			if (text != null && text != "") {
				try {
					raw = Json.parse(text);
				} catch (_:Dynamic) {}
			}
		}
		if (!isRecord(raw))
			return result;
		for (id in Reflect.fields(raw)) {
			final item = Reflect.field(raw, id);
			if (!isRecord(item))
				continue;
			final type = stringOr(Reflect.field(item, "type"), "");
			final key = stringOr(Reflect.field(item, "key"), "");
			if (type != "" && key != "")
				result.set(trimRightSlashes(id), {type: type, key: key, metadata: Reflect.field(item, "metadata")});
		}
		return result;
	}

	static function bedrockOptions(bedrock:ProviderInfo, database:ProviderInfo, env:Dynamic,
			auth:Null<{final type:String; final key:String; final metadata:Dynamic;}>):{final autoload:Bool; final options:ProviderOptions;} {
		final configOptions = bedrock.options;
		final region = stringOr(Reflect.field(configOptions, "region"), stringOr(Reflect.field(env, "AWS_REGION"), "us-east-1"));
		final profile = stringOr(Reflect.field(configOptions, "profile"), stringOr(Reflect.field(env, "AWS_PROFILE"), ""));
		final accessKey = stringOr(Reflect.field(env, "AWS_ACCESS_KEY_ID"), "");
		final bearer = stringOr(Reflect.field(env, "AWS_BEARER_TOKEN_BEDROCK"), auth != null && auth.type == "api" ? auth.key : "");
		final webIdentity = stringOr(Reflect.field(env, "AWS_WEB_IDENTITY_TOKEN_FILE"), "");
		final container = stringOr(Reflect.field(env, "AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"), "") != ""
			|| stringOr(Reflect.field(env, "AWS_CONTAINER_CREDENTIALS_FULL_URI"), "") != "";
		if (profile == "" && accessKey == "" && bearer == "" && webIdentity == "" && !container)
			return {autoload: false, options: cast {}};
		final options:ProviderOptions = cast mergeObject(configOptions, {region: region});
		final endpoint = stringOr(Reflect.field(configOptions, "endpoint"), stringOr(Reflect.field(configOptions, "baseURL"), ""));
		if (endpoint != "")
			Reflect.setField(options, "baseURL", endpoint);
		return {autoload: true, options: options};
	}

	static function withPatch(provider:ProviderInfo, patch:Dynamic):ProviderInfo {
		final models = Reflect.hasField(patch, "models") ? Reflect.field(patch, "models") : cloneModels(provider.models);
		final result:Dynamic = {
			id: provider.id,
			name: stringOr(Reflect.field(patch, "name"), provider.name),
			source: stringOr(Reflect.field(patch, "source"), provider.source),
			env: Reflect.hasField(patch, "env") ? Reflect.field(patch, "env") : provider.env.copy(),
			options: Reflect.hasField(patch,
				"options") ? cast mergeObject(provider.options, Reflect.field(patch, "options")) : cast cloneObject(provider.options),
			models: models,
		};
		final key = stringOr(Reflect.field(patch, "key"), provider.key);
		if (key != null && key != "")
			Reflect.setField(result, "key", key);
		return cast result;
	}

	static function add(map:Map<String, ProviderInfo>, provider:ProviderInfo):Void {
		map.set(provider.id.toString(), provider);
	}

	static function notFound(providerID:ProviderID, modelID:ModelID, suggestions:Array<String>):ProviderException {
		return new ProviderException(ModelNotFound(providerID, modelID, suggestions));
	}

	static function providerSuggestions(query:String):Array<String> {
		return [];
	}

	static function modelSuggestions(provider:ProviderInfo, query:String):Array<String> {
		final result:Array<String> = [];
		for (id in provider.models.keys()) {
			if (id.indexOf(query) != -1 || query.indexOf(id) != -1)
				result.push(id);
		}
		return result;
	}

	static function firstEnv(keys:Array<String>, env:Dynamic):Null<String> {
		for (key in keys) {
			final value = Reflect.field(env, key);
			if (Std.isOfType(value, String) && Std.string(value) != "")
				return Std.string(value);
		}
		return null;
	}

	static function modality(data:Dynamic, field:String, existing:Dynamic, defaultText:Bool):opencodehx.provider.ProviderTypes.ProviderCapabilityIO {
		final values = isRecord(data) ? Reflect.field(data, field) : null;
		return {
			text: contains(values, "text", existing == null ? defaultText : existing.text),
			audio: contains(values, "audio", existing == null ? false : existing.audio),
			image: contains(values, "image", existing == null ? false : existing.image),
			video: contains(values, "video", existing == null ? false : existing.video),
			pdf: contains(values, "pdf", existing == null ? false : existing.pdf),
		};
	}

	static function contains(values:Dynamic, item:String, fallback:Bool):Bool {
		if (!Std.isOfType(values, Array))
			return fallback;
		final arr:Array<Dynamic> = cast values;
		for (value in arr) {
			if (Std.string(value) == item)
				return true;
		}
		return false;
	}

	static function costFrom(data:Dynamic, existing:Dynamic):opencodehx.provider.ProviderTypes.ProviderCost {
		return {
			input: numberOr(Reflect.field(data, "input"), existing == null ? 0 : existing.input),
			output: numberOr(Reflect.field(data, "output"), existing == null ? 0 : existing.output),
			cache: {
				read: numberOr(Reflect.field(data, "cache_read"), existing == null ? 0 : existing.cache.read),
				write: numberOr(Reflect.field(data, "cache_write"), existing == null ? 0 : existing.cache.write),
			},
		};
	}

	static function limitFrom(data:Dynamic, existing:Dynamic):opencodehx.provider.ProviderTypes.ProviderLimit {
		final result:Dynamic = {
			context: numberOr(Reflect.field(data, "context"), existing == null ? 0 : existing.context),
			output: numberOr(Reflect.field(data, "output"), existing == null ? 0 : existing.output),
		};
		final input = numberOr(Reflect.field(data, "input"), existing == null || existing.input == null ? -1 : existing.input);
		if (input >= 0)
			Reflect.setField(result, "input", input);
		return cast result;
	}

	static function strings(value:Dynamic, fallback:Array<String>):Array<String> {
		if (!Std.isOfType(value, Array))
			return fallback.copy();
		final result:Array<String> = [];
		final arr:Array<Dynamic> = cast value;
		for (item in arr) {
			if (Std.isOfType(item, String))
				result.push(Std.string(item));
		}
		return result;
	}

	static function optionalStrings(value:Dynamic):Null<Array<String>> {
		if (!Std.isOfType(value, Array))
			return null;
		return strings(value, []);
	}

	static function stringSet(values:Null<Array<String>>):Map<String, Bool> {
		final result = new Map<String, Bool>();
		if (values == null)
			return result;
		for (value in values)
			result.set(value, true);
		return result;
	}

	static function stringOr(value:Dynamic, fallback:Null<String>):String {
		if (Std.isOfType(value, String))
			return Std.string(value);
		return fallback == null ? "" : fallback;
	}

	static function boolOr(value:Dynamic, fallback:Bool):Bool {
		if (Std.isOfType(value, Bool))
			return value;
		return fallback;
	}

	static function numberOr(value:Dynamic, fallback:Float):Float {
		if (Std.isOfType(value, Int) || Std.isOfType(value, Float))
			return value;
		return fallback;
	}

	static function mergeObject(current:Dynamic, next:Dynamic):Dynamic {
		if (!isRecord(current))
			current = {};
		if (!isRecord(next))
			return cloneObject(current);
		final result = cloneObject(current);
		for (field in Reflect.fields(next)) {
			final currentValue = Reflect.field(result, field);
			final nextValue = Reflect.field(next, field);
			Reflect.setField(result, field, isRecord(currentValue)
				&& isRecord(nextValue) ? mergeObject(currentValue, nextValue) : nextValue);
		}
		return result;
	}

	static function cloneProviders(input:Map<String, ProviderInfo>):Map<String, ProviderInfo> {
		final result = new Map<String, ProviderInfo>();
		for (id in input.keys())
			result.set(id, input.get(id));
		return result;
	}

	static function cloneModels(input:Map<String, ProviderModel>):Map<String, ProviderModel> {
		final result = new Map<String, ProviderModel>();
		for (id in input.keys())
			result.set(id, input.get(id));
		return result;
	}

	static function cloneObject(value:Dynamic):Dynamic {
		final result:Dynamic = {};
		if (!isRecord(value))
			return result;
		for (field in Reflect.fields(value))
			Reflect.setField(result, field, Reflect.field(value, field));
		return result;
	}

	static function isRecord(value:Dynamic):Bool {
		if (value == null)
			return false;
		if (Std.isOfType(value, Array))
			return false;
		if (Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Float) || Std.isOfType(value, Int))
			return false;
		return Reflect.isObject(value);
	}

	static function trimRightSlashes(value:String):String {
		var result = value;
		while (StringTools.endsWith(result, "/"))
			result = result.substr(0, result.length - 1);
		return result;
	}
}
