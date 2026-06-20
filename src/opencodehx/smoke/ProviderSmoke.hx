package opencodehx.smoke;

import genes.js.Async.await;
import genes.ts.Unknown;
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
import opencodehx.host.node.NodePath;
import opencodehx.provider.ProviderError.ProviderException;
import opencodehx.provider.ProviderError.ProviderFailure;
import opencodehx.provider.AiSdkLanguageLoader;
import opencodehx.provider.BedrockLanguageLoader;
import opencodehx.provider.ProviderModelsDev;
import opencodehx.provider.ProviderModelsDev.ModelsDevFetchFunction;
import opencodehx.provider.ProviderModelsDev.ModelsDevFetchRequest;
import opencodehx.provider.ProviderModelsDev.ModelsDevOptions;
import opencodehx.provider.ProviderRegistry;
import opencodehx.provider.ProviderTypes.ModelsDevCatalog;
import opencodehx.provider.ProviderTypes.ModelsDevModel;
import opencodehx.provider.ProviderTypes.ModelsDevProvider;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
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
		registryAuthAndBedrock();
		cloudflareAiGatewayLoading();
		opencodePaidModelLoading();
		modelsDevNormalization();
		final transcript = TranscriptHarness.oneTurn();
		eq(transcript.provider.id, "openai", "provider id");
		eq(transcript.provider.modelID, "gpt-5.2", "model id");
		eq(transcript.events.length, 3, "event count");
		eq(Reflect.field(transcript.events[1], "text"), "Hello from the fake provider.", "delta text");
		eq(transcript.messages.length, 2, "message count");

		final encoded = TranscriptHarness.oneTurnJson();
		final parsed:Dynamic = Json.parse(encoded);
		final first = Reflect.field(cast parsed.messages[0], "info");
		eq(Reflect.field(first, "role"), "user", "encoded user role");
		MessageCodec.decodeWithParts(parsed.messages[1], "provider-smoke-assistant");
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
		final anthropic = envRegistry.getProvider(ProviderID.make("anthropic"));
		eq(anthropic.source, "env", "anthropic env source");
		eq(Reflect.hasField(Reflect.field(anthropic.options, "headers"), "anthropic-beta"), true, "anthropic custom headers");

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
		final provider = configured.getProvider(ProviderID.make("anthropic"));
		eq(provider.source, "config", "anthropic config source");
		eq(Reflect.field(provider.options, "apiKey"), "config-api-key", "config api key");
		eq(Reflect.field(provider.options, "timeout"), 60000, "config timeout");
	}

	static function registryFilters():Void {
		final disabled = registry(config({disabled_providers: ["anthropic"]}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(disabled.getProvider(ProviderID.make("anthropic")) == null, true, "disabled provider");

		final enabled = registry(config({enabled_providers: ["anthropic"]}), {ANTHROPIC_API_KEY: "test-api-key", OPENAI_API_KEY: "openai-key"});
		eq(enabled.getProvider(ProviderID.make("anthropic")) != null, true, "enabled provider present");
		eq(enabled.getProvider(ProviderID.make("openai")) == null, true, "enabled provider excludes openai");

		final whitelist = registry(config({
			provider: {
				anthropic: {
					whitelist: ["claude-sonnet-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(whitelist.getProvider(ProviderID.make("anthropic")).models.exists("claude-sonnet-4-20250514"), true, "whitelist keeps model");
		eq(modelCount(whitelist, "anthropic"), 1, "whitelist count");

		final blacklist = registry(config({
			provider: {
				anthropic: {
					blacklist: ["claude-sonnet-4-20250514"],
				},
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(blacklist.getProvider(ProviderID.make("anthropic")).models.exists("claude-sonnet-4-20250514"), false, "blacklist removes model");
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
		eq(filters.getProvider(ProviderID.make("anthropic")) != null, true, "plugin enabled provider kept");
		eq(filters.getProvider(ProviderID.make("openai")) == null, true, "plugin disabled provider removed");
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
					},
					options: {apiKey: "custom-key"},
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
			},
		}), {ANTHROPIC_API_KEY: "test-api-key"});
		eq(custom.getProvider(ProviderID.make("custom-provider")).name, "Custom Provider", "custom provider name");
		eq(custom.getModel(ProviderID.make("custom-provider"), ModelID.make("custom-model")).name, "Custom Model", "custom model name");
		eq(custom.getModel(ProviderID.make("anthropic"), ModelID.make("my-alias")).name, "My Custom Alias", "alias model name");
		eq(Reflect.field(custom.getModel(ProviderID.make("anthropic"), ModelID.make("claude-sonnet-4-20250514")).options, "customOption"), "custom-value",
			"model option merge");

		final parsed = ProviderRegistry.parseModel("openrouter/anthropic/claude-3-opus");
		eq(parsed.providerID.toString(), "openrouter", "parse provider");
		eq(parsed.modelID.toString(), "anthropic/claude-3-opus", "parse slash model");

		final configuredDefault = registry(config({model: "anthropic/claude-sonnet-4-20250514"}), {ANTHROPIC_API_KEY: "test-api-key"}).defaultModel();
		eq(configuredDefault.providerID.toString(), "anthropic", "default model provider");
		eq(configuredDefault.modelID.toString(), "claude-sonnet-4-20250514", "default model id");

		final small = custom.smallModel(ProviderID.make("anthropic"));
		if (small == null)
			throw "small model: expected model";
		eq(small.id.toString(), "claude-haiku-4-5", "small model priority");

		expectProviderFailure(() -> custom.getModel(ProviderID.make("anthropic"), ModelID.make("missing-model")), "missing model", function(failure) {
			return switch failure {
				case ModelNotFound(providerID, modelID, _): providerID.toString() == "anthropic" && modelID.toString() == "missing-model";
				case _: false;
			}
		});
		expectProviderFailure(() -> custom.getModel(ProviderID.make("anthropic"), ModelID.make("claude-sonet-4")), "model typo suggestions",
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
		final openai = authRegistry.getProvider(ProviderID.make("openai"));
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
		final bedrock = bedrockConfig.getProvider(ProviderID.make("amazon-bedrock"));
		eq(Reflect.field(bedrock.options, "region"), "eu-west-1", "bedrock config region");
		eq(Reflect.field(bedrock.options, "profile"), "config-profile", "bedrock config profile");
		eq(Reflect.field(bedrock.options, "baseURL"), "https://bedrock-runtime.example.com", "bedrock endpoint baseURL");

		final bedrockEnv = registry(config({}), {AWS_REGION: "eu-west-1", AWS_PROFILE: "default"});
		eq(Reflect.field(bedrockEnv.getProvider(ProviderID.make("amazon-bedrock")).options, "region"), "eu-west-1", "bedrock env region");

		final bedrockAuth = registry(config({
			provider: {
				"amazon-bedrock": {options: {region: "us-east-1"}},
			},
		}), {}, {"amazon-bedrock": {type: "api", key: "bearer"}});
		final authBedrock = bedrockAuth.getProvider(ProviderID.make("amazon-bedrock"));
		eq(authBedrock != null, true, "bedrock auth bearer");
		eq(Reflect.field(authBedrock.options, "apiKey"), "bearer", "bedrock bearer apiKey");

		final webIdentity = registry(config({
			provider: {
				"amazon-bedrock": {options: {region: "us-east-1"}},
			},
		}),
			{AWS_WEB_IDENTITY_TOKEN_FILE: "/var/run/secrets/eks.amazonaws.com/serviceaccount/token", AWS_PROFILE: "", AWS_ACCESS_KEY_ID: ""});
		eq(webIdentity.getProvider(ProviderID.make("amazon-bedrock")) != null, true, "bedrock web identity autoload");

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
		final providerID = ProviderID.make("amazon-bedrock");
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
		eq(partial.getProvider(ProviderID.make("cloudflare-ai-gateway")) == null, true, "cloudflare gateway requires token");

		final loaded = registry(config({}), {
			CLOUDFLARE_ACCOUNT_ID: "test-account",
			CLOUDFLARE_GATEWAY_ID: "test-gateway",
			CLOUDFLARE_API_TOKEN: "test-token",
		});
		final provider = loaded.getProvider(ProviderID.make("cloudflare-ai-gateway"));
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
		final metadata = Reflect.field(configured.getProvider(ProviderID.make("cloudflare-ai-gateway")).options, "metadata");
		eq(Reflect.field(metadata, "invoked_by"), "test", "cloudflare metadata invoked_by");
		eq(Reflect.field(metadata, "project"), "opencode", "cloudflare metadata project");
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
			id: ProviderID.make("amazon-bedrock"),
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
			providerID: ProviderID.make("amazon-bedrock"),
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
		final provider = registry.getProvider(ProviderID.make("opencode"));
		for (model in provider.models) {
			if (model.cost.input > 0)
				count++;
		}
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

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected) {
			throw '$label: expected ${expected}, got ${actual}';
		}
	}
}
