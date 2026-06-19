package opencodehx.plugin;

import opencodehx.config.ConfigInfo;

/**
 * Applies typed plugin config hooks in upstream order.
 *
 * Hooks intentionally receive the mutable `ConfigInfo` instance. Upstream hands
 * plugins the live config object and Provider.Service reads provider settings
 * only after every config hook has run, so returning a copy here would hide
 * mutation and make later plugin-loader parity less faithful.
 */
class PluginConfigHooks {
	public static function apply(config:ConfigInfo, ?hooks:Array<PluginServerHooks>):ConfigInfo {
		if (hooks == null)
			return config;
		for (hook in hooks) {
			final configHook = hook.config;
			if (configHook != null)
				configHook(config);
		}
		return config;
	}
}
