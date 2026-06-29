package opencodehx.cli;

import opencodehx.plugin.PluginAuthHooks.PluginAuthHook;
import opencodehx.provider.ProviderTypes.ProviderID;

/**
	Typed helper for the provider-login picker entries contributed by plugin auth
	hooks.

	Upstream receives whole plugin `Hooks` objects and checks their optional
	`auth` field. OpenCodeHX keeps that boundary explicit with `PluginProviderHook`
	and converts provider membership checks into `ProviderID` lists so the helper
	does not need broad hook objects or string-keyed open records.
**/
typedef PluginProviderHook = {
	final auth:Null<PluginAuthHook>;
}

typedef PluginProviderDisplayName = {
	final id:ProviderID;
	final name:String;
}

typedef PluginProviderResolutionInput = {
	final hooks:Array<PluginProviderHook>;
	final existingProviders:Array<ProviderID>;
	final disabled:Array<ProviderID>;
	final enabled:Null<Array<ProviderID>>;
	final providerNames:Array<PluginProviderDisplayName>;
}

typedef PluginProviderChoice = {
	final id:ProviderID;
	final name:String;
}

function resolvePluginProviders(input:PluginProviderResolutionInput):Array<PluginProviderChoice> {
	final seen:Array<ProviderID> = [];
	final result:Array<PluginProviderChoice> = [];
	for (hook in input.hooks) {
		final auth = hook.auth;
		if (auth == null)
			continue;
		final id = auth.provider;
		if (containsProvider(seen, id))
			continue;
		seen.push(id);
		if (containsProvider(input.existingProviders, id))
			continue;
		if (containsProvider(input.disabled, id))
			continue;
		if (input.enabled != null && !containsProvider(input.enabled, id))
			continue;
		result.push({
			id: id,
			name: providerName(id, input.providerNames),
		});
	}
	return result;
}

private function containsProvider(values:Null<Array<ProviderID>>, id:ProviderID):Bool {
	if (values == null)
		return false;
	for (value in values) {
		if (value == id)
			return true;
	}
	return false;
}

private function providerName(id:ProviderID, names:Array<PluginProviderDisplayName>):String {
	for (entry in names) {
		if (entry.id == id)
			return entry.name;
	}
	return id.toString();
}
