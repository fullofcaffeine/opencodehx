package opencodehx.externs.node;

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
}

extern class NodeWritableStream {
	function write(value:String):Void;
}
