package opencodehx.provider;

import js.Syntax;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.ConfigProviderConfig;
import opencodehx.config.ConfigInfo.ConfigProviderMap;
import opencodehx.config.ConfigInfo.ConfigProviderModelConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelCostConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelLimitConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModalitiesConfig;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.provider.AiSdkLanguageLoader.AiSdkLanguageResolution;
import opencodehx.provider.CopilotLanguageLoader.CopilotChatLanguageResolution;
import opencodehx.provider.CopilotLanguageLoader.CopilotResponsesLanguageResolution;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ModelsDevCatalog;
import opencodehx.provider.ProviderTypes.ModelsDevCost;
import opencodehx.provider.ProviderTypes.ModelsDevModel;
import opencodehx.provider.ProviderTypes.ModelsDevMode;
import opencodehx.provider.ProviderTypes.ModelsDevProvider;
import opencodehx.provider.ProviderTypes.ParsedModelRef;
import opencodehx.provider.ProviderTypes.ProviderApiInfo;
import opencodehx.provider.ProviderTypes.ProviderCost;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderInterleaved;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTypes.ProviderOver200KCost;
import opencodehx.provider.ProviderTypes.ProviderVariants;
import opencodehx.externs.ai.AiSdk.AiLanguageModel;
import opencodehx.plugin.PluginConfigHooks;
import opencodehx.plugin.PluginServerHooks;

using StringTools;

typedef ProviderRegistryInput = {
	final config:ConfigInfo;
	// Upstream Provider.Service loads plugin hooks before it reads cfg.provider,
	// because server().config(cfg) may add providers or change provider filters.
	@:optional final pluginHooks:Array<PluginServerHooks>;
	// Raw process-env/auth JSON boundaries. The registry immediately normalizes
	// these into typed provider records and keeps the loose shape out of callers.
	@:optional final env:Dynamic;
	@:optional final auth:Dynamic;
	@:optional final database:Map<String, ProviderInfo>;
}

typedef DefaultModelFlags = {
	@:optional final reasoning:Bool;
	@:optional final attachment:Bool;
}

class ProviderRegistry {
	final providers:Map<String, ProviderInfo>;
	final config:ConfigInfo;

