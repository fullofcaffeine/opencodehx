package opencodehx.smoke;

import genes.ts.Unknown;
import haxe.Json;
import js.lib.Promise;
import opencodehx.cli.PluginAuthPicker.PluginProviderChoice;
import opencodehx.cli.PluginAuthPicker.PluginProviderHook;
import opencodehx.cli.PluginAuthPicker.resolvePluginProviders;
import opencodehx.config.ConfigPlugin;
import opencodehx.config.ConfigPlugin.PluginOrigin;
import opencodehx.config.ConfigPlugin.PluginScope;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeBuffer;
import opencodehx.plugin.PluginAuthHooks;
import opencodehx.plugin.PluginAuthHooks.PluginAuthHook;
import opencodehx.plugin.PluginAuthHooks.PluginAuthMethodType;
import opencodehx.plugin.PluginCloudflare;
import opencodehx.plugin.PluginCloudflare.CloudflareChatParamsInput;
import opencodehx.plugin.PluginCloudflare.CloudflareChatParamsOutput;
import opencodehx.plugin.PluginCodex;
import opencodehx.plugin.PluginGithubCopilotModels;
import opencodehx.plugin.PluginGithubCopilotModels.CopilotRemoteModel;
import opencodehx.plugin.PluginMeta;
import opencodehx.plugin.PluginRuntime;
import opencodehx.plugin.PluginRuntime.PluginLegacyExport;
import opencodehx.plugin.PluginRuntime.PluginModule;
import opencodehx.plugin.PluginRuntime.PluginV1Export;
import opencodehx.plugin.PluginServerHooks;
import opencodehx.plugin.PluginShared;
import opencodehx.plugin.PluginShared.PluginSource;
import opencodehx.provider.ProviderOpenRecords;
import opencodehx.provider.ProviderTypes.ModelID;
import opencodehx.provider.ProviderTypes.ProviderID;
import opencodehx.provider.ProviderTypes.ProviderIDs;
import opencodehx.provider.ProviderTypes.ProviderModel;
import opencodehx.smoke.SmokeCleanup.withCleanup;

class PluginSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-plugin-"));
		withCleanup(() -> {
			codexJwtClaims();
			authOverride();
			pluginAuthPicker();
			cloudflareChatParams();
			githubCopilotModels();
			parseSpecifiers();
			metadata(root);
			runtime(root);
		}, () -> Fs.rmSync(root, {recursive: true, force: true}));
	}

	public static function runAsync():Promise<Void> {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-plugin-async-"));
		return runtimeAsync(root).then(_ -> {
			Fs.rmSync(root, {recursive: true, force: true});
			return null;
		}).catchError(error -> {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		});
	}

	static function codexJwtClaims():Void {
		final rootClaims = PluginCodex.parseJwtClaims(jwt({email: "test@example.com", chatgpt_account_id: "acc-123"}));
		eq(rootClaims != null, true, "codex jwt claims parse");
		eq(PluginCodex.extractAccountIdFromClaims(rootClaims), "acc-123", "codex root account id");
		eq(PluginCodex.parseJwtClaims("invalid") == null, true, "codex jwt rejects one part");
		eq(PluginCodex.parseJwtClaims("only.two") == null, true, "codex jwt rejects two parts");
		eq(PluginCodex.parseJwtClaims("a.!!!invalid!!!.b") == null, true, "codex jwt rejects invalid base64");
		eq(PluginCodex.parseJwtClaims(jwtRaw("not json")) == null, true, "codex jwt rejects invalid json");

		final nested = Unknown.fromBoundary({"https://api.openai.com/auth": {chatgpt_account_id: "acc-nested"}});
		eq(PluginCodex.extractAccountIdFromClaims(nested), "acc-nested", "codex nested account id");
		final rootPreferred = Unknown.fromBoundary({
			chatgpt_account_id: "acc-root",
			"https://api.openai.com/auth": {chatgpt_account_id: "acc-nested"},
		});
		eq(PluginCodex.extractAccountIdFromClaims(rootPreferred), "acc-root", "codex prefers root account id");
		final organization = Unknown.fromBoundary({organizations: [{id: "org-123"}, {id: "org-456"}]});
		eq(PluginCodex.extractAccountIdFromClaims(organization), "org-123", "codex organization fallback");
		eq(PluginCodex.extractAccountIdFromClaims(Unknown.fromBoundary({email: "test@example.com"})) == null, true, "codex missing account id");

		final idToken = jwt({chatgpt_account_id: "from-id-token"});
		final accessToken = jwt({chatgpt_account_id: "from-access-token"});
		eq(PluginCodex.extractAccountId({id_token: idToken, access_token: accessToken, refresh_token: "rt"}), "from-id-token", "codex id token first");
		final accessFallback = jwt({"https://api.openai.com/auth": {chatgpt_account_id: "from-access"}});
		eq(PluginCodex.extractAccountId({id_token: jwt({email: "test@example.com"}), access_token: accessFallback, refresh_token: "rt"}), "from-access",
			"codex access token fallback");
		final noAccount = jwt({email: "test@example.com"});
		eq(PluginCodex.extractAccountId({id_token: noAccount, access_token: noAccount, refresh_token: "rt"}) == null, true, "codex no token account id");
		eq(PluginCodex.extractAccountId({id_token: "", access_token: accessToken, refresh_token: "rt"}), "from-access-token", "codex missing id token");
	}

	static function authOverride():Void {
		final builtIns:Array<PluginAuthHook> = [
			authHook(ProviderIDs.known("github-copilot"), "GitHub Copilot"),
			authHook(ProviderIDs.known("openai"), "OpenAI"),
		];
		final user:Array<PluginAuthHook> = [authHook(ProviderIDs.known("github-copilot"), "Test Override Auth"),];
		final combined = PluginAuthHooks.concat(builtIns, user);

		eq(PluginAuthHooks.methodsFor(ProviderIDs.known("github-copilot"), combined).length, 1, "auth override method count");
		eq(PluginAuthHooks.methodsFor(ProviderIDs.known("github-copilot"), combined)[0].label, "Test Override Auth", "auth override label");
		eq(PluginAuthHooks.methodsFor(ProviderIDs.known("github-copilot"), builtIns)[0].label, "GitHub Copilot", "plain built-in auth label");
		eq(PluginAuthHooks.methodsFor(ProviderIDs.known("openai"), combined)[0].label, "OpenAI", "unrelated auth provider unchanged");
	}

	static function pluginAuthPicker():Void {
		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [],
			enabled: null,
			providerNames: [],
		}), [{id: ProviderID.make("portkey"), name: "portkey"}],
			"plugin auth picker includes plugin provider");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderIDs.known("anthropic"))],
			existingProviders: [ProviderIDs.known("anthropic")],
			disabled: [],
			enabled: null,
			providerNames: [],
		}), [], "plugin auth picker skips models.dev provider");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey")), pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [],
			enabled: null,
			providerNames: [],
		}), [{id: ProviderID.make("portkey"), name: "portkey"}],
			"plugin auth picker dedupes plugins");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [ProviderID.make("portkey")],
			enabled: null,
			providerNames: [],
		}), [], "plugin auth picker respects disabled providers");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [],
			enabled: [ProviderIDs.known("anthropic")],
			providerNames: [],
		}), [], "plugin auth picker respects enabled provider absence");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [],
			enabled: [ProviderID.make("portkey")],
			providerNames: [],
		}), [{id: ProviderID.make("portkey"), name: "portkey"}],
			"plugin auth picker includes enabled provider");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [],
			enabled: null,
			providerNames: [{id: ProviderID.make("portkey"), name: "Portkey AI"}],
		}), [{id: ProviderID.make("portkey"), name: "Portkey AI"}],
			"plugin auth picker configured name");

		assertChoices(resolvePluginProviders({
			hooks: [pickerHook(ProviderID.make("portkey"))],
			existingProviders: [],
			disabled: [],
			enabled: null,
			providerNames: [],
		}), [{id: ProviderID.make("portkey"), name: "portkey"}],
			"plugin auth picker falls back to id");

		assertChoices(resolvePluginProviders({
			hooks: [
				pickerHookWithoutAuth(),
				pickerHook(ProviderID.make("portkey")),
				pickerHookWithoutAuth()
			],
			existingProviders: [],
			disabled: [],
			enabled: null,
			providerNames: [],
		}), [{id: ProviderID.make("portkey"), name: "portkey"}],
			"plugin auth picker skips hooks without auth");

		assertChoices(resolvePluginProviders({
			hooks: [],
			existingProviders: [],
			disabled: [],
			enabled: null,
			providerNames: [],
		}), [], "plugin auth picker handles no hooks");
	}

	static function authHook(provider:ProviderID, label:String):PluginAuthHook {
		return {
			provider: provider,
			methods: [
				{
					type: PluginAuthMethodType.Api,
					label: label,
				}
			],
		};
	}

	static function pickerHook(provider:ProviderID):PluginProviderHook {
		return {auth: authHook(provider, provider.toString())};
	}

	static function pickerHookWithoutAuth():PluginProviderHook {
		return {auth: null};
	}

	static function assertChoices(actual:Array<PluginProviderChoice>, expected:Array<PluginProviderChoice>, label:String):Void {
		eq(actual.length, expected.length, '${label} count');
		for (i in 0...expected.length) {
			eq(actual[i].id, expected[i].id, '${label} id ${i}');
			eq(actual[i].name, expected[i].name, '${label} name ${i}');
		}
	}

	static function cloudflareChatParams():Void {
		final omitted = cloudflareOutput();
		PluginCloudflare.applyChatParams(cloudflareInput("cloudflare-ai-gateway", "openai/gpt-5.2-codex", true), omitted);
		eq(omitted.maxOutputTokens.orNull() == null, true, "cloudflare omits openai reasoning max output");

		final nonReasoning = cloudflareOutput();
		PluginCloudflare.applyChatParams(cloudflareInput("cloudflare-ai-gateway", "openai/gpt-4-turbo", false), nonReasoning);
		eq(nonReasoning.maxOutputTokens.orNull(), 32000.0, "cloudflare keeps openai non-reasoning max output");

		final nonOpenAI = cloudflareOutput();
		PluginCloudflare.applyChatParams(cloudflareInput("cloudflare-ai-gateway", "anthropic/claude-sonnet-4-5", true), nonOpenAI);
		eq(nonOpenAI.maxOutputTokens.orNull(), 32000.0, "cloudflare keeps non-openai reasoning max output");

		final otherProvider = cloudflareOutput();
		PluginCloudflare.applyChatParams(cloudflareInput("openai", "gpt-5.2-codex", true), otherProvider);
		eq(otherProvider.maxOutputTokens.orNull(), 32000.0, "cloudflare ignores non-cloudflare provider");
	}

	static function cloudflareInput(providerID:String, apiID:String, reasoning:Bool):CloudflareChatParamsInput {
		return {
			model: {
				providerID: providerID,
				api: {id: apiID},
				capabilities: {reasoning: reasoning},
			},
		};
	}

	static function cloudflareOutput():CloudflareChatParamsOutput {
		return {maxOutputTokens: 32000.0};
	}

	static function githubCopilotModels():Void {
		final existing = new Map<String, ProviderModel>();
		existing.set("gpt-4o", copilotModel("gpt-4o", "gpt-4o", "https://api.githubcopilot.com", "@ai-sdk/openai-compatible", true));
		final merged = PluginGithubCopilotModels.merge("https://api.githubcopilot.com", [
			copilotRemote("gpt-4o", "GPT-4o", "gpt", 64000, 16384, true),
			copilotRemote("brand-new", "Brand New", "test", 32000, 8192, false),
		], existing);
		eq(merged.get("gpt-4o").capabilities.temperature, true, "copilot preserves existing temperature support");
		eq(merged.get("brand-new").capabilities.temperature, true, "copilot defaults new model temperature support");

		final fallbackInput = new Map<String, ProviderModel>();
		fallbackInput.set("claude", copilotModel("claude", "claude-sonnet-4.5", "https://api.githubcopilot.com/v1", "@ai-sdk/anthropic", true));
		final fallback = PluginGithubCopilotModels.fallbackModels(fallbackInput, "ghe.example.com");
		eq(fallback.get("claude").api.url, "https://copilot-api.ghe.example.com", "copilot enterprise fallback url");
		eq(fallback.get("claude").api.npm, "@ai-sdk/github-copilot", "copilot enterprise fallback sdk");
	}

	static function copilotRemote(id:String, name:String, family:String, context:Float, output:Float, toolCalls:Bool):CopilotRemoteModel {
		return {
			modelPickerEnabled: true,
			id: id,
			name: name,
			version: id + "-2026-04-01",
			family: family,
			maxContextWindowTokens: context,
			maxOutputTokens: output,
			maxPromptTokens: context,
			streaming: true,
			toolCalls: toolCalls,
		};
	}

	static function copilotModel(key:String, apiID:String, apiURL:String, apiNpm:String, temperature:Bool):ProviderModel {
		return {
			id: ModelID.make(key),
			providerID: ProviderID.make("github-copilot"),
			api: {
				id: apiID,
				url: apiURL,
				npm: apiNpm,
			},
			name: key,
			family: "gpt",
			capabilities: {
				temperature: temperature,
				reasoning: false,
				attachment: true,
				toolcall: true,
				input: {
					text: true,
					audio: false,
					image: true,
					video: false,
					pdf: false,
				},
				output: {
					text: true,
					audio: false,
					image: false,
					video: false,
					pdf: false,
				},
				interleaved: false,
			},
			cost: {
				input: 0,
				output: 0,
				cache: {
					read: 0,
					write: 0,
				},
			},
			limit: {
				context: 64000,
				output: 16384,
			},
			options: ProviderOpenRecords.options(),
			headers: ProviderOpenRecords.headers(),
			release_date: "2024-05-13",
			variants: ProviderOpenRecords.variants(),
			status: "active",
		};
	}

	static function jwt(payload:Dynamic):String {
		return jwtRaw(Json.stringify(payload));
	}

	static function jwtRaw(payload:String):String {
		return NodeBuffer.toBase64Url(Json.stringify({alg: "none"})) + "." + NodeBuffer.toBase64Url(payload) + ".sig";
	}

	static function parseSpecifiers():Void {
		parsed("acme", "acme", "latest");
		parsed("acme@1.0.0", "acme", "1.0.0");
		parsed("@opencode/acme", "@opencode/acme", "latest");
		parsed("@opencode/acme@1.0.0", "@opencode/acme", "1.0.0");
		parsed("acme@git+https://github.com/opencode/acme.git", "acme", "git+https://github.com/opencode/acme.git");
		parsed("@opencode/acme@git+ssh://git@github.com/opencode/acme.git", "@opencode/acme", "git+ssh://git@github.com/opencode/acme.git");
		parsed("git+ssh://git@github.com/opencode/acme.git", "git+ssh://git@github.com/opencode/acme.git", "");
		parsed("acme@npm:@opencode/acme@1.0.0", "acme", "npm:@opencode/acme@1.0.0");
		parsed("npm:@opencode/acme@1.0.0", "@opencode/acme", "1.0.0");
		parsed("npm:@opencode/acme", "@opencode/acme", "latest");
	}

	static function metadata(root:String):Void {
		final file = NodePath.join(root, "plugin.ts");
		write(file, "export default async () => ({})\n");
		final state = NodePath.join(root, "state/plugin-meta.json");
		var clock = 1000.0;
		final meta = new PluginMeta(state, () -> {
			clock += 1;
			return clock;
		});
		final spec = Url.pathToFileURL(file).href;
		final one = meta.touch(spec, spec, "demo.file");
		eq(one.state, "first", "plugin meta first file");
		eq(one.entry.source, PluginSource.File, "plugin meta file source");
		final two = meta.touch(spec, spec, "demo.file");
		eq(two.state, "same", "plugin meta same file");
		eq(two.entry.load_count, 2, "plugin meta load count");
		write(file, "export default async () => ({ ok: true })\n");
		final three = meta.touch(spec, spec, "demo.file");
		eq(three.state, "updated", "plugin meta updated file");

		final mod = NodePath.join(root, "node_modules/acme-plugin");
		Fs.mkdirSync(mod, {recursive: true});
		write(NodePath.join(mod, "package.json"), '{"name":"acme-plugin","version":"1.0.0"}');
		final npmOne = meta.touch("acme-plugin@latest", mod, "acme-plugin");
		eq(npmOne.entry.requested, "latest", "plugin meta npm requested");
		eq(npmOne.entry.version, "1.0.0", "plugin meta npm version");
		write(NodePath.join(mod, "package.json"), '{"name":"acme-plugin","version":"1.1.0"}');
		final npmTwo = meta.touch("acme-plugin@latest", mod, "acme-plugin");
		eq(npmTwo.state, "updated", "plugin meta npm updated");
		eq(meta.list().get("acme-plugin").version, "1.1.0", "plugin meta persisted npm version");
	}

	static function runtime(root:String):Void {
		final file = NodePath.join(root, "plugin.ts");
		write(file, "export default async () => ({})\n");
		final fileSpec = Url.pathToFileURL(file).href;
		final pkgDir = NodePath.join(root, "node_modules/acme-plugin");
		Fs.mkdirSync(pkgDir, {recursive: true});
		write(NodePath.join(pkgDir, "package.json"), '{"name":"acme-plugin","version":"1.0.0","main":"./index.js"}');
		final origins = [
			origin(fileSpec),
			origin("acme-plugin"),
			origin("missing-plugin"),
			origin("bad-file"),
			origin("mixed-file"),
			origin("dedupe-file")
		];
		final modules:Array<SmokePluginModule> = [];
		modules.push({spec: fileSpec, module: {defaultV1: v1("demo.file", "file-default"), legacy: [legacy("ignored", "ignored")]}});
		modules.push({spec: "acme-plugin", module: {legacy: [legacy("pkg-one", "pkg-one")]}});
		modules.push({spec: "bad-file", module: {defaultV1: v1(null, "bad"), legacy: []}});
		modules.push({spec: "mixed-file", module: {defaultV1: {id: "mixed", server: spec -> hook("mixed"), tui: true}, legacy: []}});
		final same = legacy("same", "dedupe");
		modules.push({spec: "dedupe-file", module: {legacy: [same, same]}});
		final runtime = new PluginRuntime(origins, spec -> {
			final raw = ConfigPlugin.specifier(spec);
			final target = raw == "acme-plugin" ? pkgDir : raw;
			return PluginShared.createPluginEntry(raw, target);
		}, entry -> moduleFor(modules, entry.spec));
		eq(runtime.list().length, 3, "plugin runtime loaded hooks");
		final out = runtime.trigger("experimental.chat.system.transform", Unknown.fromBoundary({}), {system: []});
		eq(out.system.join(","), "file-default,pkg-one,dedupe", "plugin trigger hook order");
	}

	static function runtimeAsync(root:String):Promise<Void> {
		final file = NodePath.join(root, "plugin-async.ts");
		write(file, "export default async () => ({})\n");
		final fileSpec = Url.pathToFileURL(file).href;
		final origins = [origin(fileSpec), origin("async-plugin"), origin("last-plugin")];
		final modules:Array<SmokePluginModule> = [
			{spec: fileSpec, module: {defaultV1: v1("sync.file", "sync"), legacy: []}},
			{spec: "async-plugin", module: {legacy: [legacyAsync("async-plugin", "async")]}},
			{spec: "last-plugin", module: {legacy: [legacy("last-plugin", "last")]}},
		];
		final runtime = new PluginRuntime(origins, spec -> {
			final raw = ConfigPlugin.specifier(spec);
			return PluginShared.createPluginEntry(raw, raw);
		}, entry -> moduleFor(modules, entry.spec));
		return runtime.triggerAsync("experimental.chat.system.transform", Unknown.fromBoundary({}), {system: []}).then(out -> {
			eq(out.system.join(","), "sync,async,last", "plugin async trigger hook order");
			return null;
		});
	}

	static function parsed(spec:String, pkg:String, version:String):Void {
		final out = PluginShared.parsePluginSpecifier(spec);
		eq(out.pkg, pkg, 'plugin parse pkg ${spec}');
		eq(out.version, version, 'plugin parse version ${spec}');
	}

	static function origin(spec:String):PluginOrigin {
		return ConfigPlugin.withOrigin({specifier: spec}, "smoke", PluginScope.PluginScopeLocal);
	}

	static function v1(id:Null<String>, label:String):PluginV1Export {
		return {id: id, server: _ -> hook(label)};
	}

	static function legacy(identity:String, label:String):PluginLegacyExport {
		return {identity: identity, server: _ -> hook(label)};
	}

	static function legacyAsync(identity:String, label:String):PluginLegacyExport {
		return {identity: identity, server: _ -> asyncHook(label)};
	}

	static function hook(label:String):PluginServerHooks {
		return {
			systemTransform: (_input, output) -> output.system.push(label),
		};
	}

	static function asyncHook(label:String):PluginServerHooks {
		return {
			systemTransformAsync: (_input, output) -> Promise.resolve(true).then(_ -> {
				output.system.push(label);
				return null;
			}),
		};
	}

	static function moduleFor(modules:Array<SmokePluginModule>, spec:String):Null<PluginModule> {
		for (item in modules) {
			if (item.spec == spec)
				return item.module;
		}
		return null;
	}

	static function write(path:String, content:String):Void {
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content, {encoding: "utf8"});
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}

typedef SmokePluginModule = {
	final spec:String;
	final module:PluginModule;
}
