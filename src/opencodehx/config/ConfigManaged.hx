package opencodehx.config;

import genes.ts.Unknown;
import genes.ts.JsonCodec;
import genes.ts.UnknownNarrow;
import haxe.Json;

typedef ManagedConfigSource = {
	final text:String;
	final source:String;
}

class ConfigManaged {
	static final PLIST_META = [
		"PayloadDisplayName",
		"PayloadIdentifier",
		"PayloadType",
		"PayloadUUID",
		"PayloadVersion",
		"_manualProfile",
	];

	public static function parseManagedPlist(json:String):String {
		final parsed = switch JsonCodec.parse(json) {
			case Ok(value): value;
			case Error(error): throw error.message;
		}
		final record = UnknownNarrow.record(Unknown.fromBoundary(parsed));
		if (record == null)
			return JsonCodec.stringify(parsed);
		final fields:Array<String> = [];
		for (key in record.keys()) {
			if (!isMetadataKey(key)) {
				final value = JsonCodec.narrow(record.get(key));
				if (value != null)
					fields.push(Json.stringify(key) + ":" + JsonCodec.stringify(value));
			}
		}
		return "{" + fields.join(",") + "}";
	}

	static function isMetadataKey(key:String):Bool {
		return PLIST_META.indexOf(key) != -1;
	}
}
