package opencodehx.externs.node;

import opencodehx.externs.node.ChildProcess.NodeReadableStream;

@:jsRequire("node:stream", "Readable")
extern class NodeReadable {
	static function from(chunks:Array<String>):NodeReadableStream;
}
