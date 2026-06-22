package opencodehx.provider;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.AbortSignal;
import js.lib.Date;
import js.lib.Promise;
import opencodehx.BuildInfo;
import opencodehx.externs.node.Crypto;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;
import opencodehx.provider.ProviderTypes.ModelsDevCatalog;
import opencodehx.provider.ProviderTypes.ModelsDevCost;
import opencodehx.provider.ProviderTypes.ModelsDevExperimental;
import opencodehx.provider.ProviderTypes.ModelsDevLimit;
import opencodehx.provider.ProviderTypes.ModelsDevMode;
import opencodehx.provider.ProviderTypes.ModelsDevModeProvider;
import opencodehx.provider.ProviderTypes.ModelsDevModalities;
import opencodehx.provider.ProviderTypes.ModelsDevModel;
import opencodehx.provider.ProviderTypes.ModelsDevOver200KCost;
import opencodehx.provider.ProviderTypes.ModelsDevProvider;
import opencodehx.provider.ProviderTypes.ModelsDevProviderApi;
import opencodehx.provider.ProviderTypes.ProviderInterleaved;
import opencodehx.provider.ProviderTypes.ProviderInterleavedConfig;
import opencodehx.provider.ProviderTypes.ProviderInterleavedField;

using StringTools;

typedef ModelsDevFetchRequest = {
	final url:String;
	final headers:DynamicAccess<String>;
	final timeoutMs:Int;
}

typedef ModelsDevFetchResult = {
	final ok:Bool;
	final status:Int;
	final text:String;
}

typedef ModelsDevFetchFunction = ModelsDevFetchRequest->Promise<ModelsDevFetchResult>;

typedef ModelsDevOptions = {
	@:optional final cacheDir:String;
	@:optional final sourceUrl:String;
	@:optional final modelsPath:String;
	@:optional final disableFetch:Bool;
	@:optional final snapshot:ModelsDevCatalog;
	@:optional final fetcher:ModelsDevFetchFunction;
	@:optional final now:Void->Float;
	@:optional final ttlMs:Float;
	@:optional final timeoutMs:Int;
}

typedef ModelsDevRuntimeOptions = {
	final cacheDir:String;
	final sourceUrl:String;
	@:optional final modelsPath:String;
	final disableFetch:Bool;
	@:optional final snapshot:ModelsDevCatalog;
	final fetcher:ModelsDevFetchFunction;
	final now:Void->Float;
	final ttlMs:Float;
	final timeoutMs:Int;
}

typedef Decoded<T> = {
	final ok:Bool;
	final value:Null<T>;
}

extern typedef ModelsDevHttpInit = {
	final headers:DynamicAccess<String>;
	@:optional final signal:AbortSignal;
}

extern typedef ModelsDevHttpResponse = {
	final ok:Bool;
	final status:Int;
	function text():Promise<String>;
}

@:native("globalThis")
extern class ModelsDevGlobalThis {
	static function fetch(url:String, init:ModelsDevHttpInit):Promise<ModelsDevHttpResponse>;
}

@:native("AbortSignal")
extern class ModelsDevAbortSignal {
	static function timeout(ms:Int):AbortSignal;
}

class ProviderModelsDev {
	static inline final DEFAULT_SOURCE = "https://models.dev";
	static inline final TTL_MS = 5 * 60 * 1000;
	static inline final TIMEOUT_MS = 10000;

	@:async
	public static function get(?options:ModelsDevOptions):Promise<ModelsDevCatalog> {
		final opts = runtimeOptions(options);
		final local = readLocal(opts);
		if (local != null)
			return local;
		if (opts.snapshot != null)
			return opts.snapshot;
		if (opts.disableFetch)
			return emptyCatalog();
		final fetched = @:await fetchCatalog(opts);
		return fetched == null ? emptyCatalog() : fetched;
	}

	@:async
	public static function refresh(?force:Bool = false, ?options:ModelsDevOptions):Promise<Bool> {
		final opts = runtimeOptions(options);
		if (opts.disableFetch || (!force && fresh(opts)))
			return false;
		try {
			final fetched = @:await fetchCatalog(opts);
			return fetched != null;
		} catch (_:Dynamic) {
			// Refresh is background cache maintenance. Network, JSON, and file
			// failures stay contained here so callers can keep using old data.
			return false;
		}
	}

