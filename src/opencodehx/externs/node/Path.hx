package opencodehx.externs.node;

@:jsRequire("node:path")
extern class Path {
	static function join(paths:haxe.extern.Rest<String>):String;
	static function normalize(path:String):String;
	static function resolve(paths:haxe.extern.Rest<String>):String;
	static function relative(from:String, to:String):String;
	static function basename(path:String):String;
	static function dirname(path:String):String;
	static function extname(path:String):String;
	static function isAbsolute(path:String):Bool;
}

@:jsRequire("node:path", "win32")
extern class PathWin32 {
	static function join(paths:haxe.extern.Rest<String>):String;
	static function resolve(paths:haxe.extern.Rest<String>):String;
	static function relative(from:String, to:String):String;
	static function dirname(path:String):String;
	static function isAbsolute(path:String):Bool;
}
