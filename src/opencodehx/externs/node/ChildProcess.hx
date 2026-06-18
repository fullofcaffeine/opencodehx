package opencodehx.externs.node;

@:jsRequire("node:child_process")
extern class ChildProcess {
	static function spawnSync(command:String, args:Array<String>, ?options:SpawnSyncOptions):SpawnSyncResult;
}

typedef SpawnSyncOptions = {
	@:optional final cwd:String;
	@:optional final encoding:String;
	@:optional final env:Dynamic;
	@:optional final windowsHide:Bool;
	@:optional final maxBuffer:Int;
	@:optional final input:String;
}

typedef SpawnSyncResult = {
	final stdout:String;
	final stderr:String;
	final status:Null<Int>;
	@:optional final error:Dynamic;
}
