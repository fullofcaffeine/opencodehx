package opencodehx.externs.node;

@:jsRequire("node:fs")
extern class Fs {
	static function existsSync(path:String):Bool;
	static function readFileSync(path:String, encoding:String):String;
	static function writeFileSync(path:String, data:String, ?options:Dynamic):Void;
	static function mkdirSync(path:String, ?options:Dynamic):Void;
	static function mkdtempSync(prefix:String):String;
	static function rmSync(path:String, ?options:Dynamic):Void;
	static function readdirSync(path:String, ?options:Dynamic):Array<Dynamic>;
	static function statSync(path:String):Dynamic;
}
