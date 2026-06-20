package opencodehx.host.node;

import haxe.DynamicAccess;
import opencodehx.externs.node.Os;

class GlobalPaths {
	public static function config(env:DynamicAccess<String>):String {
		final xdgConfig = env.get("XDG_CONFIG_HOME");
		final base:String = if (xdgConfig != null && xdgConfig != "") xdgConfig; else NodePath.join(home(env), ".config");
		return NodePath.join(base, "opencode");
	}

	public static function data(env:DynamicAccess<String>):String {
		final xdgData = env.get("XDG_DATA_HOME");
		final base:String = if (xdgData != null && xdgData != "") xdgData; else NodePath.join(NodePath.join(home(env), ".local"), "share");
		return NodePath.join(base, "opencode");
	}

	static function home(env:DynamicAccess<String>):String {
		final testHome = env.get("OPENCODE_TEST_HOME");
		return testHome != null && testHome != "" ? testHome : Os.homedir();
	}
}
