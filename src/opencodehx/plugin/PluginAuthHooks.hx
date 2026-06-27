package opencodehx.plugin;

import opencodehx.provider.ProviderTypes.ProviderID;

enum abstract PluginAuthMethodType(String) to String {
	final OAuth = "oauth";
	final Api = "api";
}

typedef PluginAuthMethod = {
	final type:PluginAuthMethodType;
	final label:String;
}

typedef PluginAuthHook = {
	final provider:ProviderID;
	final methods:Array<PluginAuthMethod>;
}

class PluginAuthHooks {
	public static function methodsFor(provider:ProviderID, hooks:Array<PluginAuthHook>):Array<PluginAuthMethod> {
		var matched:Null<Array<PluginAuthMethod>> = null;
		for (hook in hooks) {
			if (hook.provider == provider)
				matched = hook.methods;
		}
		return matched == null ? [] : copyMethods(matched);
	}

	public static function concat(base:Array<PluginAuthHook>, overrides:Array<PluginAuthHook>):Array<PluginAuthHook> {
		final result:Array<PluginAuthHook> = [];
		for (hook in base)
			result.push(hook);
		for (hook in overrides)
			result.push(hook);
		return result;
	}

	static function copyMethods(methods:Array<PluginAuthMethod>):Array<PluginAuthMethod> {
		final result:Array<PluginAuthMethod> = [];
		for (method in methods) {
			result.push({
				type: method.type,
				label: method.label,
			});
		}
		return result;
	}
}
