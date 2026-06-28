package opencodehx.externs.node;

import haxe.DynamicAccess;
import opencodehx.externs.node.Buffer.NodeBufferData;

@:ts.type("NodeJS.Signals")
abstract NodeSignal(String) from String to String {}

@:ts.type("import('node:child_process').SpawnOptions")
typedef SpawnOptions = {
	@:optional final cwd:String;
	@:optional final env:DynamicAccess<String>;
	@:optional final detached:Bool;
	@:optional final shell:haxe.extern.EitherType<Bool, String>;
	@:optional final stdio:String;
	@:optional final windowsHide:Bool;
}

/**
 * Node's spawnSync overloads are sensitive to exact optional-property types.
 * Reusing the upstream Node declaration keeps this extern boundary aligned
 * without weakening application-facing process results.
 */
@:ts.type("import('node:child_process').SpawnSyncOptionsWithStringEncoding")
typedef SpawnSyncOptions = {
	@:optional final cwd:String;
	@:optional final encoding:String;
	@:optional final env:DynamicAccess<String>;
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

typedef ChildProcessHandle = {
	@:optional final pid:Int;
	@:optional final stdin:NodeChildWritableStream;
	@:optional final stdout:NodeReadableStream;
	@:optional final stderr:NodeReadableStream;
	@:optional final exitCode:Null<Int>;
	@:optional final signalCode:Null<String>;
	function kill(?signal:NodeSignal):Bool;
	function once(event:String, listener:Dynamic->Void):ChildProcessHandle;
	function unref():Void;
}

typedef NodeChildWritableStream = {
	function write(value:String):Void;
	function end():Void;
}

@:ts.type("import('node:stream').Readable")
extern class NodeReadableStream {
	function setEncoding(encoding:String):Void;
	@:overload(function(event:String, listener:Void->Void):NodeReadableStream {})
	@:overload(function(event:String, listener:Dynamic->Void):NodeReadableStream {})
	@:overload(function(event:String, listener:NodeBufferData->Void):NodeReadableStream {})
	function on(event:String, listener:String->Void):NodeReadableStream;
}

@:jsRequire("node:child_process")
extern class ChildProcess {
	static function spawn(command:String, args:Array<String>, ?options:SpawnOptions):ChildProcessHandle;
	static function spawnSync(command:String, args:Array<String>, ?options:SpawnSyncOptions):SpawnSyncResult;
}
