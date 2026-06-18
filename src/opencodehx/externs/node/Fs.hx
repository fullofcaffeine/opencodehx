package opencodehx.externs.node;

@:ts.type("import('node:buffer').Buffer")
abstract NodeBufferData(Dynamic) from Dynamic to Dynamic {}

@:jsRequire("node:fs")
extern class Fs {
	static function existsSync(path:String):Bool;
	static function readFileSync(path:String, encoding:String):String;
	@:native("readFileSync") static function readFileBufferSync(path:String):NodeBufferData;
	static function writeFileSync(path:String, data:String, ?options:Dynamic):Void;
	static function mkdirSync(path:String, ?options:Dynamic):Void;
	static function mkdtempSync(prefix:String):String;
	static function rmSync(path:String, ?options:Dynamic):Void;
	static function readdirSync(path:String, ?options:Dynamic):Array<Dynamic>;
	static function statSync(path:String):Dynamic;
}
