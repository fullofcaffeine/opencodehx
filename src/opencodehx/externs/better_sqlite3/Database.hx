package opencodehx.externs.better_sqlite3;

@:jsRequire("better-sqlite3")
extern class Database {
	function new(path:String);
	function exec(sql:String):Void;
	function prepare(sql:String):Statement;
	function pragma(sql:String):Dynamic;
	function close():Void;
}

extern class Statement {
	function run():RunResult;
	function get():Dynamic;
	function all():Array<Dynamic>;
}

typedef RunResult = {
	final changes:Int;
	final lastInsertRowid:Dynamic;
}