	public static function cacheFile(?options:ModelsDevOptions):String {
		final opts = runtimeOptions(options);
		return cacheFileFor(opts.sourceUrl, opts.cacheDir);
	}

	public static function parse(text:String):ModelsDevCatalog {
		final result = emptyCatalog();
		final parsed = UnknownNarrow.record(Unknown.fromBoundary(Json.parse(text)));
		if (parsed == null)
			return result;
		for (id in parsed.keys()) {
			final provider = decodeProvider(parsed.get(id));
			if (provider == null)
				continue;
			result.set(id, provider);
		}
		return result;
	}

	public static function sourceUrl(?options:ModelsDevOptions):String {
		final configured = options != null && options.sourceUrl != null ? options.sourceUrl : NodeProcess.envValue("OPENCODE_MODELS_URL");
		return configured == null || configured == "" ? DEFAULT_SOURCE : trimRightSlashes(configured);
	}

	public static function cacheFileFor(sourceUrl:String, cacheDir:String):String {
		final file = trimRightSlashes(sourceUrl) == DEFAULT_SOURCE ? "models.json" : 'models-${hashFast(sourceUrl)}.json';
		return NodePath.join(cacheDir, file);
	}

	public static function hashFast(value:String):String {
		return Crypto.createHash("sha1").update(value).digest("hex");
	}

	static function runtimeOptions(?options:ModelsDevOptions):ModelsDevRuntimeOptions {
		final opts:ModelsDevOptions = options == null ? {} : options;
		final configuredPath = opts.modelsPath != null ? opts.modelsPath : NodeProcess.envValue("OPENCODE_MODELS_PATH");
		return {
			cacheDir: opts.cacheDir == null || opts.cacheDir == "" ? defaultCacheDir() : opts.cacheDir,
			sourceUrl: sourceUrl(opts),
			modelsPath: configuredPath,
			disableFetch: opts.disableFetch == true
			|| NodeProcess.envValue("OPENCODE_DISABLE_MODELS_FETCH") == "1"
			|| NodeProcess.envValue("OPENCODE_DISABLE_MODELS_FETCH") == "true",
			snapshot: opts.snapshot,
			fetcher: opts.fetcher == null ? defaultFetch : opts.fetcher,
			now: opts.now == null ? Date.now : opts.now,
			ttlMs: opts.ttlMs == null ? TTL_MS : opts.ttlMs,
			timeoutMs: opts.timeoutMs == null ? TIMEOUT_MS : opts.timeoutMs,
		};
	}

	static function readLocal(opts:ModelsDevRuntimeOptions):Null<ModelsDevCatalog> {
		final path = opts.modelsPath == null ? cacheFileFor(opts.sourceUrl, opts.cacheDir) : opts.modelsPath;
		try {
			if (!Fs.existsSync(path))
				return null;
			return parse(Fs.readFileSync(path, "utf8"));
		} catch (_:Dynamic) {
			// File and JSON failures are local cache/input-boundary failures. Treat
			// them as a cache miss so fetch/snapshot fallback can decide the result.
			return null;
		}
	}

	static function fresh(opts:ModelsDevRuntimeOptions):Bool {
		if (opts.modelsPath != null)
			return true;
		final path = cacheFileFor(opts.sourceUrl, opts.cacheDir);
		try {
			if (!Fs.existsSync(path))
				return false;
			final stat = Fs.statSync(path);
			return opts.now() - (stat.mtimeMs == null ? 0 : stat.mtimeMs) < opts.ttlMs;
		} catch (_:Dynamic) {
			// Cache stat failures are treated like stale/missing cache entries.
			return false;
		}
	}

	@:async
	static function fetchCatalog(opts:ModelsDevRuntimeOptions):Promise<Null<ModelsDevCatalog>> {
		final response = @:await opts.fetcher({
			url: opts.sourceUrl + "/api.json",
			headers: headers(),
			timeoutMs: opts.timeoutMs,
		});
		if (!response.ok)
			return null;
		final catalog = parse(response.text);
		writeCache(opts, response.text);
		return catalog;
	}

