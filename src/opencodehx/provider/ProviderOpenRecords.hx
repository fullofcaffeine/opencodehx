package opencodehx.provider;

import haxe.DynamicAccess;
import opencodehx.provider.ProviderTypes.ProviderHeaders;
import opencodehx.provider.ProviderTypes.ProviderOptions;
import opencodehx.provider.ProviderTypes.ProviderVariants;

class ProviderOpenRecords {
	public static function options():ProviderOptions {
		// ProviderOptions is the documented SDK passthrough boundary. Keep empty
		// open-record construction here so product helpers stay typed.
		return new DynamicAccess<Dynamic>();
	}

	public static function headers():ProviderHeaders {
		return new DynamicAccess<String>();
	}

	public static function variants():ProviderVariants {
		return new DynamicAccess<ProviderOptions>();
	}
}
