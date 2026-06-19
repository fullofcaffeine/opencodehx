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

	public static function resolve(first:String, second:String):String {
		return Path.resolve(first, second);
	}

	public static function relative(from:String, to:String):String {
		return Path.relative(from, to);
	}

	public static function basename(path:String):String {
		return Path.basename(path);
	}

	public static function extname(path:String):String {
		return Path.extname(path);
	}
}
