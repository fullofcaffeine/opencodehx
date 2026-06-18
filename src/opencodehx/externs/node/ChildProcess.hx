package opencodehx.externs.node;

@:jsRequire("node:child_process")
extern class ChildProcess {
	static function spawnSync(command:String, args:Array<String>, ?options:Dynamic):Dynamic;
}

typedef SpawnSyncOptions = {
	@:optional final cwd:String;
	@:optional final encoding:String;
	@:optional final env:Dynamic;
	@:optional final shell:Dynamic;
	@:optional final timeout:Int;
	@:optional final killSignal:String;
	@:optional final windowsHide:Bool;
	@:optional final maxBuffer:Int;
	@:optional final input:String;
}

typedef SpawnSyncResult = {
	final stdout:String;
	final stderr:String;
	final status:Null<Int>;
	@:optional final signal:String;
	@:optional final error:Dynamic;
}
