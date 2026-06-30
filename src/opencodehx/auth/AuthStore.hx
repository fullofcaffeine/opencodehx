package opencodehx.auth;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import haxe.Json;
import opencodehx.config.ConfigLoader.WellKnownAuth;
import opencodehx.externs.node.Fs;
import opencodehx.host.node.GlobalPaths;
import opencodehx.host.node.NodePath;
import opencodehx.host.node.NodeProcess;

typedef AuthMetadata = DynamicAccess<String>;

typedef AuthEntry = {
	final type:String;
	@:optional final key:String;
	@:optional final access:String;
	@:optional final refresh:String;
	@:optional final token:String;
	@:optional final expires:Float;
	@:optional final accountId:String;
	@:optional final enterpriseUrl:String;
	@:optional final metadata:AuthMetadata;
}

typedef AuthMap = DynamicAccess<AuthEntry>;

/**
	Loads upstream-compatible OpenCode auth entries from the Node host.

	Auth JSON is untrusted runtime input, so this module is the containment
	boundary: it parses raw JSON locally, validates the known auth entry shapes,
	and returns a typed superset used by provider/config code.
**/
class AuthStore {
	public static function load(env:DynamicAccess<String>):AuthMap {
		final content = env.get("OPENCODE_AUTH_CONTENT");
		if (content != null && content != "") {
			final parsed = parse(content);
			if (parsed != null)
				return parsed;
		}

		final file = NodePath.join(GlobalPaths.data(env), "auth.json");
		if (!Fs.existsSync(file))
			return empty();
		return parse(Fs.readFileSync(file, "utf8")) ?? empty();
	}

	public static function wellKnown(auth:AuthMap):Array<WellKnownAuth> {
		final result:Array<WellKnownAuth> = [];
		for (url in auth.keys()) {
			final entry = auth.get(url);
			if (entry.type == "wellknown" && entry.key != null && entry.token != null) {
				result.push({
					url: url,
					key: entry.key,
					token: entry.token,
				});
			}
		}
		return result;
	}

	public static function set(key:String, info:AuthEntry):Void {
		final env = NodeProcess.env();
		final normalized = trimRightSlashes(key);
		final data = load(env);
		if (normalized != key)
			data.remove(key);
		data.remove(normalized + "/");
		data.set(normalized, info);
		final file = NodePath.join(GlobalPaths.data(env), "auth.json");
		Fs.mkdirSync(NodePath.dirname(file), {recursive: true});
		Fs.writeFileSync(file, Json.stringify(data));
		Fs.chmodSync(file, 384);
	}

	private static function parse(text:String):Null<AuthMap> {
		try {
			// Json.parse has no static result type in Haxe. Mark the root as
			// Unknown, then validate every field before returning AuthMap.
			final raw = Unknown.fromBoundary(Json.parse(text));
			return decodeMap(raw);
		} catch (_:Dynamic) {
			// JS JSON.parse can throw host-native values, so Dynamic is the least
			// broad catch that reliably mirrors upstream's best-effort auth load.
			return null;
		}
	}

	private static function decodeMap(raw:Unknown):AuthMap {
		final result = empty();
		if (!isRecord(raw))
			return result;
		for (field in recordFields(raw)) {
			final entry = decodeEntry(fieldValue(raw, field));
			if (entry != null)
				result.set(trimRightSlashes(field), entry);
		}
		return result;
	}

	private static function decodeEntry(raw:Unknown):Null<AuthEntry> {
		if (!isRecord(raw))
			return null;
		final type = stringValue(fieldValue(raw, "type"));
		return switch type {
			case "api":
				final key = stringValue(fieldValue(raw, "key"));
				if (key == null) null; else {
					type: "api",
					key: key,
					metadata: metadata(fieldValue(raw, "metadata")),
				};
			case "oauth":
				final refresh = stringValue(fieldValue(raw, "refresh"));
				final access = stringValue(fieldValue(raw, "access"));
				final expires = numberValue(fieldValue(raw, "expires"));
				if (refresh == null || access == null || expires == null) null; else {
					type: "oauth",
					refresh: refresh,
					access: access,
					expires: expires,
					accountId: stringValue(fieldValue(raw, "accountId")),
					enterpriseUrl: stringValue(fieldValue(raw, "enterpriseUrl")),
				};
			case "wellknown":
				final key = stringValue(fieldValue(raw, "key"));
				final token = stringValue(fieldValue(raw, "token"));
				if (key == null || token == null) null; else {
					type: "wellknown",
					key: key,
					token: token,
				};
			case _:
				null;
		}
	}

	private static function metadata(raw:Unknown):Null<AuthMetadata> {
		if (!isRecord(raw))
			return null;
		final out:AuthMetadata = new DynamicAccess<String>();
		for (field in recordFields(raw)) {
			final value = stringValue(fieldValue(raw, field));
			if (value != null)
				out.set(field, value);
		}
		return out;
	}

	private static function empty():AuthMap {
		return new DynamicAccess<AuthEntry>();
	}

	private static function isRecord(value:Unknown):Bool {
		// Runtime JSON category checks require inspecting the unknown value.
		// Keep the cast local and return only a boolean narrowing result.
		final raw:Dynamic = cast value;
		return raw != null && !Std.isOfType(raw, Array) && Reflect.isObject(raw);
	}

	private static function stringValue(value:Unknown):Null<String> {
		// Runtime JSON primitive narrowing: the cast is guarded by Std.isOfType
		// and never escapes this decoder as Dynamic.
		final raw:Dynamic = cast value;
		return Std.isOfType(raw, String) ? cast raw : null;
	}

	private static function numberValue(value:Unknown):Null<Float> {
		// Runtime JSON primitive narrowing: the cast is guarded by Std.isOfType
		// and never escapes this decoder as Dynamic.
		final raw:Dynamic = cast value;
		return Std.isOfType(raw, Int) || Std.isOfType(raw, Float) ? cast raw : null;
	}

	private static function recordFields(record:Unknown):Array<String> {
		// Unknown is intentionally cast only inside this decoder boundary after
		// the broad object check above; every field is narrowed before escaping.
		final object:Dynamic = cast record;
		return Reflect.fields(object);
	}

	private static function fieldValue(record:Unknown, name:String):Unknown {
		// Reflect.field is needed for runtime JSON object keys. Wrapping the
		// result as Unknown forces every consumer to narrow before use.
		final object:Dynamic = cast record;
		return Unknown.fromBoundary(Reflect.field(object, name));
	}

	private static function trimRightSlashes(value:String):String {
		var out = value;
		while (out.length > 1 && out.charAt(out.length - 1) == "/")
			out = out.substr(0, out.length - 1);
		return out;
	}
}
