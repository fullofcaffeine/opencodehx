package opencodehx.auth;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
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
		write(data);
	}

	public static function remove(key:String):Void {
		final env = NodeProcess.env();
		final normalized = trimRightSlashes(key);
		final data = load(env);
		data.remove(key);
		data.remove(normalized);
		data.remove(normalized + "/");
		write(data);
	}

	private static function write(data:AuthMap):Void {
		final env = NodeProcess.env();
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
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return result;
		for (field in record.keys()) {
			final entry = decodeEntry(record.get(field));
			if (entry != null)
				result.set(trimRightSlashes(field), entry);
		}
		return result;
	}

	private static function decodeEntry(raw:Unknown):Null<AuthEntry> {
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return null;
		final type = stringField(record, "type");
		return switch type {
			case "api":
				final key = stringField(record, "key");
				if (key == null) null; else {
					type: "api",
					key: key,
					metadata: metadata(record.get("metadata")),
				};
			case "oauth":
				final refresh = stringField(record, "refresh");
				final access = stringField(record, "access");
				final expires = numberField(record, "expires");
				if (refresh == null || access == null || expires == null) null; else {
					type: "oauth",
					refresh: refresh,
					access: access,
					expires: expires,
					accountId: stringField(record, "accountId"),
					enterpriseUrl: stringField(record, "enterpriseUrl"),
				};
			case "wellknown":
				final key = stringField(record, "key");
				final token = stringField(record, "token");
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
		final record = UnknownNarrow.record(raw);
		if (record == null)
			return null;
		final out:AuthMetadata = new DynamicAccess<String>();
		for (field in record.keys()) {
			final value = UnknownNarrow.string(record.get(field));
			if (value != null)
				out.set(field, value);
		}
		return out;
	}

	private static function empty():AuthMap {
		return new DynamicAccess<AuthEntry>();
	}

	private static function stringField(record:UnknownRecord, field:String):Null<String> {
		return UnknownNarrow.string(record.get(field));
	}

	private static function numberField(record:UnknownRecord, field:String):Null<Float> {
		return UnknownNarrow.number(record.get(field));
	}

	private static function trimRightSlashes(value:String):String {
		var out = value;
		while (out.length > 1 && out.charAt(out.length - 1) == "/")
			out = out.substr(0, out.length - 1);
		return out;
	}
}
