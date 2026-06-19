package opencodehx.externs.node;

/**
 * Node's spawnSync overloads are sensitive to exact optional-property types.
 * Reusing the upstream Node declaration keeps this extern boundary aligned
 * without weakening application-facing process results.
 */
@:ts.type("import('node:child_process').SpawnSyncOptionsWithStringEncoding")
typedef SpawnSyncOptions = {
	@:optional final cwd:String;
	@:optional final encoding:String;
	@:optional final env:haxe.DynamicAccess<String>;
	@:optional final shell:haxe.extern.EitherType<Bool, String>;
	@:optional final timeout:Int;
	@:optional final killSignal:String;
	@:optional final windowsHide:Bool;
	@:optional final maxBuffer:Int;
	@:optional final input:String;
}

/**
 * The OpenCodeHX process seam always requests utf8 encoding, so callers see
 * string stdout/stderr while Node still owns the exact platform result shape.
 */
@:ts.type("import('node:child_process').SpawnSyncReturns<string>")
typedef SpawnSyncResult = {
	final stdout:String;
	final stderr:String;
	final status:Null<Int>;
	@:optional final signal:String;
	@:optional final error:js.lib.Error;
}

@:jsRequire("node:child_process")
extern class ChildProcess {
	static function spawnSync(command:String, args:Array<String>, ?options:SpawnSyncOptions):SpawnSyncResult;
}
