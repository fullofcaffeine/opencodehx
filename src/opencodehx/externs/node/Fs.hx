package opencodehx.externs.node;

import opencodehx.externs.node.Buffer.NodeBufferData;

extern typedef FsStats = {
	function isDirectory():Bool;
	function isFile():Bool;
	@:optional final mtimeMs:Float;
}

extern typedef FsWatchOptions = {
	@:optional final persistent:Bool;
	@:optional final recursive:Bool;
	@:optional final encoding:String;
}

typedef FsWatchListener = (String, Null<String>) -> Void;

extern typedef FsWatcher = {
	function close():Void;
}

@:jsRequire("node:fs")
extern class Fs {
	static function existsSync(path:String):Bool;
	static function readFileSync(path:String, encoding:String):String;
	@:native("readFileSync") static function readFileBufferSync(path:String):NodeBufferData;
	static function writeFileSync(path:String, data:String, ?options:Dynamic):Void;
	static function chmodSync(path:String, mode:Int):Void;
	static function unlinkSync(path:String):Void;
	static function mkdirSync(path:String, ?options:Dynamic):Void;
	static function mkdtempSync(prefix:String):String;
	static function rmSync(path:String, ?options:Dynamic):Void;
	static function readdirSync(path:String, ?options:Dynamic):Array<Dynamic>;
	@:native("readdirSync") static function readdirNamesSync(path:String):Array<String>;
	static function statSync(path:String):FsStats;
	static function realpathSync(path:String):String;
	static function watch(path:String, options:FsWatchOptions, listener:FsWatchListener):FsWatcher;
}
