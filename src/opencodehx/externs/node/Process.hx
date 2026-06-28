package opencodehx.externs.node;

import haxe.DynamicAccess;
import opencodehx.externs.node.ChildProcess.NodeSignal;

/**
 * Small global `process` extern for the entrypoint's CLI/smoke plumbing.
 * Broader process behavior belongs in `host.node.NodeProcess`; this type only
 * exposes argv, stdio writes, and exitCode so `Main` does not need raw JS.
 */
@:native("process")
extern class Process {
	static final argv:Array<String>;
	static final stdout:NodeWritableStream;
	static final stderr:NodeWritableStream;
	static var exitCode:Int;
	static final env:DynamicAccess<String>;
	static final platform:String;
	static function cwd():String;
	static function chdir(path:String):Void;
	static function kill(pid:Int, signal:NodeSignal):Void;
}

extern class NodeWritableStream {
	function write(value:String):Void;
	function end():Void;
}