	static function writeCache(opts:ModelsDevRuntimeOptions, text:String):Void {
		if (opts.modelsPath != null)
			return;
		try {
			final path = cacheFileFor(opts.sourceUrl, opts.cacheDir);
			Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
			Fs.writeFileSync(path, text, "utf8");
		} catch (_:Dynamic) {
			// Cache writes are best effort, matching upstream's tolerance for a
			// read-only or transiently unavailable cache directory.
		}
	}

	@:async
	static function defaultFetch(request:ModelsDevFetchRequest):Promise<ModelsDevFetchResult> {
		final response = @:await ModelsDevGlobalThis.fetch(request.url, {
			headers: request.headers,
			signal: ModelsDevAbortSignal.timeout(request.timeoutMs),
		});
		final text = @:await response.text();
		return {
			ok: response.ok,
			status: response.status,
			text: text,
		};
	}

	static function headers():DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		out.set("User-Agent", 'opencodehx/${BuildInfo.version}');
		return out;
	}

	static function defaultCacheDir():String {
		final home = NodeProcess.envValue("OPENCODE_TEST_HOME");
		return NodePath.join(NodePath.join(home == null || home == "" ? Os.homedir() : home, ".cache"), "opencode");
	}

	static function emptyCatalog():ModelsDevCatalog {
		return new DynamicAccess<ModelsDevProvider>();
	}

	// Runtime JSON decoder boundary: Json.parse returns untrusted JavaScript.
	// Keep it as Unknown, validate each consumed field, then copy into typed
	// models.dev records so raw parsed objects never enter the registry.
	static function decodeProvider(value:Unknown):Null<ModelsDevProvider> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return null;
		final id = requiredString(record, "id");
		final name = requiredString(record, "name");
		if (id == null || name == null)
			return null;
		final env = optionalStringArray(record, "env");
		final api = optionalString(record, "api");
		final npm = optionalString(record, "npm");
		final modelsRecord = optionalRecord(record, "models");
		if (!env.ok || !api.ok || !npm.ok || !modelsRecord.ok || modelsRecord.value == null)
			return null;
		final models = new DynamicAccess<ModelsDevModel>();
		for (modelID in modelsRecord.value.keys()) {
			final model = decodeModel(modelsRecord.value.get(modelID));
			if (model == null)
				return null;
			models.set(modelID, model);
		}
		return {
			id: id,
			name: name,
			env: env.value,
			api: api.value,
			npm: npm.value,
			models: models,
		};
	}

	static function decodeModel(value:Unknown):Null<ModelsDevModel> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return null;
		final id = requiredString(record, "id");
		final name = requiredString(record, "name");
		final limit = decodeLimit(record.get("limit"));
		if (id == null || name == null || limit == null)
			return null;
		final family = optionalString(record, "family");
		final releaseDate = optionalString(record, "release_date");
		final status = optionalString(record, "status");
		final attachment = optionalBool(record, "attachment");
		final reasoning = optionalBool(record, "reasoning");
		final temperature = optionalBool(record, "temperature");
		final toolCall = optionalBool(record, "tool_call");
		final interleaved = optionalInterleaved(record, "interleaved");
		final cost = optionalCost(record, "cost");
		final provider = optionalProviderApi(record, "provider");
		final modalities = optionalModalities(record, "modalities");
		final experimental = optionalExperimental(record, "experimental");
		if (!family.ok || !releaseDate.ok || !status.ok || !attachment.ok || !reasoning.ok || !temperature.ok || !toolCall.ok || !interleaved.ok
			|| !cost.ok || !provider.ok || !modalities.ok || !experimental.ok)
			return null;
		return {
			id: id,
			name: name,
			family: family.value,
			release_date: releaseDate.value,
			attachment: attachment.value,
			reasoning: reasoning.value,
			temperature: temperature.value,
			tool_call: toolCall.value,
			interleaved: interleaved.value,
			cost: cost.value,
			limit: limit,
			modalities: modalities.value,
			experimental: experimental.value,
			status: status.value,
			provider: provider.value,
		};
	}

	static function decodeLimit(value:Unknown):Null<ModelsDevLimit> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return null;
		final context = requiredNumber(record, "context");
		final output = requiredNumber(record, "output");
		final input = optionalNumber(record, "input");
		if (context == null || output == null || !input.ok)
			return null;
		return {
			context: context,
			input: input.value,
			output: output,
		};
	}

	static function optionalCost(record:UnknownRecord, field:String):Decoded<ModelsDevCost> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		return decodeCost(value);
	}

	static function decodeCost(value:Unknown):Decoded<ModelsDevCost> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return invalid();
		final input = requiredNumber(record, "input");
		final output = requiredNumber(record, "output");
		final cacheRead = optionalNumber(record, "cache_read");
		final cacheWrite = optionalNumber(record, "cache_write");
		final over = optionalOver200K(record, "context_over_200k");
		if (input == null || output == null || !cacheRead.ok || !cacheWrite.ok || !over.ok)
			return invalid();
		final cost:ModelsDevCost = {
			input: input,
			output: output,
			cache_read: cacheRead.value,
			cache_write: cacheWrite.value,
			context_over_200k: over.value,
		};
		return ok(cost);
	}

	static function optionalOver200K(record:UnknownRecord, field:String):Decoded<ModelsDevOver200KCost> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final over = UnknownNarrow.record(value);
		if (over == null)
			return invalid();
		final input = requiredNumber(over, "input");
		final output = requiredNumber(over, "output");
		final cacheRead = optionalNumber(over, "cache_read");
		final cacheWrite = optionalNumber(over, "cache_write");
		if (input == null || output == null || !cacheRead.ok || !cacheWrite.ok)
			return invalid();
		final cost:ModelsDevOver200KCost = {
			input: input,
			output: output,
			cache_read: cacheRead.value,
			cache_write: cacheWrite.value,
		};
		return ok(cost);
	}

	static function optionalProviderApi(record:UnknownRecord, field:String):Decoded<ModelsDevProviderApi> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final provider = UnknownNarrow.record(value);
		if (provider == null)
			return invalid();
		final api = optionalString(provider, "api");
		final npm = optionalString(provider, "npm");
		if (!api.ok || !npm.ok)
			return invalid();
		final providerApi:ModelsDevProviderApi = {
			api: api.value,
			npm: npm.value,
		};
		return ok(providerApi);
	}

	static function optionalModalities(record:UnknownRecord, field:String):Decoded<ModelsDevModalities> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final modalities = UnknownNarrow.record(value);
		if (modalities == null)
			return invalid();
		final input = decodeStringArray(modalities.get("input"));
		final output = decodeStringArray(modalities.get("output"));
		if (input == null || output == null)
			return invalid();
		final decoded:ModelsDevModalities = {
			input: input,
			output: output,
		};
		return ok(decoded);
	}

	static function optionalExperimental(record:UnknownRecord, field:String):Decoded<ModelsDevExperimental> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final experimental = UnknownNarrow.record(value);
		if (experimental == null)
			return invalid();
		final modesRecord = optionalRecord(experimental, "modes");
		if (!modesRecord.ok)
			return invalid();
		if (modesRecord.value == null) {
			final empty:ModelsDevExperimental = {};
			return ok(empty);
		}
		final modes = new DynamicAccess<ModelsDevMode>();
		for (mode in modesRecord.value.keys()) {
			final decoded = decodeMode(modesRecord.value.get(mode));
			if (decoded == null)
				return invalid();
			modes.set(mode, decoded);
		}
		final decoded:ModelsDevExperimental = {modes: modes};
		return ok(decoded);
	}

	static function decodeMode(value:Unknown):Null<ModelsDevMode> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return null;
		final cost = optionalCost(record, "cost");
		final provider = optionalModeProvider(record, "provider");
		if (!cost.ok || !provider.ok)
			return null;
		return {
			cost: cost.value,
			provider: provider.value,
		};
	}

	static function optionalModeProvider(record:UnknownRecord, field:String):Decoded<ModelsDevModeProvider> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final provider = UnknownNarrow.record(value);
		if (provider == null)
			return invalid();
		final bodyRecord = optionalRecord(provider, "body");
		final headers = optionalStringRecord(provider, "headers");
		if (!bodyRecord.ok || !headers.ok)
			return invalid();
		final decoded:ModelsDevModeProvider = {
			body: bodyRecord.value == null ? null : copyUnknownRecord(bodyRecord.value),
			headers: headers.value,
		};
		return ok(decoded);
	}

	static function optionalInterleaved(record:UnknownRecord, field:String):Decoded<ProviderInterleaved> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final bool = UnknownNarrow.bool(value);
		if (bool != null)
			return ok(bool);
		final configRecord = UnknownNarrow.record(value);
		if (configRecord == null)
			return invalid();
		final fieldValue = requiredString(configRecord, "field");
		final interleavedField = switch fieldValue {
			case "reasoning_content":
				ProviderInterleavedField.ReasoningContent;
			case "reasoning_details":
				ProviderInterleavedField.ReasoningDetails;
			case _:
				return invalid();
		}
		final config:ProviderInterleavedConfig = {field: interleavedField};
		return ok(config);
	}

	static function optionalStringRecord(record:UnknownRecord, field:String):Decoded<DynamicAccess<String>> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final source = UnknownNarrow.record(value);
		if (source == null)
			return invalid();
		final out = new DynamicAccess<String>();
		for (key in source.keys()) {
			final item = UnknownNarrow.string(source.get(key));
			if (item == null)
				return invalid();
			out.set(key, item);
		}
		return ok(out);
	}

	static function copyUnknownRecord(record:UnknownRecord):DynamicAccess<Unknown> {
		final out = new DynamicAccess<Unknown>();
		for (key in record.keys())
			out.set(key, record.get(key));
		return out;
	}

	static function optionalRecord(record:UnknownRecord, field:String):Decoded<UnknownRecord> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final nested = UnknownNarrow.record(value);
		return nested == null ? invalid() : ok(nested);
	}

	static function requiredString(record:UnknownRecord, field:String):Null<String> {
		return UnknownNarrow.string(record.get(field));
	}

	static function optionalString(record:UnknownRecord, field:String):Decoded<String> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final text = UnknownNarrow.string(value);
		return text == null ? invalid() : ok(text);
	}

	static function optionalBool(record:UnknownRecord, field:String):Decoded<Bool> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final bool = UnknownNarrow.bool(value);
		return bool == null ? invalid() : ok(bool);
	}

	static function requiredNumber(record:UnknownRecord, field:String):Null<Float> {
		return UnknownNarrow.number(record.get(field));
	}

	static function optionalNumber(record:UnknownRecord, field:String):Decoded<Float> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final number = UnknownNarrow.number(value);
		return number == null ? invalid() : ok(number);
	}

	static function optionalStringArray(record:UnknownRecord, field:String):Decoded<Array<String>> {
		final value = record.get(field);
		if (isAbsent(value))
			return absent();
		final items = decodeStringArray(value);
		return items == null ? invalid() : ok(items);
	}

	static function decodeStringArray(value:Unknown):Null<Array<String>> {
		final items:Null<UnknownArray> = UnknownNarrow.array(value);
		if (items == null)
			return null;
		final out:Array<String> = [];
		for (index in 0...items.length) {
			final item = UnknownNarrow.string(items.get(index));
			if (item == null)
				return null;
			out.push(item);
		}
		return out;
	}

	static function isAbsent(value:Unknown):Bool {
		return UnknownNarrow.isUndefined(value) || UnknownNarrow.isNull(value);
	}

	static function ok<T>(value:Null<T>):Decoded<T> {
		return {ok: true, value: value};
	}

	static function absent<T>():Decoded<T> {
		return {ok: true, value: null};
	}

	static function invalid<T>():Decoded<T> {
		return {ok: false, value: null};
	}

	static function trimRightSlashes(value:String):String {
		var result = value;
		while (result.endsWith("/"))
			result = result.substr(0, result.length - 1);
		return result;
	}
}
