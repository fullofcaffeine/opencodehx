package opencodehx.host.node;

import opencodehx.externs.node.Path;

class NodePath {
	public static function join(first:String, second:String):String {
		return Path.join(first, second);
	}

	public static function dirname(path:String):String {
		return Path.dirname(path);
	}

	public static function isAbsolute(path:String):Bool {
		return Path.isAbsolute(path);
	}

	public static function normalize(path:String):String {
		return Path.normalize(path);
	}
}
