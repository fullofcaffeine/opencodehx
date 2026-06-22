package opencodehx.plugin;

import opencodehx.config.ConfigInfo;
import opencodehx.plugin.PluginRuntime.PluginSystemOutput;
import genes.ts.Unknown;

/**
 * Typed subset of @opencode-ai/plugin server hooks owned by the current port.
 *
 * The upstream plugin runtime exposes many hooks, but provider loading depends
 * specifically on `server().config(cfg)`: plugins mutate the live config object
 * before Provider.Service reads configured providers and filters. Modeling that
 * hook directly lets provider parity advance without introducing a broad dynamic
 * plugin module boundary before the plugin-loader slice owns it.
 */
typedef PluginConfigHook = ConfigInfo->Void;

typedef PluginSystemTransformHook = (Unknown, PluginSystemOutput) -> Void;

typedef PluginServerHooks = {
	@:optional final config:PluginConfigHook;
	@:optional final systemTransform:PluginSystemTransformHook;
}