	public function new(input:ProviderRegistryInput) {
		config = PluginConfigHooks.apply(input.config, input.pluginHooks);
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

	public static function sort<T:{final id:String;}>(models:Array<T>):Array<T> {
		final result = models.copy();
		result.sort((a, b) -> compareModelID(a.id, b.id));
		return result;
	}

	public function getProvider(providerID:ProviderID):Null<ProviderInfo> {
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

	public function resolveLanguage(model:ProviderModel):AiSdkLanguageResolution {
		final provider = getProvider(model.providerID);
		if (provider == null)
			throw notFound(model.providerID, model.id, providerSuggestions(model.providerID.toString()));
		return AiSdkLanguageLoader.resolve(provider, model);
	}

	public function getLanguage(model:ProviderModel):AiLanguageModel {
		if (CopilotLanguageLoader.canResolveChat(model))
			return resolveCopilotChat(model).sdkLanguage;
		if (CopilotLanguageLoader.canResolveResponses(model))
			return resolveCopilotResponses(model).sdkLanguage;
		return resolveLanguage(model).language;
	}

	public function resolveCopilotChat(model:ProviderModel):CopilotChatLanguageResolution {
		final provider = getProvider(model.providerID);
		if (provider == null)
			throw notFound(model.providerID, model.id, providerSuggestions(model.providerID.toString()));
		return CopilotLanguageLoader.resolveChat(provider, model);
	}

	public function resolveCopilotResponses(model:ProviderModel):CopilotResponsesLanguageResolution {
		final provider = getProvider(model.providerID);
		if (provider == null)
			throw notFound(model.providerID, model.id, providerSuggestions(model.providerID.toString()));
		return CopilotLanguageLoader.resolveResponses(provider, model);
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
		if (providerID.toString().startsWith("opencode"))
			priority = ["gpt-5-nano"];
		if (providerID.toString().startsWith("github-copilot"))
			priority = ["gpt-5-mini", "claude-haiku-4.5"].concat(priority);
		for (needle in priority) {
			if (providerID.toString() == "amazon-bedrock") {
				final bedrock = smallBedrockModel(provider, needle);
				if (bedrock != null)
					return bedrock;
				continue;
			}
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

	public static function fromModelsDevProvider(provider:ModelsDevProvider):ProviderInfo {
		final models = new Map<String, ProviderModel>();
		for (key in provider.models.keys()) {
			final modelData = provider.models.get(key);
			if (modelData == null)
				continue;
			final base = fromModelsDevModel(provider, modelData);
			models.set(key, base);
			final experimental = modelData.experimental;
			final modes = experimental == null ? null : experimental.modes;
			if (modes == null)
				continue;
			for (mode in modes.keys()) {
				final modeData = modes.get(mode);
				if (modeData == null)
					continue;
				final modeID = '${modelData.id}-${mode}';
				models.set(modeID, modeModel(base, modelData, mode, modeData));
			}
		}

		return {
			id: ProviderID.make(provider.id),
			source: "custom",
			name: provider.name,
			env: provider.env == null ? [] : provider.env.copy(),
			options: emptyProviderOptions(),
			models: models,
		};
	}

	public static function fromModelsDevCatalog(catalog:ModelsDevCatalog):Map<String, ProviderInfo> {
		final result = new Map<String, ProviderInfo>();
		for (id in catalog.keys()) {
			final provider = catalog.get(id);
			if (provider != null)
				result.set(id, fromModelsDevProvider(provider));
		}
		return result;
	}

	static function fromModelsDevModel(provider:ModelsDevProvider, modelData:ModelsDevModel):ProviderModel {
		final base:ProviderModel = {
			id: ModelID.make(modelData.id),
			providerID: ProviderID.make(provider.id),
			name: modelData.name,
			family: stringOr(modelData.family, ""),
			api: {
				id: modelData.id,
				url: modelData.provider == null ? stringOr(provider.api, "") : stringOr(modelData.provider.api, stringOr(provider.api, "")),
				npm: modelData.provider == null ? stringOr(provider.npm,
					"@ai-sdk/openai-compatible") : stringOr(modelData.provider.npm, stringOr(provider.npm, "@ai-sdk/openai-compatible")),
			},
			status: stringOr(modelData.status, "active"),
			headers: new haxe.DynamicAccess<String>(),
			options: emptyProviderOptions(),
			cost: costFromModelsDev(modelData.cost),
			limit: {
				context: modelData.limit.context,
				input: modelData.limit.input,
				output: modelData.limit.output,
			},
			capabilities: {
				temperature: boolOr(modelData.temperature, false),
				reasoning: boolOr(modelData.reasoning, false),
				attachment: boolOr(modelData.attachment, false),
				toolcall: boolOr(modelData.tool_call, true),
				input: modelsDevModality(modelData.modalities == null ? null : modelData.modalities.input),
				output: modelsDevModality(modelData.modalities == null ? null : modelData.modalities.output),
				interleaved: interleavedOr(modelData.interleaved, false),
			},
			release_date: stringOr(modelData.release_date, ""),
			variants: emptyProviderVariants(),
		};

		return copyModel(base, ProviderTransform.variants(base));
	}

	static function modeModel(base:ProviderModel, modelData:ModelsDevModel, mode:String, modeData:ModelsDevMode):ProviderModel {
		var options = base.options;
		var headers = base.headers;
		final provider = modeData.provider;
		if (provider != null) {
			if (provider.body != null)
				options = optionsFromModelsDevBody(provider.body);
			if (provider.headers != null)
				headers = cloneHeaders(provider.headers);
		}
		return copyModel(base, base.variants, ModelID.make('${modelData.id}-${mode}'), '${modelData.name} ${capitalize(mode)}',
			mergeProviderCost(base.cost, modeData.cost), options, headers);
	}

	static function copyModel(base:ProviderModel, variants:ProviderVariants, ?id:ModelID, ?name:String, ?cost:ProviderCost, ?options:ProviderOptions,
			?headers:ProviderHeaders):ProviderModel {
		return {
			id: id == null ? base.id : id,
			providerID: base.providerID,
			name: name == null ? base.name : name,
			family: base.family,
			api: {
				id: base.api.id,
				url: base.api.url,
				npm: base.api.npm,
			},
			status: base.status,
			headers: headers == null ? base.headers : headers,
			options: options == null ? base.options : options,
			cost: cost == null ? base.cost : cost,
			limit: {
				context: base.limit.context,
				input: base.limit.input,
				output: base.limit.output,
			},
			capabilities: {
				temperature: base.capabilities.temperature,
				reasoning: base.capabilities.reasoning,
				attachment: base.capabilities.attachment,
				toolcall: base.capabilities.toolcall,
				input: base.capabilities.input,
				output: base.capabilities.output,
				interleaved: base.capabilities.interleaved,
			},
			release_date: base.release_date,
			variants: variants,
		};
	}

	static function costFromModelsDev(data:Null<ModelsDevCost>):ProviderCost {
		final cacheRead = data == null ? 0 : floatOrZero(data.cache_read);
		final cacheWrite = data == null ? 0 : floatOrZero(data.cache_write);
		final result:ProviderCost = {
			input: data == null ? 0 : data.input,
			output: data == null ? 0 : data.output,
			cache: {
				read: cacheRead,
				write: cacheWrite,
			},
		};
		if (data != null && data.context_over_200k != null) {
			final over = data.context_over_200k;
			final overCacheRead = floatOrZero(over.cache_read);
			final overCacheWrite = floatOrZero(over.cache_write);
			result.experimentalOver200K = {
				input: over.input,
				output: over.output,
				cache: {
					read: overCacheRead,
					write: overCacheWrite,
				},
			};
		}
		return result;
	}

	static function floatOrZero(value:Null<Float>):Float {
		return value == null ? 0 : value;
	}

	static function mergeProviderCost(base:ProviderCost, overrideCost:Null<ModelsDevCost>):ProviderCost {
		if (overrideCost == null)
			return cloneProviderCost(base);
		final next = costFromModelsDev(overrideCost);
		if (next.experimentalOver200K == null && base.experimentalOver200K != null)
			next.experimentalOver200K = cloneOver200KCost(base.experimentalOver200K);
		return next;
	}

	static function cloneProviderCost(cost:ProviderCost):ProviderCost {
		final result:ProviderCost = {
			input: cost.input,
			output: cost.output,
			cache: {
				read: cost.cache.read,
				write: cost.cache.write,
			},
		};
		if (cost.experimentalOver200K != null)
			result.experimentalOver200K = cloneOver200KCost(cost.experimentalOver200K);
		return result;
	}

	static function cloneOver200KCost(cost:ProviderOver200KCost):ProviderOver200KCost {
		return {
			input: cost.input,
			output: cost.output,
			cache: {
				read: cost.cache.read,
				write: cost.cache.write,
			},
		};
	}

	static function modelsDevModality(values:Null<Array<String>>):opencodehx.provider.ProviderTypes.ProviderCapabilityIO {
		return {
			text: contains(values, "text", false),
			audio: contains(values, "audio", false),
			image: contains(values, "image", false),
			video: contains(values, "video", false),
			pdf: contains(values, "pdf", false),
		};
	}

	static function optionsFromModelsDevBody(body:haxe.DynamicAccess<genes.ts.Unknown>):ProviderOptions {
		final result = emptyProviderOptions();
		for (key in body.keys())
			result.set(camelCaseProviderOption(key), body.get(key));
		return result;
	}

	static function cloneHeaders(headers:haxe.DynamicAccess<String>):ProviderHeaders {
		final result = new haxe.DynamicAccess<String>();
		for (key in headers.keys())
			result.set(key, headers.get(key));
		return result;
	}

	static function camelCaseProviderOption(key:String):String {
		final parts = key.split("_");
		if (parts.length == 1)
			return key;
		final result = new StringBuf();
		result.add(parts[0]);
		for (i in 1...parts.length)
			result.add(capitalize(parts[i]));
		return result.toString();
	}

	static function capitalize(value:String):String {
		if (value == "")
			return value;
		return value.substr(0, 1).toUpperCase() + value.substr(1);
	}

	static function emptyProviderOptions():ProviderOptions {
		// ProviderOptions is the documented SDK passthrough boundary. models.dev
		// mode bodies become this open map only after their known keys are
		// normalized; core provider facts stay in typed records.
		return new haxe.DynamicAccess<Dynamic>();
	}

	static function emptyProviderVariants():ProviderVariants {
		return new haxe.DynamicAccess<ProviderOptions>();
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
			final alreadyLoaded = providers.exists(configLoadID);
			final configExisting = alreadyLoaded ? providers.get(configLoadID) : configBaseProvider;
			// Config augments env/auth-loaded providers, but upstream keeps the
			// connection source from the credential path that made the provider usable.
			providers.set(configLoadID, withPatch(configExisting, {
				source: alreadyLoaded ? configExisting.source : "config",
				env: strings(Reflect.field(configLoadValue, "env"), configBaseProvider.env),
				name: stringOr(Reflect.field(configLoadValue, "name"), configBaseProvider.name),
				options: mergeObject(configBaseProvider.options, Reflect.field(configLoadValue, "options")),
			}));
		}

		final opencode = database.get("opencode");
		if (opencode != null && !disabled.exists("opencode")) {
			// Upstream exposes free OpenCode-hosted models with a public key, but
			// removes paid models unless env/auth/config proves user-owned access.
			final opencodeAlreadyLoaded = providers.exists("opencode");
			final existingOpencode = providers.get("opencode");
			final opencodeBase:ProviderInfo = existingOpencode == null ? opencode : existingOpencode;
			final ok = opencodePaidAccess(opencodeBase, configProviders.get("opencode"), env, auths.get("opencode"));
			final opencodeResolved:ProviderInfo = ok ? opencodeBase : withoutPaidModels(opencodeBase);
			if (opencodeAlreadyLoaded || opencodeResolved.models.iterator().hasNext()) {
				providers.set("opencode", withPatch(opencodeResolved, {
					source: opencodeAlreadyLoaded ? opencodeBase.source : "custom",
					options: ok ? opencodeBase.options : mergeObject(opencodeBase.options, {apiKey: "public"}),
				}));
			}
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

		final cloudflareGateway = database.get("cloudflare-ai-gateway");
		if (cloudflareGateway != null && !disabled.exists("cloudflare-ai-gateway")) {
			final cloudflareAlreadyLoaded = providers.exists("cloudflare-ai-gateway");
			final cloudflareBase = cloudflareAlreadyLoaded ? providers.get("cloudflare-ai-gateway") : cloudflareGateway;
			final cloudflareResolved = cloudflareGatewayOptions(cloudflareBase, env, auths.get("cloudflare-ai-gateway"));
			if (cloudflareAlreadyLoaded || cloudflareResolved.autoload) {
				providers.set("cloudflare-ai-gateway", withPatch(cloudflareBase, {
					source: cloudflareResolved.source,
					key: cloudflareResolved.key,
					options: cloudflareResolved.options,
				}));
			}
		}

		final gitlab = database.get("gitlab");
		if (gitlab != null && !disabled.exists("gitlab")) {
			final gitlabAlreadyLoaded = providers.exists("gitlab");
			final gitlabBase = gitlabAlreadyLoaded ? providers.get("gitlab") : gitlab;
			final gitlabResolved = gitlabOptions(gitlabBase, env, auths.get("gitlab"));
			if (gitlabAlreadyLoaded || gitlabResolved.autoload) {
				providers.set("gitlab", withPatch(gitlabBase, {
					source: gitlabResolved.source,
					key: gitlabResolved.key,
					options: gitlabResolved.options,
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

	static function providerFromConfig(id:String, config:ConfigProviderConfig, existing:Null<ProviderInfo>):ProviderInfo {
		final providerID = ProviderID.make(id);
		final env = strings(config.env, existing == null ? [] : existing.env);
		final name = stringOr(config.name, existing == null ? id : existing.name);
		final options:ProviderOptions = cast mergeObject(existing == null ? {} : existing.options, config.options);
		final models = existing == null ? new Map<String, ProviderModel>() : cloneModels(existing.models);
		final modelConfig = config.models;
		if (modelConfig != null) {
			for (modelID in modelConfig.keys()) {
				final modelData = modelConfig.get(modelID);
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

	static function modelFromConfig(providerID:ProviderID, modelID:String, data:ConfigProviderModelConfig, existing:Null<ProviderModel>,
			providerConfig:ConfigProviderConfig, existingProvider:Null<ProviderInfo>):ProviderModel {
		final upstreamID = stringOr(data.id, existing == null ? modelID : existing.api.id);
		final modelName = stringOr(data.name, existing == null ? modelID : existing.name);
		final apiConfig = data.provider;
		final inheritedApi = providerDefaultApi(existingProvider);
		final npm = stringOr(apiConfig == null ? null : apiConfig.npm,
			existing == null ? stringOr(providerConfig.npm,
				stringOr(inheritedApi.npm, "@ai-sdk/openai-compatible")) : stringOr(providerConfig.npm, existing.api.npm));
		final apiUrl = stringOr(apiConfig == null ? null : apiConfig.api,
			existing == null ? stringOr(providerConfig.api, inheritedApi.url) : stringOr(providerConfig.api, existing.api.url));
		final interleaved = interleavedOr(data.interleaved, existing == null ? false : existing.capabilities.interleaved);
		final parsed:ProviderModel = {
			id: ModelID.make(modelID),
			providerID: providerID,
			name: modelName,
			family: stringOr(data.family, existing == null ? "" : existing.family),
			api: {
				id: upstreamID,
				url: apiUrl,
				npm: npm
			},
			status: stringOr(data.status, existing == null ? "active" : existing.status),
			capabilities: {
				temperature: boolOr(data.temperature, existing == null ? false : existing.capabilities.temperature),
				reasoning: boolOr(data.reasoning, existing == null ? false : existing.capabilities.reasoning),
				attachment: boolOr(data.attachment, existing == null ? false : existing.capabilities.attachment),
				toolcall: boolOr(data.tool_call, existing == null ? true : existing.capabilities.toolcall),
				input: modality(data.modalities, "input", existing == null ? null : existing.capabilities.input, true),
				output: modality(data.modalities, "output", existing == null ? null : existing.capabilities.output, true),
				interleaved: interleaved,
			},
			cost: costFrom(data.cost, existing == null ? null : existing.cost),
			options: cast mergeObject(existing == null ? {} : existing.options, data.options),
			headers: cast mergeObject(existing == null ? {} : existing.headers, data.headers),
			limit: limitFrom(data.limit, existing == null ? null : existing.limit),
			release_date: stringOr(data.release_date, existing == null ? "" : existing.release_date),
			variants: emptyProviderVariants(),
		};
		return copyModel(parsed, configuredVariants(parsed, data.variants));
	}

	static function providerDefaultApi(provider:Null<ProviderInfo>):ProviderApiInfo {
		// New config-only models under a known provider inherit that provider's
		// SDK package and API URL, matching upstream models.dev-backed providers.
		if (provider == null)
			return {id: "", url: "", npm: ""};
		final model = sortedModels(provider.models)[0];
		return model == null ? {id: "", url: "", npm: ""} : model.api;
	}

	static function configuredVariants(model:ProviderModel, config:Null<ProviderVariants>):ProviderVariants {
		// Upstream treats `disabled` as variant-control metadata, not a provider
		// option. Generate canonical variants, merge config, drop disabled entries,
		// and strip the control field from variants that remain enabled.
		final generated = ProviderTransform.variants(model);
		final result = emptyProviderVariants();
		for (key in generated.keys())
			addConfiguredVariant(result, key, generated.get(key), config == null ? null : config.get(key));
		if (config != null) {
			for (key in config.keys()) {
				if (!result.exists(key) && !generated.exists(key))
					addConfiguredVariant(result, key, emptyProviderOptions(), config.get(key));
			}
		}
		return result;
	}

	static function addConfiguredVariant(result:ProviderVariants, key:String, generated:ProviderOptions, config:Null<ProviderOptions>):Void {
		final merged:ProviderOptions = cast mergeObject(generated, config);
		if (!boolOr(Reflect.field(merged, "disabled"), false))
			result.set(key, stripDisabledVariantField(merged));
	}

	static function stripDisabledVariantField(options:ProviderOptions):ProviderOptions {
		final result = emptyProviderOptions();
		for (field in Reflect.fields(options)) {
			if (field != "disabled")
				result.set(field, Reflect.field(options, field));
		}
		return result;
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
		add(result, provider("opencode", "opencode", ["OPENCODE_API_KEY"], [
			withCost(model("opencode", "gpt-5.2", "GPT-5.2", "@ai-sdk/openai-compatible", "https://api.opencode.ai/v1", 200000, 10000, {
				reasoning: true
			}), 1.25, 10),
			model("opencode", "gpt-5-nano", "GPT-5 nano", "@ai-sdk/openai-compatible", "https://api.opencode.ai/v1", 200000, 10000, {
				reasoning: true
			}),
		]));
		add(result, provider("cloudflare-ai-gateway", "Cloudflare AI Gateway", [], [
			model("cloudflare-ai-gateway", "openai/gpt-5.2-codex", "GPT-5.2 Codex", "ai-gateway-provider", "", 400000, 128000, {
				reasoning: true,
				attachment: true
			}),
		]));
		add(result, provider("gitlab", "GitLab Duo", ["GITLAB_TOKEN"], [
			model("gitlab", "duo-chat-haiku-4-5", "GitLab Duo Chat Haiku 4.5", "gitlab-ai-provider", "https://gitlab.com", 200000, 32000, {
				reasoning: true,
				attachment: true
			}),
			model("gitlab", "duo-chat-sonnet-4-5", "GitLab Duo Chat Sonnet 4.5", "gitlab-ai-provider", "https://gitlab.com", 200000, 64000, {
				reasoning: true,
				attachment: true
			}),
			model("gitlab", "duo-chat-opus-4-5", "GitLab Duo Chat Opus 4.5", "gitlab-ai-provider", "https://gitlab.com", 200000, 64000, {
				reasoning: true,
				attachment: true
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

	static function model(providerID:String, id:String, name:String, npm:String, url:String, context:Float, output:Float,
			flags:DefaultModelFlags):ProviderModel {
		final reasoning = boolOr(flags.reasoning, false);
		final attachment = boolOr(flags.attachment, false);
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

	static function withCost(base:ProviderModel, input:Float, output:Float):ProviderModel {
		return copyModel(base, base.variants, null, null, {
			input: input,
			output: output,
			cache: {read: 0, write: 0},
		});
	}

	static function filterProviderModels(provider:ProviderInfo, configEntry:Null<ConfigProviderConfig>):ProviderInfo {
		final models = new Map<String, ProviderModel>();
		final whitelistValues = configEntry == null ? null : configEntry.whitelist;
		final whitelist = whitelistValues == null ? null : stringSet(whitelistValues);
		final blacklistValues = configEntry == null ? null : configEntry.blacklist;
		final blacklist = blacklistValues == null ? new Map<String, Bool>() : stringSet(blacklistValues);
		for (modelID in provider.models.keys()) {
			final model = provider.models.get(modelID);
			if (model.status == "deprecated")
				continue;
			if (whitelist != null && !whitelist.exists(modelID))
				continue;
			if (blacklist.exists(modelID))
				continue;
			models.set(modelID, copyModel(model, configuredVariants(model, configModelVariants(configEntry, modelID))));
		}
		return withPatch(provider, {models: models});
	}

	static function configModelVariants(configEntry:Null<ConfigProviderConfig>, modelID:String):Null<ProviderVariants> {
		if (configEntry == null || configEntry.models == null)
			return null;
		final model = configEntry.models.get(modelID);
		return model == null ? null : model.variants;
	}

	static function sortedModels(models:Map<String, ProviderModel>):Array<ProviderModel> {
		final result:Array<ProviderModel> = [];
		for (id in models.keys())
			result.push(models.get(id));
		return sort(result);
	}

	static function compareModelID(left:String, right:String):Int {
		final leftPriority = priority(left);
		final rightPriority = priority(right);
		if (leftPriority != rightPriority)
			return rightPriority - leftPriority;
		final leftLatest = left.indexOf("latest") == -1 ? 1 : 0;
		final rightLatest = right.indexOf("latest") == -1 ? 1 : 0;
		if (leftLatest != rightLatest)
			return leftLatest - rightLatest;
		return Reflect.compare(right, left);
	}

	static function priority(id:String):Int {
		final filters = ["gpt-5", "claude-sonnet-4", "big-pickle", "gemini-3-pro"];
		for (index in 0...filters.length) {
			if (id.indexOf(filters[index]) != -1)
				return index;
		}
		return -1;
	}

	static function smallBedrockModel(provider:ProviderInfo, needle:String):Null<ProviderModel> {
		final global = firstMatchingModel(provider, needle, modelID -> modelID.startsWith("global."));
		if (global != null)
			return global;

		final region = ProviderOptionAccess.string(provider.options, "region", null);
		if (region != null) {
			final regionPrefix = region.split("-")[0];
			if (regionPrefix == "us" || regionPrefix == "eu") {
				final regional = firstMatchingModel(provider, needle, modelID -> modelID.startsWith('${regionPrefix}.'));
				if (regional != null)
					return regional;
			}
		}

		return firstMatchingModel(provider, needle, modelID -> !bedrockSmallCrossRegion(modelID));
	}

	static function firstMatchingModel(provider:ProviderInfo, needle:String, accept:String->Bool):Null<ProviderModel> {
		for (modelID in provider.models.keys()) {
			if (modelID.indexOf(needle) != -1 && accept(modelID))
				return provider.models.get(modelID);
		}
		return null;
	}

	static function bedrockSmallCrossRegion(modelID:String):Bool {
		// Keep this list aligned with upstream getSmallModel fallback semantics.
		// Broader Bedrock SDK inference-profile prefixing remains in BedrockLanguageLoader.
		return modelID.startsWith("global.") || modelID.startsWith("us.") || modelID.startsWith("eu.");
	}

	static function providerConfigEntries(data:Null<ConfigProviderMap>):Map<String, ConfigProviderConfig> {
		final result = new Map<String, ConfigProviderConfig>();
		if (data == null)
			return result;
		for (id in data.keys())
			result.set(id, data.get(id));
		return result;
	}

	static function authEntries(data:Dynamic):Map<String, {final type:String; final key:String; final metadata:Dynamic;}> {
		final result = new Map<String, {final type:String; final key:String; final metadata:Dynamic;}>();
		final raw = data;
		if (!isRecord(raw))
			return result;
		for (id in Reflect.fields(raw)) {
			final item = Reflect.field(raw, id);
			if (!isRecord(item))
				continue;
			final type = stringOr(Reflect.field(item, "type"), "");
			final key = stringOr(Reflect.field(item, "key"), stringOr(Reflect.field(item, "access"), ""));
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
		if (profile != "")
			Reflect.setField(options, "profile", profile);
		// Bedrock bearer auth is passed directly to the SDK factory. Upstream
		// mutates process.env for this case; the Haxe port keeps it explicit so
		// the loader can type-check the boundary and tests can inject auth safely.
		if (bearer != "")
			Reflect.setField(options, "apiKey", bearer);
		final endpoint = stringOr(Reflect.field(configOptions, "endpoint"), stringOr(Reflect.field(configOptions, "baseURL"), ""));
		if (endpoint != "")
			Reflect.setField(options, "baseURL", endpoint);
		return {autoload: true, options: options};
	}

	static function opencodePaidAccess(provider:ProviderInfo, configEntry:Null<ConfigProviderConfig>, env:Dynamic,
			auth:Null<{final type:String; final key:String; final metadata:Dynamic;}>):Bool {
		if (firstEnv(provider.env, env) != null)
			return true;
		if (auth != null && auth.type == "api")
			return true;
		final configOptions = configEntry == null ? null : configEntry.options;
		return configOptions != null && ProviderOptionAccess.string(configOptions, "apiKey", null) != null;
	}

	static function withoutPaidModels(provider:ProviderInfo):ProviderInfo {
		final models = new Map<String, ProviderModel>();
		for (modelID in provider.models.keys()) {
			final model = provider.models.get(modelID);
			if (model.cost.input == 0)
				models.set(modelID, model);
		}
		return withPatch(provider, {models: models});
	}

	static function cloudflareGatewayOptions(provider:ProviderInfo, env:Dynamic, auth:Null<{final type:String; final key:String; final metadata:Dynamic;}>):{
		final autoload:Bool;
		final source:String;
		final key:String;
		final options:ProviderOptions;
	} {
		if (ProviderOptionAccess.string(provider.options, "baseURL", null) != null)
			return {
				autoload: false,
				source: provider.source,
				key: stringOr(provider.key, ""),
				options: provider.options
			};
		final authMetadata = auth == null || auth.type != "api" ? null : auth.metadata;
		final accountID = stringOr(Reflect.field(env, "CLOUDFLARE_ACCOUNT_ID"), stringOr(Reflect.field(authMetadata, "accountId"), ""));
		final gatewayID = stringOr(Reflect.field(env, "CLOUDFLARE_GATEWAY_ID"), stringOr(Reflect.field(authMetadata, "gatewayId"), ""));
		final envToken = stringOr(Reflect.field(env, "CLOUDFLARE_API_TOKEN"), stringOr(Reflect.field(env, "CF_AIG_TOKEN"), ""));
		final authToken = auth == null || auth.type != "api" ? "" : auth.key;
		final configuredToken = ProviderOptionAccess.string(provider.options, "apiKey", null);
		final apiToken = configuredToken != null && configuredToken != "" ? configuredToken : envToken != "" ? envToken : authToken;
		final source = configuredToken != null
			&& configuredToken != "" ? "config" : envToken != "" ? "env" : authToken != "" ? "api" : provider.source;
		final options:ProviderOptions = cast mergeObject(provider.options, {
			accountId: accountID,
			gatewayId: gatewayID,
			apiKey: apiToken,
		});
		return {
			autoload: accountID != "" && gatewayID != "" && apiToken != "",
			source: source,
			key: apiToken,
			options: options,
		};
	}

	static function gitlabOptions(provider:ProviderInfo, env:Dynamic, auth:Null<{final type:String; final key:String; final metadata:Dynamic;}>):{
		final autoload:Bool;
		final source:String;
		final key:String;
		final options:ProviderOptions;
	} {
		final configuredKey = ProviderOptionAccess.string(provider.options, "apiKey", null);
		final authKey = auth == null || (auth.type != "api" && auth.type != "oauth") ? null : auth.key;
		final envKey = stringOr(Reflect.field(env, "GITLAB_TOKEN"), "");
		final key = configuredKey != null && configuredKey != "" ? configuredKey : authKey != null && authKey != "" ? authKey : envKey;
		final source = configuredKey != null && configuredKey != "" ? "config" : authKey != null && authKey != "" ? auth.type : "env";
		final instanceUrl = ProviderOptionAccess.string(provider.options, "instanceUrl",
			stringOr(Reflect.field(env, "GITLAB_INSTANCE_URL"), "https://gitlab.com"));
		// GitLab SDK options are an open provider-owned boundary. Merge typed
		// OpenCode defaults first, then let user config override stable leaves
		// such as feature flags and gateway headers without losing defaults.
		final options:ProviderOptions = cast mergeObject({
			instanceUrl: instanceUrl,
			apiKey: key,
			aiGatewayHeaders: {
				"anthropic-beta": "context-1m-2025-08-07",
			},
			featureFlags: {
				duo_agent_platform_agentic_chat: true,
				duo_agent_platform: true,
			},
		}, provider.options);
		return {
			autoload: key != "",
			source: source,
			key: key,
			options: options
		};
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

	function providerSuggestions(query:String):Array<String> {
		return suggestions(query, providers.keys());
	}

	static function modelSuggestions(provider:ProviderInfo, query:String):Array<String> {
		return suggestions(query, provider.models.keys());
	}

	static function suggestions(query:String, candidates:Iterator<String>):Array<String> {
		// Upstream uses fuzzysort here. A small Levenshtein ranker keeps the UX
		// behavior deterministic and portable without adding a JS-only runtime dependency.
		final ranked:Array<{final id:String; final score:Int;}> = [];
		for (id in candidates)
			ranked.push({id: id, score: suggestionScore(query, id)});
		ranked.sort((a, b) -> a.score == b.score ? Reflect.compare(a.id, b.id) : a.score - b.score);

		final result:Array<String> = [];
		final limit = ranked.length < 3 ? ranked.length : 3;
		for (index in 0...limit)
			result.push(ranked[index].id);
		return result;
	}

	static function suggestionScore(query:String, candidate:String):Int {
		final a = query.toLowerCase();
		final b = candidate.toLowerCase();
		var score = levenshtein(a, b) * 10 + intAbs(a.length - b.length);
		if (a.indexOf(b) != -1 || b.indexOf(a) != -1)
			score -= 30;
		return score;
	}

	static function levenshtein(a:String, b:String):Int {
		var previous:Array<Int> = [];
		for (column in 0...(b.length + 1))
			previous.push(column);

		for (row in 1...(a.length + 1)) {
			final current:Array<Int> = [row];
			for (column in 1...(b.length + 1)) {
				final substitutionCost = a.charAt(row - 1) == b.charAt(column - 1) ? 0 : 1;
				current.push(min3(current[column - 1] + 1, previous[column] + 1, previous[column - 1] + substitutionCost));
			}
			previous = current;
		}

		return previous[b.length];
	}

	static inline function min3(a:Int, b:Int, c:Int):Int {
		return a < b ? (a < c ? a : c) : (b < c ? b : c);
	}

	static inline function intAbs(value:Int):Int {
		return value < 0 ? -value : value;
	}

	static function firstEnv(keys:Array<String>, env:Dynamic):Null<String> {
		for (key in keys) {
			final value = Reflect.field(env, key);
			if (Std.isOfType(value, String) && Std.string(value) != "")
				return Std.string(value);
		}
		return null;
	}

	static function modality(data:Null<ConfigProviderModalitiesConfig>, field:String, existing:Dynamic,
			defaultText:Bool):opencodehx.provider.ProviderTypes.ProviderCapabilityIO {
		final values = data == null ? null : field == "input" ? data.input : data.output;
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

	static function interleavedOr(value:Null<ProviderInterleaved>, fallback:ProviderInterleaved):ProviderInterleaved {
		return value == null ? fallback : value;
	}

	static function costFrom(data:Null<ConfigProviderModelCostConfig>, existing:Dynamic):opencodehx.provider.ProviderTypes.ProviderCost {
		return {
			input: numberOr(data == null ? null : data.input, existing == null ? 0 : existing.input),
			output: numberOr(data == null ? null : data.output, existing == null ? 0 : existing.output),
			cache: {
				read: numberOr(data == null ? null : data.cache_read, existing == null ? 0 : existing.cache.read),
				write: numberOr(data == null ? null : data.cache_write, existing == null ? 0 : existing.cache.write),
			},
		};
	}

	static function limitFrom(data:Null<ConfigProviderModelLimitConfig>, existing:Dynamic):opencodehx.provider.ProviderTypes.ProviderLimit {
		final result:Dynamic = {
			context: numberOr(data == null ? null : data.context, existing == null ? 0 : existing.context),
			output: numberOr(data == null ? null : data.output, existing == null ? 0 : existing.output),
		};
		final input = numberOr(data == null ? null : data.input, existing == null || existing.input == null ? -1 : existing.input);
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
		while (result.endsWith("/"))
			result = result.substr(0, result.length - 1);
		return result;
	}
}
