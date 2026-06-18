package opencodehx.externs.jsonc;

typedef JsoncFormattingOptions = {
	@:optional final insertSpaces:Bool;
	@:optional final tabSize:Int;
}

typedef JsoncModifyOptions = {
	@:optional final formattingOptions:JsoncFormattingOptions;
}

typedef JsoncEdit = {
	final offset:Int;
	final length:Int;
	final content:String;
}

@:jsRequire("jsonc-parser")
extern class JsoncParser {
	static function modify(text:String, path:Array<String>, value:Dynamic, ?options:JsoncModifyOptions):Array<JsoncEdit>;
	static function applyEdits(text:String, edits:Array<JsoncEdit>):String;
}
