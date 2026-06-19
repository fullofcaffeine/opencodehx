package opencodehx.config;

import opencodehx.externs.node.Fs;
import opencodehx.host.node.NodePath;
import opencodehx.npm.Npm;
import opencodehx.npm.Npm.NpmDeps;
import opencodehx.npm.Npm.NpmInstallPackage;

typedef ConfigDependencyResult = {
	final directory:String;
	final installed:Bool;
	final error:Null<String>;
}

class ConfigDependencyRuntime {
	static final PLUGIN_PACKAGE = "@opencode-ai/plugin";
	static final GITIGNORE = ["node_modules", "package.json", "package-lock.json", "bun.lock", ".gitignore"].join("\n");

	public static function bootstrapPluginDependency(deps:NpmDeps, directory:String, version:Null<String>, installationLocal:Bool):ConfigDependencyResult {
		ensureGitignore(directory);
		try {
			Npm.install(deps, directory, {add: [pluginPackage(version, installationLocal)]});
			return {directory: directory, installed: true, error: null};
			// Dynamic is required here because the Npm reify seam represents external
			// package-manager/Arborist failures. The helper contains that failure as a
			// typed result so config loading can log or wait on dependency failures.
		} catch (error:Dynamic) {
			return {directory: directory, installed: false, error: Std.string(error)};
		}
	}

	static function ensureGitignore(directory:String):Void {
		final gitignore = NodePath.join(directory, ".gitignore");
		if (Fs.existsSync(gitignore))
			return;
		Fs.writeFileSync(gitignore, GITIGNORE, "utf8");
	}

	static function pluginPackage(version:Null<String>, installationLocal:Bool):NpmInstallPackage {
		if (installationLocal || version == null || version == "")
			return {name: PLUGIN_PACKAGE};
		return {name: PLUGIN_PACKAGE, version: version};
	}
}
