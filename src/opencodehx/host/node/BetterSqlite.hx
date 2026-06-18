package opencodehx.host.node;

import js.Syntax;
import opencodehx.externs.better_sqlite3.Database;

class BetterSqlite {
	public final db:Dynamic;

	public function new(path:String) {
		db = Syntax.code("new {0}({1})", Database, path);
	}

	public function exec(sql:String):Void {
		db.exec(sql);
	}

	public function pragma(sql:String):Void {
		db.pragma(sql);
	}

	public function close():Void {
		db.close();
	}

	public function run(sql:String, ?params:Array<Dynamic>):Int {
		final statement:Dynamic = db.prepare(sql);
		final result:Dynamic = apply(statement, "run", params);
		return result.changes;
	}

	public function get(sql:String, ?params:Array<Dynamic>):Dynamic {
		return apply(db.prepare(sql), "get", params);
	}

	public function all(sql:String, ?params:Array<Dynamic>):Array<Dynamic> {
		return cast apply(db.prepare(sql), "all", params);
	}

	static function apply(statement:Dynamic, method:String, ?params:Array<Dynamic>):Dynamic {
		final args = params == null ? [] : params;
		return Syntax.code("{0}[{1}](...{2})", statement, method, args);
	}
}
