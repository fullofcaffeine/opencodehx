package opencodehx.host.node;

import opencodehx.externs.better_sqlite3.Database;

/**
	Small host facade for better-sqlite3.

	The constructor and statement dispatch stay typed Haxe. Row values and bind
	parameters remain Dynamic because SQLite rows are schema-dependent JS objects
	at this boundary; storage modules must decode them before domain use.
**/
class BetterSqlite {
	public final db:Database;

	public function new(path:String) {
		db = new Database(path);
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
		final statement = db.prepare(sql);
		final result = params == null ? statement.run() : statement.run(params);
		return result.changes;
	}

	public function get(sql:String, ?params:Array<Dynamic>):Dynamic {
		final statement = db.prepare(sql);
		return params == null ? statement.get() : statement.get(params);
	}

	public function all(sql:String, ?params:Array<Dynamic>):Array<Dynamic> {
		final statement = db.prepare(sql);
		return params == null ? statement.all() : statement.all(params);
	}
}
