package opencodehx.plugin;

import genes.ts.Unknown;
import haxe.DynamicAccess;
import opencodehx.config.ConfigPlugin.PluginOrigin;
import opencodehx.config.ConfigPlugin.PluginSpec;
import opencodehx.plugin.PluginServerHooks;
import opencodehx.plugin.PluginShared;
import opencodehx.plugin.PluginShared.PluginEntry;

typedef PluginSystemOutput = {
	final system:Array<String>;
}

typedef PluginServerFactory = PluginSpec->PluginServerHooks;

typedef PluginV1Export = {
	@:optional final id:String;
	@:optional final server:PluginServerFactory;
	@:optional final tui:Bool;
}

typedef PluginLegacyExport = {
	final identity:String;
	final server:PluginServerFactory;
}

typedef PluginModule = {
	@:optional final defaultV1:PluginV1Export;
	final legacy:Array<PluginLegacyExport>;
}

typedef PluginModuleProvider = PluginEntry->Null<PluginModule>;
typedef PluginResolver = PluginSpec->PluginEntry;

class PluginRuntime {
	final origins:Array<PluginOrigin>;
	final resolver:PluginResolver;
	final provider:PluginModuleProvider;
	final hooks:Array<PluginServerHooks> = [];
	var initialized = false;

	public function new(origins:Array<PluginOrigin>, resolver:PluginResolver, provider:PluginModuleProvider) {
		this.origins = origins;
		this.resolver = resolver;
		this.provider = provider;
	}

	public function init():Void {
		if (initialized)
			return;
		initialized = true;
		for (origin in origins) {
			final entry = resolver(origin.spec);
			final mod = provider(entry);
			if (mod == null)
				continue;
			loadModule(entry, origin.spec, mod);
		}
	}

	public function list():Array<PluginServerHooks> {
		init();
		return hooks.copy();
	}

	public function trigger(name:String, input:Unknown, output:PluginSystemOutput):PluginSystemOutput {
		init();
		if (name != "experimental.chat.system.transform")
			return output;
		for (hook in hooks) {
			final transform = hook.systemTransform;
			if (transform != null)
				transform(input, output);
		}
		return output;
	}

	function loadModule(entry:PluginEntry, spec:PluginSpec, mod:PluginModule):Void {
		if (mod.defaultV1 != null) {
			final plugin = readV1Plugin(entry, mod.defaultV1);
			if (plugin != null) {
				final server = plugin.server;
				if (server != null)
					hooks.push(server(spec));
			}
			return;
		}
		final seen = new Map<String, Bool>();
		for (legacy in mod.legacy) {
			if (seen.exists(legacy.identity))
				continue;
			seen.set(legacy.identity, true);
			hooks.push(legacy.server(spec));
		}
	}

	function readV1Plugin(entry:PluginEntry, plugin:PluginV1Export):Null<PluginV1Export> {
		if (plugin.tui == true && plugin.server != null)
			return null;
		if (plugin.server == null)
			return null;
		try {
			PluginShared.resolvePluginId(entry.source, entry.spec, entry.target, plugin.id, entry.pkg);
		} catch (_:Dynamic) {
			return null;
		}
		return plugin;
	}
}
