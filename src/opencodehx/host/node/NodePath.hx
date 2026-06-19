package opencodehx.host.node;

import opencodehx.externs.node.Path;
import opencodehx.externs.node.Path.PathWin32;

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

	public static function windowsJoin(first:String, second:String):String {
		return PathWin32.join(first, second);
	}

	public static function windowsResolve(first:String, second:String):String {
		return PathWin32.resolve(first, second);
	}

	public static function windowsRelative(from:String, to:String):String {
		return PathWin32.relative(from, to);
	}

	public static function windowsDirname(path:String):String {
		return PathWin32.dirname(path);
	}

	public static function windowsIsAbsolute(path:String):Bool {
		return PathWin32.isAbsolute(path);
	}
}
