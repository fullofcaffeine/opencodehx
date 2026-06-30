package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import genes.ts.JsonCodec;
import haxe.DynamicAccess;
import haxe.Json;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.config.ConfigInfo;
import opencodehx.config.ConfigInfo.ConfigProviderConfig;
import opencodehx.config.ConfigInfo.ConfigProviderModelConfig;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.harness.TranscriptHarness;
import opencodehx.plugin.PluginServerHooks;
import opencodehx.plugin.PluginConfigHooks;
import opencodehx.host.node.NodePath;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.provider.AiSdkLanguageLoader;
import opencodehx.provider.BedrockLanguageLoader;
import opencodehx.provider.ProviderModelsDev;
import opencodehx.provider.ProviderModelsDev.ModelsDevFetchFunction;
import opencodehx.provider.ProviderModelsDev.ModelsDevFetchRequest;
import opencodehx.provider.ProviderModelsDev.ModelsDevOptions;
import opencodehx.provider.ProviderOptionAccess;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ModelsDevCatalog;
import opencodehx.provider.ProviderTypes.ModelsDevModel;
import opencodehx.provider.ProviderTypes.ModelsDevProvider;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderIDs;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderInfo;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.session.MessageCodec;

class ProviderSmoke {
	public static function run():Void {
		registryEnvAndConfig();
		registryFilters();
		registryPluginConfigHooks();
		registryModels();
		registryModelVariants();
		registryVertexProviders();
		registryAuthAndBedrock();
		cloudflareAiGatewayLoading();
		gitlabDuoLoading();
		opencodePaidModelLoading();
		modelsDevNormalization();
		final transcript = TranscriptHarness.oneTurn();
		eq(transcript.provider.id, "openai", "provider id");
		eq(transcript.provider.modelID, "gpt-5.2", "model id");
		eq(transcript.events.length, 3, "event count");
		eq(transcript.events[1].text, "Hello from the fake provider.", "delta text");
		eq(transcript.messages.length, 2, "message count");

		final encoded = TranscriptHarness.oneTurnJson();
		final parsed = parseRecord(encoded, "provider transcript");
		final messages = requiredArrayField(parsed, "messages", "provider transcript");
		final first = requiredRecordField(recordAt(messages, 0, "provider transcript messages"), "info", "provider transcript first message");
		eq(requiredString(first.get("role"), "provider transcript first message role"), "user", "encoded user role");
		MessageCodec.parseWithParts(jsonString(messages.get(1), "provider transcript assistant message"), "provider-smoke-assistant");
	}

