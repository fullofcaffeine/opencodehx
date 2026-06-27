package opencodehx.plugin;

import genes.ts.Unknown;
import opencodehx.config.ConfigInfo;

typedef PluginConfigHookError = {
	final hookIndex:Int;
	final error:Unknown;
}

typedef PluginConfigHookErrorReporter = PluginConfigHookError->Void;

/**
 * Applies typed plugin config hooks in upstream order.
 *
 * Hooks intentionally receive the mutable `ConfigInfo` instance. Upstream hands
 * plugins the live config object and Provider.Service reads provider settings
 * only after every config hook has run, so returning a copy here would hide
 * mutation and make later plugin-loader parity less faithful.
 */
class PluginConfigHooks {
	public static function apply(config:ConfigInfo, ?hooks:Array<PluginServerHooks>, ?reporter:PluginConfigHookErrorReporter):ConfigInfo {
		if (hooks == null)
			return config;
		var hookIndex = 0;
		for (hook in hooks) {
			final configHook = hook.config;
			if (configHook != null) {
				try {
					configHook(config);
				} catch (error:Dynamic) {
					// Plugin hooks may throw arbitrary host values. Keep the
					// value opaque and continue so one plugin cannot block later
					// config hooks, matching upstream's Effect.ignore isolation.
					if (reporter != null)
						reporter({hookIndex: hookIndex, error: Unknown.fromBoundary(error)});
				}
			}
			hookIndex += 1;
		}
		return config;
	}
}
