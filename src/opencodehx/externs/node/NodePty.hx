package opencodehx.externs.node;

typedef PtySpawnOptions = {
	@:optional final name:String;
	@:optional final cols:Int;
	@:optional final rows:Int;
	@:optional final cwd:String;
	@:optional final env:haxe.DynamicAccess<String>;
}

typedef PtyExit = {
	final exitCode:Int;
	@:optional final signal:Int;
}

typedef PtyDisposable = {
	function dispose():Void;
}

typedef PtyProcess = {
	final pid:Int;
	final onData:(listener:String->Void)->PtyDisposable;
	final onExit:(listener:PtyExit->Void)->PtyDisposable;
	final write:String->Void;
	final resize:(cols:Int, rows:Int) -> Void;
	final kill:(?signal:String) -> Void;
}

@:jsRequire("@lydell/node-pty")
extern class NodePty {
	static function spawn(file:String, args:Array<String>, options:PtySpawnOptions):PtyProcess;
}
