package opencodehx.externs.better_sqlite3;

@:jsRequire("better-sqlite3")
@:ts.type("import('better-sqlite3').Database")
extern class Database {
	function new(path:String);
	function exec(sql:String):Void;
	function prepare(sql:String):Statement;
	// better-sqlite3 pragmas can return scalar values or row-like objects.
	// This facade currently uses pragma for side effects only; callers should
	// add a typed wrapper before reading pragma results.
	function pragma(sql:String):Dynamic;
	function close():Void;
}

@:ts.type("import('better-sqlite3').Statement<unknown[]>")
extern class Statement {
	@:overload(function():RunResult {})
	// SQLite bind parameters and result rows are heterogeneous DB boundary
	// values. BetterSqlite keeps the Dynamic usage localized until storage rows
	// are promoted to schema-specific typed decoders.
	function run(params:Array<Dynamic>):RunResult;
	@:overload(function():Dynamic {})
	function get(params:Array<Dynamic>):Dynamic;
	@:overload(function():Array<Dynamic> {})
	function all(params:Array<Dynamic>):Array<Dynamic>;
}

@:ts.type("import('better-sqlite3').RunResult")
typedef RunResult = {
	final changes:Int;
	final lastInsertRowid:Dynamic;
}
