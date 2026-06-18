package opencodehx.config;

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
		// Managed plist conversion arrives as untyped JSON; strip only known MDM
		// metadata here, then let ConfigLoader validate the remaining config.
		final raw:Dynamic = Json.parse(json);
		for (key in PLIST_META) {
			if (Reflect.hasField(raw, key))
				Reflect.deleteField(raw, key);
		}
		return Json.stringify(raw);
	}
}
