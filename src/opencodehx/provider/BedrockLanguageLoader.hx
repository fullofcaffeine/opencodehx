package opencodehx.provider;

using StringTools;

/**
 * Amazon Bedrock model IDs need cross-region inference-profile prefixes for
 * selected model families. Upstream applies this immediately before calling
 * `sdk.languageModel(...)`; keeping it as a pure helper lets the registry and
 * smoke tests prove the routing without making AWS calls.
 */
class BedrockLanguageLoader {
	static final CROSS_REGION_PREFIXES = ["global.", "us.", "eu.", "jp.", "apac.", "au."];
	static final US_PREFIX_FAMILIES = [
		"nova-micro",
		"nova-lite",
		"nova-pro",
		"nova-premier",
		"nova-2",
		"claude",
		"deepseek"
	];
	static final EU_PREFIX_FAMILIES = ["claude", "nova-lite", "nova-micro", "llama3", "pixtral"];
	static final AP_PREFIX_FAMILIES = ["claude", "nova-lite", "nova-micro", "nova-pro"];
	static final AU_PREFIX_FAMILIES = ["anthropic.claude-sonnet-4-5", "anthropic.claude-haiku"];

	public static function hasCrossRegionPrefix(modelID:String):Bool {
		return containsPrefix(modelID, CROSS_REGION_PREFIXES);
	}

	public static function sdkModelID(modelID:String, region:String):String {
		if (hasCrossRegionPrefix(modelID))
			return modelID;

		final parts = region.split("-");
		final regionPrefix = parts.length == 0 ? "" : parts[0];
		return switch regionPrefix {
			case "us": needsAny(modelID, US_PREFIX_FAMILIES) && !region.startsWith("us-gov") ? 'us.${modelID}' : modelID;
			case "eu": requiresEuRegionPrefix(region) && needsAny(modelID, EU_PREFIX_FAMILIES) ? 'eu.${modelID}' : modelID;
			case "ap":
				if (region == "ap-southeast-2" || region == "ap-southeast-4") {
					needsAny(modelID, AU_PREFIX_FAMILIES) ? 'au.${modelID}' : modelID;
				} else if (region == "ap-northeast-1") {
					needsAny(modelID, AP_PREFIX_FAMILIES) ? 'jp.${modelID}' : modelID;
				} else {
					needsAny(modelID, AP_PREFIX_FAMILIES) ? 'apac.${modelID}' : modelID;
				}
			case _:
				modelID;
		}
	}

	static function requiresEuRegionPrefix(region:String):Bool {
		return region == "eu-west-1" || region == "eu-west-2" || region == "eu-west-3" || region == "eu-north-1" || region == "eu-central-1"
			|| region == "eu-south-1" || region == "eu-south-2";
	}

	static function containsPrefix(value:String, prefixes:Array<String>):Bool {
		for (prefix in prefixes) {
			if (value.startsWith(prefix))
				return true;
		}
		return false;
	}

	static function needsAny(value:String, needles:Array<String>):Bool {
		for (needle in needles) {
			if (value.contains(needle))
				return true;
		}
		return false;
	}
}