	@:async
	public static function runRemote():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-models-dev-"));
		try {
			await(modelsDevFetchCache(root));
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Test cleanup must preserve and rethrow the original host/runtime error,
			// whose concrete type is not knowable across Haxe's JS catch boundary.
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function registryEnvAndConfig():Void {
		final envRegistry = registry(config({}), {ANTHROPIC_API_KEY: "test-api-key"});
		final anthropic = envRegistry.getProvider(ProviderIDs.known("anthropic"));
		eq(anthropic.source, "env", "anthropic env source");
		eq(stringMapHas(ProviderOptionAccess.stringMap(anthropic.options, "headers"), "anthropic-beta"), true, "anthropic custom headers");

		final envDetails = registry(config({
			provider: {
				"single-env": {
					name: "Single Env",
					npm: "@ai-sdk/openai-compatible",
					env: ["SINGLE_ENV_KEY"],
					models: {"chat": {name: "Chat"}},
				},
				"multi-env": {
					name: "Multi Env",
					npm: "@ai-sdk/openai-compatible",
					env: ["MULTI_ENV_KEY_1", "MULTI_ENV_KEY_2"],
					models: {"chat": {name: "Chat"}},
				},
				"fallback-env": {
					name: "Fallback Env",
					npm: "@ai-sdk/openai-compatible",
					env: ["FALLBACK_ENV_KEY_1", "FALLBACK_ENV_KEY_2"],
					models: {"chat": {name: "Chat"}},
				},
			},
		}),
			{SINGLE_ENV_KEY: "single-key", MULTI_ENV_KEY_1: "multi-key", FALLBACK_ENV_KEY_2: "fallback-key"});
		eq(envDetails.getProvider(ProviderID.make("single-env")).key, "single-key", "single env captures key");
		eq(envDetails.getProvider(ProviderID.make("multi-env")).key == null, true, "multi env does not capture ambiguous key");
		eq(envDetails.getProvider(ProviderID.make("fallback-env")).source, "env", "fallback env source");

		final envWithConfig = registry(config({
			provider: {
				anthropic: {
					options: {
						headers: {
							"X-Custom": "custom-value",
						},
						timeout: 60000,
					},
				},
				openai: {
					options: {
						timeout: 30000,
					},
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		final envConfiguredAnthropic = envWithConfig.getProvider(ProviderIDs.known("anthropic"));
		eq(envConfiguredAnthropic.source, "env", "env source survives config merge");
		eq(ProviderOptionAccess.numberValue(envConfiguredAnthropic.options, "timeout", null), 60000.0, "env provider config option merge");
		final mergedHeaders = ProviderOptionAccess.stringMap(envConfiguredAnthropic.options, "headers");
		eq(stringMapValue(mergedHeaders, "X-Custom"), "custom-value", "provider nested option deep merge");
		eq(stringMapHas(mergedHeaders, "anthropic-beta"), true, "provider loader header survives deep merge");
		eq(ProviderOptionAccess.numberValue(envWithConfig.getProvider(ProviderIDs.known("openai")).options, "timeout", null), 30000.0,
			"multiple configured providers load together");

		final configured = registry(config({
			provider: {
				anthropic: {
					options: {
						apiKey: "config-api-key",
						timeout: 60000,
						chunkTimeout: 15000,
					},
				},
			},
		}));
		final provider = configured.getProvider(ProviderIDs.known("anthropic"));
		eq(provider.source, "config", "anthropic config source");
		eq(ProviderOptionAccess.string(provider.options, "apiKey", null), "config-api-key", "config api key");
		eq(ProviderOptionAccess.numberValue(provider.options, "timeout", null), 60000.0, "config timeout");
	}

	static function registryFilters():Void {
		final disabled = registry(config({disabled_providers: ["anthropic"]}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(disabled.getProvider(ProviderIDs.known("anthropic")) == null, true, "disabled provider");

		final enabled = registry(config({enabled_providers: ["anthropic"]}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		eq(enabled.getProvider(ProviderIDs.known("anthropic")) != null, true, "enabled provider present");
		eq(enabled.getProvider(ProviderIDs.known("openai")) == null, true, "enabled provider excludes openai");

		final emptyEnabled = registry(config({enabled_providers: []}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		eq(emptyEnabled.all().length, 0, "empty enabled providers allows no providers");

		final enabledDisabled = registry(config({
			enabled_providers: ["anthropic", "openai"],
			disabled_providers: ["openai"],
		}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		eq(enabledDisabled.getProvider(ProviderIDs.known("anthropic")) != null, true, "enabled and not disabled provider kept");
		eq(enabledDisabled.getProvider(ProviderIDs.known("openai")) == null, true, "enabled and disabled provider removed");

		final whitelist = registry(config({
			provider: {
				anthropic: {
					whitelist: ["claude-sonnet-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(whitelist.getProvider(ProviderIDs.known("anthropic")).models.exists("claude-sonnet-4-20250514"), true, "whitelist keeps model");
		eq(modelCount(whitelist, "anthropic"), 1, "whitelist count");

		final blacklist = registry(config({
			provider: {
				anthropic: {
					blacklist: ["claude-sonnet-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(blacklist.getProvider(ProviderIDs.known("anthropic")).models.exists("claude-sonnet-4-20250514"), false, "blacklist removes model");

		final combined = registry(config({
			provider: {
				anthropic: {
					whitelist: ["claude-sonnet-4-20250514", "claude-opus-4-20250514"],
					blacklist: ["claude-opus-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(combined.getProvider(ProviderIDs.known("anthropic")).models.exists("claude-sonnet-4-20250514"), true, "combined filter keeps whitelist model");
		eq(combined.getProvider(ProviderIDs.known("anthropic")).models.exists("claude-opus-4-20250514"), false, "combined filter removes blacklist model");
		eq(modelCount(combined, "anthropic"), 1, "combined filter count");
	}

	static function registryPluginConfigHooks():Void {
		final providerHook = demoProviderHook();
		final first = registry(config({}), {}, {}, [providerHook]);
		eq(first.getProvider(ProviderID.make("demo")).name, "Demo Provider", "plugin provider present");
		eq(first.getModel(ProviderID.make("demo"), ModelID.make("chat")).limit.context, 128000, "plugin model context");

		final second = registry(config({}), {}, {}, [providerHook]);
		eq(second.getModel(ProviderID.make("demo"), ModelID.make("chat")).name, "Demo Chat", "plugin provider after registry rebuild");

		final filters = registry(config({}), {ANTHROPIC_API_KEY: "test-anthropic-key", OPENAI_API_KEY: "test-openai-key"}, {}, [
			{
				config: cfg -> {
					cfg.enabledProviders = ["anthropic", "openai"];
					cfg.disabledProviders = ["openai"];
				},
			}
		]);
		eq(filters.getProvider(ProviderIDs.known("anthropic")) != null, true, "plugin enabled provider kept");
		eq(filters.getProvider(ProviderIDs.known("openai")) == null, true, "plugin disabled provider removed");

		final failures:Array<Int> = [];
		final isolatedConfig = config({});
		PluginConfigHooks.apply(isolatedConfig, [
			{
				config: _ -> throw "plugin exploded",
			},
			{
				config: cfg -> cfg.enabledProviders = ["anthropic"],
			}
		], failure -> failures.push(failure.hookIndex));
		eq(failures.length, 1, "plugin config hook failure reported");
		eq(failures[0], 0, "plugin config hook failure index");
		final isolatedEnabled = isolatedConfig.enabledProviders;
		if (isolatedEnabled == null)
			throw "plugin config hook after failure did not set enabled providers";
		eq(isolatedEnabled[0], "anthropic", "plugin config hook after failure still runs");
	}

	static function registryModels():Void {
		final custom = registry(config({
			provider: {
				"custom-provider": {
					name: "Custom Provider",
					npm: "@ai-sdk/openai-compatible",
					api: "https://api.custom.com/v1",
					env: ["CUSTOM_API_KEY"],
					models: {
						"custom-model": {
							name: "Custom Model",
							tool_call: true,
							limit: {context: 128000, output: 4096},
						},
						"cost-model": {
							name: "Cost Model",
							cost: {
								input: 5,
								output: 15,
								cache_read: 2.5,
								cache_write: 7.5,
							},
						},
						"no-tools": {
							name: "No Tools",
							tool_call: false,
						},
						"headers-model": {
							name: "Headers Model",
							headers: {
								"X-Custom-Header": "custom-value",
								Authorization: "Bearer special-token",
							},
						},
						"no-limit": {
							name: "No Limit",
						},
					},
					options: {apiKey: "custom-key", baseURL: "https://custom.override.com/v1"},
				},
				"anonymous-provider": {
					npm: "@ai-sdk/openai-compatible",
					models: {
						model: {name: "Model"},
					},
					options: {apiKey: "anonymous-key"},
				},
				"brand-new-provider": {
					name: "Brand New",
					npm: "@ai-sdk/openai-compatible",
					api: "https://new-api.com/v1",
					models: {
						"new-model": {
							name: "New Model",
							reasoning: true,
							attachment: true,
							temperature: true,
							modalities: {
								input: ["text", "image"],
								output: ["text"],
							},
							limit: {context: 32000, output: 8000},
						},
					},
					options: {apiKey: "new-key"},
				},
				anthropic: {
					models: {
						"my-alias": {
							id: "claude-sonnet-4-20250514",
							name: "My Custom Alias",
						},
						"claude-sonnet-4-20250514": {
							options: {customOption: "custom-value"},
						},
					},
				},
				openai: {
					models: {
						"my-custom-model": {
							name: "My Custom Model",
							limit: {context: 8000, output: 2000},
						},
					},
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		eq(custom.getProvider(ProviderID.make("custom-provider")).name, "Custom Provider", "custom provider name");
		eq(custom.getProvider(ProviderID.make("anonymous-provider")).name, "anonymous-provider", "provider name defaults to id");
		eq(requiredOptionString(custom.getProvider(ProviderID.make("custom-provider")).options, "baseURL", "custom provider baseURL"),
			"https://custom.override.com/v1", "provider baseURL option");
		eq(custom.getProvider(ProviderID.make("brand-new-provider")).name, "Brand New", "brand-new provider name");
		eq(custom.getModel(ProviderID.make("custom-provider"), ModelID.make("custom-model")).name, "Custom Model", "custom model name");
		final customModel = custom.getModel(ProviderID.make("custom-provider"), ModelID.make("custom-model"));
		eq(customModel.api.npm, "@ai-sdk/openai-compatible", "custom provider npm package");
		eq(customModel.api.url, "https://api.custom.com/v1", "provider api field sets model api url");
		eq(customModel.cost.input, 0, "model default input cost");
		eq(customModel.cost.output, 0, "model default output cost");
		eq(customModel.cost.cache.read, 0, "model default cache read cost");
		eq(customModel.cost.cache.write, 0, "model default cache write cost");
		eq(customModel.capabilities.input.text, true, "model default input text modality");
		eq(customModel.capabilities.output.text, true, "model default output text modality");
		eq(customModel.capabilities.toolcall, true, "model explicit tool calls");
		final costModel = custom.getModel(ProviderID.make("custom-provider"), ModelID.make("cost-model"));
		eq(costModel.cost.input, 5, "model custom input cost");
		eq(costModel.cost.output, 15, "model custom output cost");
		eq(costModel.cost.cache.read, 2.5, "model custom cache read cost");
		eq(costModel.cost.cache.write, 7.5, "model custom cache write cost");
		eq(custom.getModel(ProviderID.make("custom-provider"), ModelID.make("no-tools")).capabilities.toolcall, false, "model disables tool calls");
		final headers = custom.getModel(ProviderID.make("custom-provider"), ModelID.make("headers-model")).headers;
		eq(headers.get("X-Custom-Header"), "custom-value", "model custom header");
		eq(headers.get("Authorization"), "Bearer special-token", "model authorization header");
		final noLimit = custom.getModel(ProviderID.make("custom-provider"), ModelID.make("no-limit"));
		eq(noLimit.limit.context, 0, "model default context limit");
		eq(noLimit.limit.output, 0, "model default output limit");
		final openaiCustom = custom.getModel(ProviderIDs.known("openai"), ModelID.make("my-custom-model"));
		eq(openaiCustom.api.npm, "@ai-sdk/openai", "custom model inherits provider npm package");
		eq(openaiCustom.api.url, "https://api.openai.com/v1", "custom model inherits provider api url");
		final newModel = custom.getModel(ProviderID.make("brand-new-provider"), ModelID.make("new-model"));
		eq(newModel.capabilities.reasoning, true, "brand-new model reasoning");
		eq(newModel.capabilities.attachment, true, "brand-new model attachment");
		eq(newModel.capabilities.input.image, true, "brand-new model image input");
		eq(newModel.capabilities.output.text, true, "brand-new model text output");
		eq(custom.getModel(ProviderIDs.known("anthropic"), ModelID.make("my-alias")).name, "My Custom Alias", "alias model name");
		eq(requiredOptionString(custom.getModel(ProviderIDs.known("anthropic"), ModelID.make("claude-sonnet-4-20250514")).options, "customOption",
			"custom model option"),
			"custom-value", "model option merge");

		final parsed = ProviderRegistry.parseModel("openrouter/anthropic/claude-3-opus");
		eq(parsed.providerID.toString(), "openrouter", "parse provider");
		eq(parsed.modelID.toString(), "anthropic/claude-3-opus", "parse slash model");

		final configuredDefault = registry(config({model: "anthropic/claude-sonnet-4-20250514"}), {ANTHROPIC_API_KEY: "test-api-key"}).defaultModel();
		eq(configuredDefault.providerID.toString(), "anthropic", "default model provider");
		eq(configuredDefault.modelID.toString(), "claude-sonnet-4-20250514", "default model id");

		final small = custom.smallModel(ProviderIDs.known("anthropic"));
		if (small == null)
			throw "small model: expected model";
		eq(small.id.toString(), "claude-haiku-4-5", "small model priority");
		final smallOverride = registry(config({small_model: "anthropic/claude-sonnet-4-20250514"}),
			{ANTHROPIC_API_KEY: "test-api-key"}).smallModel(ProviderIDs.known("anthropic"));
		eq(requireModel(smallOverride, "small model override").id.toString(), "claude-sonnet-4-20250514", "small_model config override");
		eq(requireModel(smallPriorityRegistry("opencode", ["gpt-5.2", "gpt-5-nano"]).smallModel(ProviderIDs.known("opencode")),
			"opencode small priority").id.toString(),
			"gpt-5-nano", "opencode small prefers nano");
		eq(requireModel(smallPriorityRegistry("github-copilot",
			["claude-haiku-4.5", "gpt-5-nano", "gpt-5-mini"]).smallModel(ProviderIDs.known("github-copilot")),
			"copilot small priority").id.toString(),
			"gpt-5-mini", "copilot small prefers mini");
		eq(requireModel(smallPriorityRegistry("github-copilot", ["claude-haiku-4.5", "gpt-5-nano"]).smallModel(ProviderIDs.known("github-copilot")),
			"copilot small fallback").id.toString(),
			"claude-haiku-4.5", "copilot small falls back to haiku");

		eq(custom.getProvider(ProviderID.make("missing-provider")) == null, true, "missing provider lookup returns null");
		eq(requireProvider(custom.getProvider(ProviderIDs.known("anthropic")), "anthropic provider lookup").id.toString(), "anthropic", "provider lookup info");

		final closest = custom.closest(ProviderIDs.known("anthropic"), ["sonnet-4"]);
		if (closest == null)
			throw "closest model: expected match";
		eq(closest.providerID.toString(), "anthropic", "closest provider id");
		eq(closest.modelID.toString().indexOf("sonnet-4") != -1, true, "closest partial match");
		eq(custom.closest(ProviderID.make("missing-provider"), ["model"]) == null, true, "closest missing provider");
		eq(custom.closest(ProviderIDs.known("anthropic"), ["nonexistent-xyz-model"]) == null, true, "closest no partial match");
		final secondClosest = custom.closest(ProviderIDs.known("anthropic"), ["nonexistent", "haiku"]);
		if (secondClosest == null)
			throw "closest model: expected second query match";
		eq(secondClosest.modelID.toString().indexOf("haiku") != -1, true, "closest checks query terms in order");

		final sortable:Array<{final id:String; final name:String;}> = [
			{id: "random-model", name: "Random"},
			{id: "claude-sonnet-4-latest", name: "Claude Sonnet 4"},
			{id: "gpt-5-turbo", name: "GPT-5 Turbo"},
			{id: "other-model", name: "Other"},
		];
		final sorted = ProviderRegistry.sort(sortable);
		eq(sorted[0].id, "claude-sonnet-4-latest", "provider sort prefers sonnet latest");
		eq(sorted[1].id, "gpt-5-turbo", "provider sort keeps priority order");
		eq(sorted[sorted.length - 1].id, "other-model", "provider sort leaves unprioritized last by id");

		expectProviderFailure(() -> custom.getModel(ProviderIDs.known("anthropic"), ModelID.make("missing-model")), "missing model", function(failure) {
			return switch failure {
				case ModelNotFound(providerID, modelID, _): providerID.toString() == "anthropic" && modelID.toString() == "missing-model";
				case _: false;
			}
		});
		expectProviderFailure(() -> custom.getModel(ProviderIDs.known("anthropic"), ModelID.make("claude-sonet-4")), "model typo suggestions",
			function(failure) {
				return switch failure {
					case ModelNotFound(_, _, suggestions): suggestions.indexOf("claude-sonnet-4-20250514") != -1;
					case _: false;
				}
			});
		expectProviderFailure(() -> custom.getModel(ProviderID.make("antropic"), ModelID.make("claude-sonnet-4")), "provider typo suggestions",
			function(failure) {
				return switch failure {
					case ModelNotFound(_, _, suggestions): suggestions.indexOf("anthropic") != -1;
					case _: false;
				}
			});
	}

	static function registryAuthAndBedrock():Void {
		final authRegistry = registry(config({}), {}, {"openai": {type: "api", key: "auth-key"}});
		final openai = authRegistry.getProvider(ProviderIDs.known("openai"));
		eq(openai.source, "api", "api auth source");
		eq(openai.key, "auth-key", "api auth key");

		final bedrockConfig = registry(config({
			provider: {
				"amazon-bedrock": {
					options: {
						region: "eu-west-1",
						profile: "config-profile",
						endpoint: "https://bedrock-runtime.example.com",
					},
				},
			},
		}), {AWS_REGION: "us-east-1", AWS_PROFILE: "default"});
		final bedrock = bedrockConfig.getProvider(ProviderIDs.known("amazon-bedrock"));
		eq(ProviderOptionAccess.string(bedrock.options, "region", null), "eu-west-1", "bedrock config region");
		eq(ProviderOptionAccess.string(bedrock.options, "profile", null), "config-profile", "bedrock config profile");
		eq(ProviderOptionAccess.string(bedrock.options, "baseURL", null), "https://bedrock-runtime.example.com", "bedrock endpoint baseURL");

		final bedrockEnv = registry(config({}), {AWS_REGION: "eu-west-1", AWS_PROFILE: "default"});
		eq(ProviderOptionAccess.string(bedrockEnv.getProvider(ProviderIDs.known("amazon-bedrock"))
			.options, "region", null), "eu-west-1", "bedrock env region");

		final bedrockAuth = registry(config({
			provider: {
				"amazon-bedrock": {options: {region: "us-east-1"}},
			},
		}), {}, {"amazon-bedrock": {type: "api", key: "bearer"}});
		final authBedrock = bedrockAuth.getProvider(ProviderIDs.known("amazon-bedrock"));
		eq(authBedrock != null, true, "bedrock auth bearer");
		eq(ProviderOptionAccess.string(authBedrock.options, "apiKey", null), "bearer", "bedrock bearer apiKey");

		final webIdentity = registry(config({
			provider: {
				"amazon-bedrock": {options: {region: "us-east-1"}},
			},
		}),
			{AWS_WEB_IDENTITY_TOKEN_FILE: "/var/run/secrets/eks.amazonaws.com/serviceaccount/token", AWS_PROFILE: "", AWS_ACCESS_KEY_ID: ""});
		eq(webIdentity.getProvider(ProviderIDs.known("amazon-bedrock")) != null, true, "bedrock web identity autoload");

		bedrockCrossRegionPrefixes(authBedrock);
		bedrockSmallModelSelection();
	}

	static function bedrockCrossRegionPrefixes(provider:opencodehx.provider.ProviderTypes.ProviderInfo):Void {
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("global.anthropic.claude-opus-4-5-20251101-v1:0"), true, "bedrock global prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("us.anthropic.claude-opus-4-5-20251101-v1:0"), true, "bedrock us prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("eu.anthropic.claude-opus-4-5-20251101-v1:0"), true, "bedrock eu prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("jp.anthropic.claude-sonnet-4-20250514-v1:0"), true, "bedrock jp prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("apac.anthropic.claude-sonnet-4-20250514-v1:0"), true, "bedrock apac prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("au.anthropic.claude-sonnet-4-5-20250929-v1:0"), true, "bedrock au prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("anthropic.claude-opus-4-5-20251101-v1:0"), false, "bedrock unprefixed");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("amazon.nova-pro-v1:0"), false, "bedrock nova no false prefix");
		eq(BedrockLanguageLoader.hasCrossRegionPrefix("cohere.command-r-plus-v1:0"), false, "bedrock cohere no false prefix");

		eq(BedrockLanguageLoader.sdkModelID("global.anthropic.claude-haiku-4-5-20250929-v1:0", "us-east-1"),
			"global.anthropic.claude-haiku-4-5-20250929-v1:0", "bedrock preserves global prefix");
		eq(BedrockLanguageLoader.sdkModelID("anthropic.claude-sonnet-4-20250514-v1:0", "us-east-1"), "us.anthropic.claude-sonnet-4-20250514-v1:0",
			"bedrock us claude prefix");
		eq(BedrockLanguageLoader.sdkModelID("anthropic.claude-sonnet-4-20250514-v1:0", "us-gov-west-1"), "anthropic.claude-sonnet-4-20250514-v1:0",
			"bedrock govcloud no us prefix");
		eq(BedrockLanguageLoader.sdkModelID("anthropic.claude-opus-4-5-20251101-v1:0", "eu-west-1"), "eu.anthropic.claude-opus-4-5-20251101-v1:0",
			"bedrock eu claude prefix");
		eq(BedrockLanguageLoader.sdkModelID("meta.llama3-70b-instruct-v1:0", "eu-central-1"), "eu.meta.llama3-70b-instruct-v1:0", "bedrock eu llama prefix");
		eq(BedrockLanguageLoader.sdkModelID("anthropic.claude-sonnet-4-20250514-v1:0", "ap-northeast-1"), "jp.anthropic.claude-sonnet-4-20250514-v1:0",
			"bedrock tokyo prefix");
		eq(BedrockLanguageLoader.sdkModelID("anthropic.claude-sonnet-4-20250514-v1:0", "ap-south-1"), "apac.anthropic.claude-sonnet-4-20250514-v1:0",
			"bedrock apac prefix");
		eq(BedrockLanguageLoader.sdkModelID("anthropic.claude-sonnet-4-5-20250929-v1:0", "ap-southeast-2"), "au.anthropic.claude-sonnet-4-5-20250929-v1:0",
			"bedrock australia prefix");
		eq(BedrockLanguageLoader.sdkModelID("cohere.command-r-plus-v1:0", "us-east-1"), "cohere.command-r-plus-v1:0", "bedrock cohere stays unprefixed");

		final base = provider.models.get("anthropic.claude-sonnet-4-20250514-v1:0");
		if (base == null)
			throw "Missing Bedrock Claude Sonnet fixture model";
		final resolution = AiSdkLanguageLoader.resolve(provider, base);
		eq(resolution.sdkModelID, "us.anthropic.claude-sonnet-4-20250514-v1:0", "bedrock sdk loader model prefix");
		eq(resolution.language.modelId, "us.anthropic.claude-sonnet-4-20250514-v1:0", "bedrock language model id");
	}

	static function bedrockSmallModelSelection():Void {
		final providerID = ProviderIDs.known("amazon-bedrock");
		final unprefixed = "anthropic.claude-haiku-4-5-20250929-v1:0";
		final us = "us.anthropic.claude-haiku-4-5-20250929-v1:0";
		final eu = "eu.anthropic.claude-haiku-4-5-20250929-v1:0";
		final global = "global.anthropic.claude-haiku-4-5-20250929-v1:0";

		eq(requireModel(bedrockSmallRegistry("us-east-1", [unprefixed, us]).smallModel(providerID), "bedrock us small").id.toString(), us,
			"bedrock small prefers us regional");
		eq(requireModel(bedrockSmallRegistry("eu-west-1", [unprefixed, eu]).smallModel(providerID), "bedrock eu small").id.toString(), eu,
			"bedrock small prefers eu regional");
		eq(requireModel(bedrockSmallRegistry("us-east-1", [unprefixed, us, global]).smallModel(providerID), "bedrock global small").id.toString(), global,
			"bedrock small prefers global");
		eq(requireModel(bedrockSmallRegistry("ap-south-1", [unprefixed, us]).smallModel(providerID), "bedrock fallback small").id.toString(), unprefixed,
			"bedrock small falls back to unprefixed");
	}

	static function cloudflareAiGatewayLoading():Void {
		final partial = registry(config({}), {
			CLOUDFLARE_ACCOUNT_ID: "test-account",
			CLOUDFLARE_GATEWAY_ID: "test-gateway",
		});
		eq(partial.getProvider(ProviderIDs.known("cloudflare-ai-gateway")) == null, true, "cloudflare gateway requires token");

		final loaded = registry(config({}), {
			CLOUDFLARE_ACCOUNT_ID: "test-account",
			CLOUDFLARE_GATEWAY_ID: "test-gateway",
			CLOUDFLARE_API_TOKEN: "test-token",
		});
		final provider = loaded.getProvider(ProviderIDs.known("cloudflare-ai-gateway"));
		eq(provider != null, true, "cloudflare gateway env autoload");
		eq(provider.models.exists("openai/gpt-5.2-codex"), true, "cloudflare gateway default model");

		final configured = registry(config({
			provider: {
				"cloudflare-ai-gateway": {
					options: {
						metadata: {
							invoked_by: "test",
							project: "opencode",
						},
					},
				},
			},
		}), {
			CLOUDFLARE_ACCOUNT_ID: "test-account",
			CLOUDFLARE_GATEWAY_ID: "test-gateway",
			CLOUDFLARE_API_TOKEN: "test-token",
		});
		final metadata = ProviderOptionAccess.unknownRecord(configured.getProvider(ProviderIDs.known("cloudflare-ai-gateway")).options, "metadata");
		if (metadata == null)
			throw "cloudflare metadata: expected record";
		eq(UnknownNarrow.string(metadata.get("invoked_by")), "test", "cloudflare metadata invoked_by");
		eq(UnknownNarrow.string(metadata.get("project")), "opencode", "cloudflare metadata project");
	}

	static function gitlabDuoLoading():Void {
		eq(registry(config({})).getProvider(ProviderIDs.known("gitlab")) == null, true, "gitlab requires token");

		final envLoaded = registry(config({}), {GITLAB_TOKEN: "test-gitlab-token"});
		final gitlab = requireProvider(envLoaded.getProvider(ProviderIDs.known("gitlab")), "gitlab env");
		eq(gitlab.source, "env", "gitlab env source");
		eq(gitlab.key, "test-gitlab-token", "gitlab env key");
		eq(ProviderOptionAccess.string(gitlab.options, "instanceUrl", null), "https://gitlab.com", "gitlab default instanceUrl");
		final headers = ProviderOptionAccess.stringMap(gitlab.options, "aiGatewayHeaders");
		eq(requiredStringMapValue(headers, "anthropic-beta", "gitlab context header").indexOf("context-1m-2025-08-07") != -1, true, "gitlab context header");
		final featureFlags = ProviderOptionAccess.boolMap(gitlab.options, "featureFlags");
		if (featureFlags == null)
			throw "gitlab feature flags: expected record";
		eq(featureFlags.get("duo_agent_platform_agentic_chat"), true, "gitlab agentic chat feature flag");
		eq(gitlab.models.exists("duo-chat-haiku-4-5"), true, "gitlab haiku static model");
		eq(gitlab.models.exists("duo-chat-sonnet-4-5"), true, "gitlab sonnet static model");
		eq(gitlab.models.exists("duo-chat-opus-4-5"), true, "gitlab opus static model");

		final envInstance = registry(config({}), {GITLAB_TOKEN: "env-token", GITLAB_INSTANCE_URL: "https://gitlab.example.com"});
		eq(ProviderOptionAccess.string(envInstance.getProvider(ProviderIDs.known("gitlab")).options, "instanceUrl", null), "https://gitlab.example.com",
			"gitlab env instanceUrl");

		final configured = registry(config({
			provider: {
				gitlab: {
					options: {
						instanceUrl: "https://gitlab.company.internal",
						apiKey: "config-token",
						aiGatewayHeaders: {
							"X-GitLab-Fixture": "configured",
						},
						featureFlags: {
							duo_agent_platform: false,
							custom_flag: true,
						},
					},
				},
			},
		}), {GITLAB_TOKEN: "env-token"});
		final configuredGitlab = configured.getProvider(ProviderIDs.known("gitlab"));
		eq(configuredGitlab.source, "config", "gitlab config apiKey source");
		eq(configuredGitlab.key, "config-token", "gitlab config apiKey precedence");
		eq(ProviderOptionAccess.string(configuredGitlab.options, "instanceUrl", null), "https://gitlab.company.internal", "gitlab config instanceUrl");
		final configuredHeaders = ProviderOptionAccess.stringMap(configuredGitlab.options, "aiGatewayHeaders");
		eq(stringMapValue(configuredHeaders, "X-GitLab-Fixture"), "configured", "gitlab custom gateway header");
		eq(requiredStringMapValue(configuredHeaders, "anthropic-beta", "gitlab default gateway header").indexOf("context-1m-2025-08-07") != -1, true,
			"gitlab default gateway header survives config");
		final configuredFlags = ProviderOptionAccess.boolMap(configuredGitlab.options, "featureFlags");
		if (configuredFlags == null)
			throw "configured gitlab feature flags: expected record";
		eq(configuredFlags.get("duo_agent_platform"), false, "gitlab feature flag override");
		eq(configuredFlags.get("custom_flag"), true, "gitlab custom feature flag");

		final apiAuth = registry(config({}), {}, {gitlab: {type: "api", key: "glpat-test-pat-token"}});
		eq(apiAuth.getProvider(ProviderIDs.known("gitlab")).key, "glpat-test-pat-token", "gitlab api auth key");

		final oauth = registry(config({}), {}, {gitlab: {type: "oauth", access: "oauth-access-token"}});
		final oauthGitlab = oauth.getProvider(ProviderIDs.known("gitlab"));
		eq(oauthGitlab.source, "oauth", "gitlab oauth source");
		eq(oauthGitlab.key, "oauth-access-token", "gitlab oauth access key");
	}

	static function opencodePaidModelLoading():Void {
		eq(paidModelCount(registry(config({}))), 0, "opencode public hides paid models");

		final configured = registry(config({
			provider: {
				opencode: {
					options: {
						apiKey: "test-key",
					},
				},
			},
		}));
		eq(paidModelCount(configured) > 0, true, "opencode config apiKey keeps paid models");

		final authenticated = registry(config({}), {}, {
			opencode: {
				type: "api",
				key: "test-key",
			},
		});
		eq(paidModelCount(authenticated) > 0, true, "opencode auth keeps paid models");

		final env = registry(config({}), {OPENCODE_API_KEY: "test-key"});
		eq(paidModelCount(env) > 0, true, "opencode env key keeps paid models");
	}

	static function modelsDevNormalization():Void {
		final modeBody = unknownMap([{key: "service_tier", value: "priority"}]);
		final fastModes = modelsDevModes([
			{
				key: "fast",
				value: {
					cost: {
						input: 5,
						output: 30,
						cache_read: 0.5,
					},
					provider: {
						body: modeBody,
					},
				},
			},
		]);
		final modelsProvider:ModelsDevProvider = {
			id: "openai",
			name: "OpenAI",
			env: [],
			api: "https://api.openai.com/v1",
			models: modelsDevModels([
				{
					key: "gpt-5.4",
					value: {
						id: "gpt-5.4",
						name: "GPT-5.4",
						family: "gpt",
						release_date: "2026-03-05",
						attachment: true,
						reasoning: true,
						temperature: false,
						tool_call: true,
						cost: {
							input: 2.5,
							output: 15,
							cache_read: 0.25,
							context_over_200k: {
								input: 5,
								output: 22.5,
								cache_read: 0.5,
							},
						},
						limit: {
							context: 1050000,
							input: 922000,
							output: 128000,
						},
						experimental: {
							modes: fastModes,
						},
					},
				},
			]),
		};

		final info = ProviderRegistry.fromModelsDevProvider(modelsProvider);
		final base = info.models.get("gpt-5.4");
		eq(base.api.url, "https://api.openai.com/v1", "models.dev provider api inherited");
		eq(base.variants.exists("high"), true, "models.dev reasoning variants");

		final fast = info.models.get("gpt-5.4-fast");
		eq(fast.name, "GPT-5.4 Fast", "models.dev mode name");
		eq(fast.cost.input, 5, "models.dev mode input cost");
		eq(fast.cost.output, 30, "models.dev mode output cost");
		eq(fast.cost.cache.read, 0.5, "models.dev mode cache read");
		eq(fast.cost.cache.write, 0, "models.dev mode cache write");
		eq(Std.string(fast.options.get("serviceTier")), "priority", "models.dev body camel case");
		if (fast.cost.experimentalOver200K == null)
			throw "models.dev mode over-200k cost missing";
		eq(fast.cost.experimentalOver200K.input, 5, "models.dev mode over-200k input");
		eq(fast.cost.experimentalOver200K.output, 22.5, "models.dev mode over-200k output");
		eq(fast.cost.experimentalOver200K.cache.read, 0.5, "models.dev mode over-200k cache read");
		eq(fast.cost.experimentalOver200K.cache.write, 0, "models.dev mode over-200k cache write");

		final defaults = ProviderRegistry.fromModelsDevProvider({
			id: "gateway",
			name: "Gateway",
			env: [],
			models: modelsDevModels([
				{
					key: "gpt-5.4",
					value: {
						id: "gpt-5.4",
						name: "GPT-5.4",
						family: "gpt",
						cost: {
							input: 2.5,
							output: 15,
						},
						limit: {
							context: 1050000,
							input: 922000,
							output: 128000,
						},
					},
				},
			]),
		}).models.get("gpt-5.4");
		eq(defaults.api.url, "", "models.dev default api url");
		eq(defaults.capabilities.temperature, false, "models.dev default temperature");
		eq(defaults.capabilities.reasoning, false, "models.dev default reasoning");
		eq(defaults.capabilities.attachment, false, "models.dev default attachment");
		eq(defaults.capabilities.toolcall, true, "models.dev default tool calls");
		eq(defaults.release_date, "", "models.dev default release date");

		final parsed = ProviderModelsDev.parse('{"bad":{"id":"bad","name":"Bad","env":[],"models":{"broken":{"id":"broken","name":"Broken","limit":{"context":"invalid","output":1}}}},"good":{"id":"good","name":"Good","env":[],"models":{"good-model":{"id":"good-model","name":"Good Model","limit":{"context":1000,"output":200}}}}}');
		eq(catalogCount(parsed), 1, "models.dev parser skips invalid provider");
		eq(ProviderRegistry.fromModelsDevCatalog(parsed).get("good").models.get("good-model").name, "Good Model", "models.dev parser keeps valid provider");
	}

	@:async
	static function modelsDevFetchCache(root:String):Promise<Void> {
		final remoteText = modelsDevCatalogText("remote", "Remote Provider", "remote-model", "Remote Model", "https://api.remote.example/v1");
		final calls:Array<ModelsDevFetchRequest> = [];
		final baseOptions:ModelsDevOptions = {
			cacheDir: root,
			sourceUrl: "https://models.example",
			fetcher: modelsDevFetcher([remoteText], calls),
			ttlMs: 60000,
		};
		final first = @:await ProviderModelsDev.get(baseOptions);
		eq(calls.length, 1, "models.dev fetch count");
		eq(calls[0].url, "https://models.example/api.json", "models.dev fetch url");
		eq(calls[0].headers.get("User-Agent"), 'opencodehx/${BuildInfo.version}', "models.dev user agent");
		final cachePath = ProviderModelsDev.cacheFile(baseOptions);
		eq(Fs.existsSync(cachePath), true, "models.dev cache written");
		final mapped = ProviderRegistry.fromModelsDevCatalog(first);
		eq(mapped.get("remote").models.get("remote-model").name, "Remote Model", "models.dev catalog mapped");

		final cachedCalls:Array<ModelsDevFetchRequest> = [];
		final cached = @:await ProviderModelsDev.get({
			cacheDir: root,
			sourceUrl: "https://models.example",
			fetcher: modelsDevFetcher([modelsDevCatalogText("wrong", "Wrong", "wrong-model", "Wrong Model", "")], cachedCalls),
		});
		eq(cachedCalls.length, 0, "models.dev cached read skips fetch");
		eq(ProviderRegistry.fromModelsDevCatalog(cached).get("remote").name, "Remote Provider", "models.dev cached provider");

		final skippedCalls:Array<ModelsDevFetchRequest> = [];
		final skipped = @:await ProviderModelsDev.refresh(false, {
			cacheDir: root,
			sourceUrl: "https://models.example",
			fetcher: modelsDevFetcher([modelsDevCatalogText("skip", "Skip", "skip-model", "Skip Model", "")], skippedCalls),
			now: () -> Fs.statSync(cachePath).mtimeMs,
			ttlMs: 60000,
		});
		eq(skipped, false, "models.dev fresh refresh skipped");
		eq(skippedCalls.length, 0, "models.dev fresh refresh no fetch");

		final refreshCalls:Array<ModelsDevFetchRequest> = [];
		final refreshed = @:await ProviderModelsDev.refresh(true, {
			cacheDir: root,
			sourceUrl: "https://models.example",
			fetcher: modelsDevFetcher([
				modelsDevCatalogText("remote", "Remote Provider Updated", "remote-model", "Updated Model", "")
			], refreshCalls),
		});
		eq(refreshed, true, "models.dev forced refresh");
		eq(refreshCalls.length, 1, "models.dev forced refresh fetch count");
		final refreshedCatalog = @:await ProviderModelsDev.get({cacheDir: root, sourceUrl: "https://models.example", disableFetch: true});
		eq(ProviderRegistry.fromModelsDevCatalog(refreshedCatalog)
			.get("remote")
			.models.get("remote-model")
			.name, "Updated Model",
			"models.dev refreshed cache read");

		final snapshot = ProviderModelsDev.parse(modelsDevCatalogText("snapshot", "Snapshot Provider", "snapshot-model", "Snapshot Model", ""));
		final snapshotCatalog = @:await ProviderModelsDev.get({
			cacheDir: NodePath.join(root, "snapshot-cache"),
			sourceUrl: "https://snapshot.example",
			disableFetch: true,
			snapshot: snapshot,
		});
		eq(ProviderRegistry.fromModelsDevCatalog(snapshotCatalog).get("snapshot").name, "Snapshot Provider", "models.dev snapshot fallback");

		final filePath = NodePath.join(root, "models-file.json");
		Fs.writeFileSync(filePath, modelsDevCatalogText("file", "File Provider", "file-model", "File Model", ""), "utf8");
		final fileCalls:Array<ModelsDevFetchRequest> = [];
		final fileCatalog = @:await ProviderModelsDev.get({
			cacheDir: NodePath.join(root, "file-cache"),
			modelsPath: filePath,
			fetcher: modelsDevFetcher([modelsDevCatalogText("wrong", "Wrong", "wrong-model", "Wrong Model", "")], fileCalls),
		});
		eq(fileCalls.length, 0, "models.dev path skips fetch");
		eq(ProviderRegistry.fromModelsDevCatalog(fileCatalog).get("file").models.get("file-model").name, "File Model", "models.dev path provider");

		final disabled = @:await ProviderModelsDev.get({
			cacheDir: NodePath.join(root, "disabled-cache"),
			sourceUrl: "https://disabled.example",
			disableFetch: true,
		});
		eq(catalogCount(disabled), 0, "models.dev disabled fetch empty");
	}

	static function registry(config:ConfigInfo, ?env:Dynamic, ?auth:Dynamic, ?pluginHooks:Array<PluginServerHooks>):ProviderRegistry {
		return new ProviderRegistry({
			config: config,
			env: env == null ? {} : env,
			auth: auth == null ? {} : auth,
			pluginHooks: pluginHooks
		});
	}

	static function registryModelVariants():Void {
		final generated = registry(config({}), {ANTHROPIC_API_KEY: "test-api-key"});
		final generatedModel = generated.getModel(ProviderIDs.known("anthropic"), ModelID.make("claude-sonnet-4-20250514"));
		eq(generatedModel.variants.exists("high"), true, "reasoning model high variant generated");
		eq(generatedModel.variants.exists("max"), true, "reasoning model max variant generated");

		final databaseVariantFilter = registry(config({
			provider: {
				openai: {
					models: {
						"gpt-5.2": {
							variants: {
								high: {disabled: true},
							},
						},
					},
				},
			},
		}),
			{OPENAI_API_KEY: "openai-key"}).getModel(ProviderIDs.known("openai"), ModelID.make("gpt-5.2"));
		eq(databaseVariantFilter.variants.exists("high"), false, "database model high variant removed in final pass");
		eq(databaseVariantFilter.variants.exists("medium"), true, "database model medium variant remains after final pass");

		final customReasoning = registry(config({
			provider: {
				"custom-reasoning": {
					name: "Custom Reasoning",
					npm: "@ai-sdk/openai-compatible",
					api: "https://reasoning.example.com/v1",
					models: {
						"reasoning-model": {
							name: "Reasoning Model",
							reasoning: true,
							limit: {context: 128000, output: 16000},
							variants: {
								low: {reasoningEffort: "low"},
								medium: {reasoningEffort: "medium"},
								high: {reasoningEffort: "high", disabled: true},
								custom: {reasoningEffort: "custom", budgetTokens: 5000},
							},
						},
					},
					options: {apiKey: "reasoning-key"},
				},
			},
		})).getModel(ProviderID.make("custom-reasoning"), ModelID.make("reasoning-model"));
		eq(customReasoning.variants.exists("low"), true, "custom reasoning low variant kept");
		eq(customReasoning.variants.exists("medium"), true, "custom reasoning medium variant kept");
		eq(customReasoning.variants.exists("custom"), true, "custom reasoning custom variant kept");
		eq(customReasoning.variants.exists("high"), false, "custom reasoning disabled variant removed");
		eq(requiredOptionNumber(customReasoning.variants.get("custom"), "budgetTokens", "custom reasoning variant budget"), 5000.0,
			"custom reasoning variant option kept");
		eq(optionHasKnownField(customReasoning.variants.get("low"), "disabled"), false, "custom reasoning enabled variant stripped");

		final disabledHigh = variantRegistry({
			high: {disabled: true},
		});
		eq(disabledHigh.variants.exists("high"), false, "disabled variant removed");
		eq(disabledHigh.variants.exists("max"), true, "other generated variant remains");

		final customHigh = variantRegistry({
			high: {
				thinking: {
					type: "enabled",
					budgetTokens: 20000,
				},
			},
		});
		final highThinking = requiredOptionRecord(customHigh.variants.get("high"), "thinking", "custom high thinking");
		eq(UnknownNarrow.number(highThinking.get("budgetTokens")), 20000.0, "variant config customizes nested option");

		final stripped = variantRegistry({
			max: {
				disabled: false,
				customField: "test",
			},
		});
		eq(stripped.variants.exists("max"), true, "enabled configured variant remains");
		eq(optionHasKnownField(stripped.variants.get("max"), "disabled"), false, "variant disabled key stripped");
		eq(requiredOptionString(stripped.variants.get("max"), "customField", "max custom field"), "test", "variant custom field kept");

		final allDisabled = variantRegistry({
			high: {disabled: true},
			max: {disabled: true},
		});
		eq(variantCount(allDisabled), 0, "all variants disabled");

		final merged = variantRegistry({
			high: {extraOption: "custom-value"},
		});
		eq(optionHasKnownField(merged.variants.get("high"), "thinking"), true, "variant generated option retained");
		eq(requiredOptionString(merged.variants.get("high"), "extraOption", "high extra option"), "custom-value", "variant config option merged");
	}

	static function registryVertexProviders():Void {
		final vertex = registry(config({
			provider: {
				"google-vertex-proxy": {
					name: "Vertex Proxy",
					npm: "@ai-sdk/google-vertex",
					api: "https://my-proxy.com/v1",
					env: ["GOOGLE_APPLICATION_CREDENTIALS"],
					models: {
						"gemini-pro": {
							name: "Gemini Pro",
							reasoning: true,
							provider: {
								api: "https://my-proxy.com/v1",
							},
						},
					},
					options: {
						project: "fixture-project",
						location: "us-central1",
						baseURL: "https://my-proxy.com/v1",
					},
				},
				"google-vertex-openai": {
					name: "Vertex OpenAI Compatible",
					npm: "@ai-sdk/google-vertex",
					env: ["GOOGLE_APPLICATION_CREDENTIALS"],
					models: {
						"gpt-4": {
							name: "GPT-4 via Vertex",
							provider: {
								npm: "@ai-sdk/openai-compatible",
								api: "https://api.openai.com/v1",
							},
						},
					},
					options: {
						project: "fixture-project",
						location: "us-central1",
					},
				},
			},
		}), {GOOGLE_APPLICATION_CREDENTIALS: "/tmp/google-credentials.json"});
		final proxyProvider = vertex.getProvider(ProviderID.make("google-vertex-proxy"));
		eq(requiredOptionString(proxyProvider.options, "baseURL", "vertex proxy baseURL"), "https://my-proxy.com/v1", "vertex proxy baseURL option preserved");
		final gemini = vertex.getModel(ProviderID.make("google-vertex-proxy"), ModelID.make("gemini-pro"));
		eq(gemini.api.npm, "@ai-sdk/google-vertex", "vertex proxy model inherits provider npm");
		eq(gemini.api.url, "https://my-proxy.com/v1", "vertex proxy model api override");
		eq(gemini.variants.exists("low"), true, "vertex reasoning low variant generated");
		final openaiModel = vertex.getModel(ProviderID.make("google-vertex-openai"), ModelID.make("gpt-4"));
		eq(openaiModel.api.npm, "@ai-sdk/openai-compatible", "vertex model provider npm override");
		eq(openaiModel.api.url, "https://api.openai.com/v1", "vertex model provider api override");
	}

	static function demoProviderHook():PluginServerHooks {
		return {
			config: cfg -> {
				if (cfg.provider == null)
					cfg.provider = new haxe.DynamicAccess<ConfigProviderConfig>();
				cfg.provider.set("demo", {
					name: "Demo Provider",
					npm: "@ai-sdk/openai-compatible",
					api: "https://example.com/v1",
					models: configProviderModels([
						{
							key: "chat",
							value: {
								name: "Demo Chat",
								tool_call: true,
								limit: {
									context: 128000,
									output: 4096,
								},
							},
						},
					]),
				});
			},
		};
	}

	static function modelsDevModels(entries:Array<{final key:String; final value:ModelsDevModel;}>):DynamicAccess<ModelsDevModel> {
		final result = new DynamicAccess<ModelsDevModel>();
		for (entry in entries)
			result.set(entry.key, entry.value);
		return result;
	}

	static function modelsDevModes(entries:Array<{final key:String; final value:opencodehx.provider.ProviderTypes.ModelsDevMode;}>):DynamicAccess<opencodehx.provider.ProviderTypes.ModelsDevMode> {
		final result = new DynamicAccess<opencodehx.provider.ProviderTypes.ModelsDevMode>();
		for (entry in entries)
			result.set(entry.key, entry.value);
		return result;
	}

	static function configProviderModels(entries:Array<{final key:String; final value:ConfigProviderModelConfig;}>):DynamicAccess<ConfigProviderModelConfig> {
		final result = new DynamicAccess<ConfigProviderModelConfig>();
		for (entry in entries)
			result.set(entry.key, entry.value);
		return result;
	}

	static function bedrockSmallRegistry(region:String, modelIDs:Array<String>):ProviderRegistry {
		final providerConfig = new DynamicAccess<ConfigProviderConfig>();
		providerConfig.set("amazon-bedrock", {
			options: bedrockProviderOptions(region),
		});
		final info = ConfigInfo.empty("fixture-user");
		info.provider = providerConfig;
		return new ProviderRegistry({
			config: info,
			env: {},
			auth: {},
			database: bedrockDatabase(modelIDs),
		});
	}

	static function bedrockProviderOptions(region:String):ProviderOptions {
		final options:ProviderOptions = new DynamicAccess();
		options.set("region", region);
		return options;
	}

	static function bedrockDatabase(modelIDs:Array<String>):Map<String, ProviderInfo> {
		final providers = new Map<String, ProviderInfo>();
		final models = new Map<String, ProviderModel>();
		for (id in modelIDs)
			models.set(id, bedrockModel(id));
		providers.set("amazon-bedrock", {
			id: ProviderIDs.known("amazon-bedrock"),
			name: "Amazon Bedrock",
			source: "custom",
			env: [],
			options: bedrockProviderOptions("us-east-1"),
			models: models,
		});
		return providers;
	}

	static function bedrockModel(id:String):ProviderModel {
		return {
			id: ModelID.make(id),
			providerID: ProviderIDs.known("amazon-bedrock"),
			name: id,
			family: "claude",
			api: {
				id: id,
				url: "",
				npm: "@ai-sdk/amazon-bedrock",
			},
			status: "active",
			capabilities: {
				temperature: true,
				reasoning: true,
				attachment: true,
				toolcall: true,
				input: {
					text: true,
					audio: false,
					image: true,
					video: false,
					pdf: true
				},
				output: {
					text: true,
					audio: false,
					image: false,
					video: false,
					pdf: false
				},
				interleaved: false,
			},
			cost: {input: 0, output: 0, cache: {read: 0, write: 0}},
			limit: {context: 200000, output: 32000},
			options: new DynamicAccess(),
			headers: new DynamicAccess(),
			release_date: "",
			variants: new DynamicAccess(),
		};
	}

	static function smallPriorityRegistry(providerID:String, modelIDs:Array<String>):ProviderRegistry {
		final providerConfig = new DynamicAccess<ConfigProviderConfig>();
		providerConfig.set(providerID, {});
		final info = ConfigInfo.empty("fixture-user");
		info.provider = providerConfig;
		return new ProviderRegistry({
			config: info,
			env: {},
			auth: {},
			database: smallPriorityDatabase(providerID, modelIDs),
		});
	}

	static function smallPriorityDatabase(providerID:String, modelIDs:Array<String>):Map<String, ProviderInfo> {
		final providers = new Map<String, ProviderInfo>();
		final models = new Map<String, ProviderModel>();
		for (id in modelIDs)
			models.set(id, smallPriorityModel(providerID, id));
		providers.set(providerID, {
			id: ProviderID.make(providerID),
			name: providerID,
			source: "custom",
			env: [],
			options: new DynamicAccess(),
			models: models,
		});
		return providers;
	}

	static function smallPriorityModel(providerID:String, id:String):ProviderModel {
		return {
			id: ModelID.make(id),
			providerID: ProviderID.make(providerID),
			name: id,
			family: "",
			api: {
				id: id,
				url: "",
				npm: "@ai-sdk/openai-compatible",
			},
			status: "active",
			capabilities: {
				temperature: true,
				reasoning: true,
				attachment: true,
				toolcall: true,
				input: {
					text: true,
					audio: false,
					image: false,
					video: false,
					pdf: false
				},
				output: {
					text: true,
					audio: false,
					image: false,
					video: false,
					pdf: false
				},
				interleaved: false,
			},
			cost: {input: 0, output: 0, cache: {read: 0, write: 0}},
			limit: {context: 200000, output: 10000},
			options: new DynamicAccess(),
			headers: new DynamicAccess(),
			release_date: "",
			variants: new DynamicAccess(),
		};
	}

	static function unknownMap(entries:Array<{final key:String; final value:String;}>):DynamicAccess<Unknown> {
		final result = new DynamicAccess<Unknown>();
		for (entry in entries)
			result.set(entry.key, Unknown.fromBoundary(entry.value));
		return result;
	}

	static function modelsDevFetcher(payloads:Array<String>, calls:Array<ModelsDevFetchRequest>):ModelsDevFetchFunction {
		var index = 0;
		return request -> {
			calls.push(request);
			final payload = payloads[index < payloads.length ? index : payloads.length - 1];
			index++;
			return Promise.resolve({
				ok: true,
				status: 200,
				text: payload,
			});
		};
	}

	static function modelsDevCatalogText(providerID:String, providerName:String, modelID:String, modelName:String, api:String):String {
		return
			'{"${providerID}":{"id":"${providerID}","name":"${providerName}","env":[],"api":"${api}","models":{"${modelID}":{"id":"${modelID}","name":"${modelName}","family":"fixture","release_date":"2026-01-01","attachment":true,"reasoning":true,"temperature":false,"tool_call":true,"cost":{"input":1,"output":2},"limit":{"context":1000,"input":800,"output":200}}}}}';
	}

	static function catalogCount(catalog:ModelsDevCatalog):Int {
		var count = 0;
		for (_ in catalog.keys())
			count++;
		return count;
	}

	static function parseRecord(text:String, label:String):UnknownRecord {
		return requiredRecord(Unknown.fromBoundary(Json.parse(text)), label);
	}

	static function requiredRecord(raw:Unknown, label:String):UnknownRecord {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			throw '${label}: expected object';
		return record;
	}

	static function requiredArray(raw:Unknown, label:String):UnknownArray {
		final array = UnknownNarrow.array(raw);
		if (array == null)
			throw '${label}: expected array';
		return array;
	}

	static function requiredString(raw:Unknown, label:String):String {
		final text = UnknownNarrow.string(raw);
		if (text == null)
			throw '${label}: expected string';
		return text;
	}

	static function requiredRecordField(record:UnknownRecord, field:String, label:String):UnknownRecord {
		return requiredRecord(record.get(field), '${label}.${field}');
	}

	static function requiredArrayField(record:UnknownRecord, field:String, label:String):UnknownArray {
		return requiredArray(record.get(field), '${label}.${field}');
	}

	static function recordAt(array:UnknownArray, index:Int, label:String):UnknownRecord {
		return requiredRecord(array.get(index), '${label}[${index}]');
	}

	static function jsonString(raw:Unknown, label:String):String {
		final json = JsonCodec.narrow(raw);
		if (json == null)
			throw '${label}: expected JSON value';
		return JsonCodec.stringify(json);
	}

	static function stringMapHas(map:Null<ProviderHeaders>, field:String):Bool {
		return map != null && map.exists(field);
	}

	static function stringMapValue(map:Null<ProviderHeaders>, field:String):Null<String> {
		return map == null ? null : map.get(field);
	}

	static function requiredStringMapValue(map:Null<ProviderHeaders>, field:String, label:String):String {
		final value = stringMapValue(map, field);
		if (value == null)
			throw '${label}: expected string field ${field}';
		return value;
	}

	static function requiredOptionString(options:ProviderOptions, field:String, label:String):String {
		final value = ProviderOptionAccess.string(options, field, null);
		if (value == null)
			throw '${label}: expected string field ${field}';
		return value;
	}

	static function requiredOptionNumber(options:ProviderOptions, field:String, label:String):Float {
		final value = ProviderOptionAccess.numberValue(options, field, null);
		if (value == null)
			throw '${label}: expected number field ${field}';
		return value;
	}

	static function requiredOptionRecord(options:ProviderOptions, field:String, label:String):UnknownRecord {
		final value = UnknownNarrow.record(Unknown.fromBoundary(options.get(field)));
		if (value == null)
			throw '${label}: expected record field ${field}';
		return value;
	}

	static function optionHasKnownField(options:ProviderOptions, field:String):Bool {
		final record = UnknownNarrow.record(Unknown.fromBoundary(options));
		return record != null && record.hasOwn(field);
	}

	static function config(data:Dynamic):ConfigInfo {
		final info = ConfigInfo.empty("fixture-user");
		info.disabledProviders = strings(Reflect.field(data, "disabled_providers"));
		info.enabledProviders = strings(Reflect.field(data, "enabled_providers"));
		info.model = stringField(data, "model");
		info.smallModel = stringField(data, "small_model");
		// Fixture boundary: test object literals mirror JSON config and are narrowed by the app types.
		info.provider = cast Reflect.field(data, "provider");
		return info;
	}

	static function strings(value:Dynamic):Null<Array<String>> {
		if (!Std.isOfType(value, Array))
			return null;
		final result:Array<String> = [];
		final arr:Array<Dynamic> = cast value;
		for (item in arr)
			result.push(Std.string(item));
		return result;
	}

	static function stringField(data:Dynamic, field:String):Null<String> {
		final value = Reflect.field(data, field);
		return Std.isOfType(value, String) ? Std.string(value) : null;
	}

	static function modelCount(registry:ProviderRegistry, providerID:String):Int {
		var count = 0;
		for (_ in registry.getProvider(ProviderID.make(providerID)).models.keys())
			count++;
		return count;
	}

	static function paidModelCount(registry:ProviderRegistry):Int {
		var count = 0;
		final provider = registry.getProvider(ProviderIDs.known("opencode"));
		for (model in provider.models) {
			if (model.cost.input > 0)
				count++;
		}
		return count;
	}

	static function variantRegistry(variants:ProviderOptions):ProviderModel {
		return registry(config({
			provider: {
				anthropic: {
					models: {
						"claude-sonnet-4-20250514": {
							variants: variants,
						},
					},
				},
			},
		}),
			{ANTHROPIC_API_KEY: "test-api-key"}).getModel(ProviderIDs.known("anthropic"), ModelID.make("claude-sonnet-4-20250514"));
	}

	static function variantCount(model:ProviderModel):Int {
		var count = 0;
		for (_ in model.variants.keys())
			count++;
		return count;
	}

	static function expectProviderFailure(run:() -> Void, label:String, matches:ProviderFailure->Bool):Void {
		try {
			run();
		} catch (error:ProviderException) {
			if (matches(error.failure))
				return;
			throw '${label}: unexpected failure ${error.message}';
		}
		throw '${label}: expected failure';
	}

	static function requireModel(model:Null<ProviderModel>, label:String):ProviderModel {
		if (model == null)
			throw '${label}: expected model';
		return model;
	}

	static function requireProvider(provider:Null<ProviderInfo>, label:String):ProviderInfo {
		if (provider == null)
			throw '${label}: expected provider';
		return provider;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
