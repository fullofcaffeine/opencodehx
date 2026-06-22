package opencodehx.smoke;

import genes.ts.Unknown;
import opencodehx.config.ConfigPlugin;
import opencodehx.config.ConfigPlugin.PluginOrigin;
import opencodehx.config.ConfigPlugin.PluginScope;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.externs.node.Url;
import opencodehx.host.node.NodePath;
import opencodehx.plugin.PluginMeta;
import opencodehx.plugin.PluginRuntime;
import opencodehx.plugin.PluginRuntime.PluginLegacyExport;
import opencodehx.plugin.PluginRuntime.PluginModule;
import opencodehx.plugin.PluginRuntime.PluginV1Export;
import opencodehx.plugin.PluginServerHooks;
import opencodehx.plugin.PluginShared;
import opencodehx.plugin.PluginShared.PluginSource;

class PluginSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-plugin-"));
		try {
			parseSpecifiers();
			metadata(root);
			runtime(root);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Dynamic) {
			// Smoke cleanup must catch arbitrary Haxe/JS failures and preserve
			// the original exception for the shared runner.
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function parseSpecifiers():Void {
		parsed("acme", "acme", "latest");
		parsed("acme@1.0.0", "acme", "1.0.0");
		parsed("@opencode/acme", "@opencode/acme", "latest");
		parsed("@opencode/acme@1.0.0", "@opencode/acme", "1.0.0");
		parsed("acme@git+https://github.com/opencode/acme.git", "acme", "git+https://github.com/opencode/acme.git");
		parsed("@opencode/acme@git+ssh://git@github.com/opencode/acme.git", "@opencode/acme", "git+ssh://git@github.com/opencode/acme.git");
		parsed("git+ssh://git@github.com/opencode/acme.git", "git+ssh://git@github.com/opencode/acme.git", "");
		parsed("acme@npm:@opencode/acme@1.0.0", "acme", "npm:@opencode/acme@1.0.0");
		parsed("npm:@opencode/acme@1.0.0", "@opencode/acme", "1.0.0");
		parsed("npm:@opencode/acme", "@opencode/acme", "latest");
	}

	static function metadata(root:String):Void {
		final file = NodePath.join(root, "plugin.ts");
		write(file, "export default async () => ({})\n");
		final state = NodePath.join(root, "state/plugin-meta.json");
		var clock = 1000.0;
		final meta = new PluginMeta(state, () -> {
			clock += 1;
			return clock;
		});
		final spec = Url.pathToFileURL(file).href;
		final one = meta.touch(spec, spec, "demo.file");
		eq(one.state, "first", "plugin meta first file");
		eq(one.entry.source, PluginSource.File, "plugin meta file source");
		final two = meta.touch(spec, spec, "demo.file");
		eq(two.state, "same", "plugin meta same file");
		eq(two.entry.load_count, 2, "plugin meta load count");
		write(file, "export default async () => ({ ok: true })\n");
		final three = meta.touch(spec, spec, "demo.file");
		eq(three.state, "updated", "plugin meta updated file");

		final mod = NodePath.join(root, "node_modules/acme-plugin");
		Fs.mkdirSync(mod, {recursive: true});
		write(NodePath.join(mod, "package.json"), '{"name":"acme-plugin","version":"1.0.0"}');
		final npmOne = meta.touch("acme-plugin@latest", mod, "acme-plugin");
		eq(npmOne.entry.requested, "latest", "plugin meta npm requested");
		eq(npmOne.entry.version, "1.0.0", "plugin meta npm version");
		write(NodePath.join(mod, "package.json"), '{"name":"acme-plugin","version":"1.1.0"}');
		final npmTwo = meta.touch("acme-plugin@latest", mod, "acme-plugin");
		eq(npmTwo.state, "updated", "plugin meta npm updated");
		eq(meta.list().get("acme-plugin").version, "1.1.0", "plugin meta persisted npm version");
	}

	static function runtime(root:String):Void {
		final file = NodePath.join(root, "plugin.ts");
		write(file, "export default async () => ({})\n");
		final fileSpec = Url.pathToFileURL(file).href;
		final pkgDir = NodePath.join(root, "node_modules/acme-plugin");
		Fs.mkdirSync(pkgDir, {recursive: true});
		write(NodePath.join(pkgDir, "package.json"), '{"name":"acme-plugin","version":"1.0.0","main":"./index.js"}');
		final origins = [
			origin(fileSpec),
			origin("acme-plugin"),
			origin("missing-plugin"),
			origin("bad-file"),
			origin("mixed-file"),
			origin("dedupe-file")
		];
		final modules:Array<SmokePluginModule> = [];
		modules.push({spec: fileSpec, module: {defaultV1: v1("demo.file", "file-default"), legacy: [legacy("ignored", "ignored")]}});
		modules.push({spec: "acme-plugin", module: {legacy: [legacy("pkg-one", "pkg-one")]}});
		modules.push({spec: "bad-file", module: {defaultV1: v1(null, "bad"), legacy: []}});
		modules.push({spec: "mixed-file", module: {defaultV1: {id: "mixed", server: spec -> hook("mixed"), tui: true}, legacy: []}});
		final same = legacy("same", "dedupe");
		modules.push({spec: "dedupe-file", module: {legacy: [same, same]}});
		final runtime = new PluginRuntime(origins, spec -> {
			final raw = ConfigPlugin.specifier(spec);
			final target = raw == "acme-plugin" ? pkgDir : raw;
			return PluginShared.createPluginEntry(raw, target);
		}, entry -> moduleFor(modules, entry.spec));
		eq(runtime.list().length, 3, "plugin runtime loaded hooks");
		final out = runtime.trigger("experimental.chat.system.transform", Unknown.fromBoundary({}), {system: []});
		eq(out.system.join(","), "file-default,pkg-one,dedupe", "plugin trigger hook order");
	}

	static function parsed(spec:String, pkg:String, version:String):Void {
		final out = PluginShared.parsePluginSpecifier(spec);
		eq(out.pkg, pkg, 'plugin parse pkg ${spec}');
		eq(out.version, version, 'plugin parse version ${spec}');
	}

	static function origin(spec:String):PluginOrigin {
		return ConfigPlugin.withOrigin({specifier: spec}, "smoke", PluginScope.PluginScopeLocal);
	}

	static function v1(id:Null<String>, label:String):PluginV1Export {
		return {id: id, server: _ -> hook(label)};
	}

	static function legacy(identity:String, label:String):PluginLegacyExport {
		return {identity: identity, server: _ -> hook(label)};
	}

	static function hook(label:String):PluginServerHooks {
		return {
			systemTransform: (_input, output) -> output.system.push(label),
		};
	}

	static function moduleFor(modules:Array<SmokePluginModule>, spec:String):Null<PluginModule> {
		for (item in modules) {
			if (item.spec == spec)
				return item.module;
		}
		return null;
	}

	static function write(path:String, content:String):Void {
		Fs.mkdirSync(NodePath.dirname(path), {recursive: true});
		Fs.writeFileSync(path, content, {encoding: "utf8"});
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw '${label}: expected ${expected}, got ${actual}';
	}
}

typedef SmokePluginModule = {
	final spec:String;
	final module:PluginModule;
}
