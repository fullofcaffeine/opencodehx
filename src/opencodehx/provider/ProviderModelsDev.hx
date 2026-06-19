package opencodehx.provider;

import genes.js.Async.await;
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
import opencodehx.provider.ProviderTypes.ModelsDevProvider;

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
		final parsed = Json.parse(text);
		final result = emptyCatalog();
		if (!isRecord(parsed))
			return result;
		for (id in Reflect.fields(parsed)) {
			final value = Reflect.field(parsed, id);
			if (!isProviderShape(value))
				continue;
			// Runtime boundary: models.dev JSON has been checked for the shape this
			// port consumes, but Haxe cannot refine Reflect-read objects into the
			// structural ModelsDevProvider typedef. Keep the cast here and expose a
			// typed catalog to the registry.
			result.set(id, cast value);
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

	// Runtime JSON decoder boundary: models.dev data starts as Dynamic because
	// Haxe Json/Reflect APIs cannot expose a typed structure without validation.
	// These helpers contain the weak reads and only let typed provider records
	// cross into the registry after their consumed shape has been checked.
	static function isProviderShape(value:Dynamic):Bool {
		if (!isRecord(value) || !isString(Reflect.field(value, "id")) || !isString(Reflect.field(value, "name")))
			return false;
		if (!isOptionalString(Reflect.field(value, "api")) || !isOptionalString(Reflect.field(value, "npm")))
			return false;
		if (!isStringArray(Reflect.field(value, "env")))
			return false;
		final models = Reflect.field(value, "models");
		if (!isRecord(models))
			return false;
		for (modelID in Reflect.fields(models))
			if (!isModelShape(Reflect.field(models, modelID)))
				return false;
		return true;
	}

	static function isModelShape(value:Dynamic):Bool {
		if (!isRecord(value) || !isString(Reflect.field(value, "id")) || !isString(Reflect.field(value, "name")))
			return false;
		if (!isOptionalString(Reflect.field(value, "family"))
			|| !isOptionalString(Reflect.field(value, "release_date"))
			|| !isOptionalString(Reflect.field(value, "status")))
			return false;
		if (!isOptionalBool(Reflect.field(value, "attachment"))
			|| !isOptionalBool(Reflect.field(value, "reasoning"))
			|| !isOptionalBool(Reflect.field(value, "temperature"))
			|| !isOptionalBool(Reflect.field(value, "tool_call")))
			return false;
		if (!isLimitShape(Reflect.field(value, "limit")))
			return false;
		if (!isOptionalCost(Reflect.field(value, "cost"))
			|| !isOptionalProviderApi(Reflect.field(value, "provider"))
			|| !isOptionalModalities(Reflect.field(value, "modalities"))
			|| !isOptionalExperimental(Reflect.field(value, "experimental")))
			return false;
		final interleaved = Reflect.field(value, "interleaved");
		return interleaved == null || Std.isOfType(interleaved, Bool) || isRecord(interleaved);
	}

	static function isLimitShape(value:Dynamic):Bool {
		return isRecord(value)
			&& isNumber(Reflect.field(value, "context"))
			&& isNumber(Reflect.field(value, "output"))
			&& isOptionalNumber(Reflect.field(value, "input"));
	}

	static function isOptionalCost(value:Dynamic):Bool {
		if (value == null)
			return true;
		if (!isRecord(value) || !isNumber(Reflect.field(value, "input")) || !isNumber(Reflect.field(value, "output")))
			return false;
		if (!isOptionalNumber(Reflect.field(value, "cache_read")) || !isOptionalNumber(Reflect.field(value, "cache_write")))
			return false;
		final over = Reflect.field(value, "context_over_200k");
		return over == null
			|| (isRecord(over)
				&& isNumber(Reflect.field(over, "input"))
				&& isNumber(Reflect.field(over, "output"))
				&& isOptionalNumber(Reflect.field(over, "cache_read"))
				&& isOptionalNumber(Reflect.field(over, "cache_write")));
	}

	static function isOptionalProviderApi(value:Dynamic):Bool {
		return value == null
			|| (isRecord(value) && isOptionalString(Reflect.field(value, "api")) && isOptionalString(Reflect.field(value, "npm")));
	}

	static function isOptionalModalities(value:Dynamic):Bool {
		return value == null
			|| (isRecord(value) && isStringArray(Reflect.field(value, "input")) && isStringArray(Reflect.field(value, "output")));
	}

	static function isOptionalExperimental(value:Dynamic):Bool {
		if (value == null)
			return true;
		if (!isRecord(value))
			return false;
		final modes = Reflect.field(value, "modes");
		if (modes == null)
			return true;
		if (!isRecord(modes))
			return false;
		for (mode in Reflect.fields(modes))
			if (!isModeShape(Reflect.field(modes, mode)))
				return false;
		return true;
	}

	static function isModeShape(value:Dynamic):Bool {
		if (!isRecord(value))
			return false;
		if (!isOptionalCost(Reflect.field(value, "cost")))
			return false;
		final provider = Reflect.field(value, "provider");
		if (provider == null)
			return true;
		if (!isRecord(provider))
			return false;
		final headers = Reflect.field(provider, "headers");
		return (headers == null || isStringRecord(headers))
			&& (Reflect.field(provider, "body") == null || isRecord(Reflect.field(provider, "body")));
	}

	static function isStringRecord(value:Dynamic):Bool {
		if (!isRecord(value))
			return false;
		for (field in Reflect.fields(value))
			if (!isString(Reflect.field(value, field)))
				return false;
		return true;
	}

	static function isStringArray(value:Dynamic):Bool {
		if (!Std.isOfType(value, Array))
			return false;
		// Json.parse returns erased arrays. The guard above proves the container
		// shape; this cast is kept inside the decoder to validate each element.
		final items:Array<Dynamic> = cast value;
		for (item in items)
			if (!isString(item))
				return false;
		return true;
	}

	static function isOptionalString(value:Dynamic):Bool {
		return value == null || isString(value);
	}

	static function isOptionalBool(value:Dynamic):Bool {
		return value == null || Std.isOfType(value, Bool);
	}

	static function isOptionalNumber(value:Dynamic):Bool {
		return value == null || isNumber(value);
	}

	static function isString(value:Dynamic):Bool {
		return Std.isOfType(value, String);
	}

	static function isNumber(value:Dynamic):Bool {
		return Std.isOfType(value, Int) || Std.isOfType(value, Float);
	}

	static function isRecord(value:Dynamic):Bool {
		if (value == null
			|| Std.isOfType(value, Array)
			|| Std.isOfType(value, String)
			|| Std.isOfType(value, Bool)
			|| isNumber(value))
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
