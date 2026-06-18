package opencodehx.externs.hono;

@:ts.type("import('@hono/node-server').ServerType")
abstract NodeServerType(Dynamic) from Dynamic to Dynamic {}

@:jsRequire("@hono/node-server")
extern class NodeServer {
	static function createAdaptorServer(options:Dynamic):NodeServerType;
}
