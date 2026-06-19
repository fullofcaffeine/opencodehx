package opencodehx.externs.hono;

import genes.ts.Undefinable;
import haxe.extern.EitherType;
import js.lib.Error;
import opencodehx.externs.hono.Hono.HonoFetch;

typedef NodeAdaptorServerOptions = {
	final fetch:HonoFetch;
}

typedef NodeServerAddress = {
	final port:Int;
}

typedef NodeServerAddressValue = EitherType<String, NodeServerAddress>;
typedef NodeServerListener = EitherType<Error->Void, Void->Void>;
typedef NodeServerCloseCallback = Undefinable<Error>->Void;

typedef NodeServerShape = {
	function once(event:String, handler:NodeServerListener):NodeServerType;
	function off(event:String, handler:NodeServerListener):NodeServerType;
	function listen(port:Int, hostname:String):NodeServerType;
	function close(callback:NodeServerCloseCallback):Void;
	function address():Null<NodeServerAddressValue>;
	@:optional function closeAllConnections():Void;
	@:optional function closeIdleConnections():Void;
}

/**
 * Haxe-facing structural view of Hono's Node server.
 *
 * Why: `@hono/node-server` exposes a package-owned `ServerType` that must stay
 * visible to TypeScript consumers and to `@hono/node-ws`, but OpenCodeHX only
 * needs a small lifecycle subset. The abstract keeps the emitted TS type
 * canonical while letting Haxe call the known methods without a raw
 * `Syntax.code` block.
 */
@:ts.type("import('@hono/node-server').ServerType & { closeAllConnections?: () => void; closeIdleConnections?: () => void }")
@:forward(once, off, listen, close, address, closeAllConnections, closeIdleConnections)
abstract NodeServerType(NodeServerShape) from NodeServerShape to NodeServerShape {}

@:jsRequire("@hono/node-server")
extern class NodeServer {
	static function createAdaptorServer(options:NodeAdaptorServerOptions):NodeServerType;
}
