package opencodehx.externs.hono;

import js.lib.Promise;

@:ts.type("string | undefined")
abstract HonoQueryValue(Dynamic) from Dynamic to Dynamic {}

typedef HonoRequest = {
	function json():Promise<Dynamic>;
	function param(name:String):String;
	function query(name:String):HonoQueryValue;
}

typedef HonoContext = {
	final req:HonoRequest;
	function json(payload:Dynamic, ?status:Int):Dynamic;
	function header(name:String, value:String):Void;
}

@:ts.type("import('hono').Handler<any, string, any, any> | import('hono').MiddlewareHandler<any, string, any, any>")
abstract HonoHandler(Dynamic) from Dynamic to Dynamic {}

@:jsRequire("hono", "Hono")
extern class Hono {
	function new();
	function get(path:String, handler:HonoHandler):Hono;
	function post(path:String, handler:HonoHandler):Hono;
	function delete(path:String, handler:HonoHandler):Hono;
	function route(path:String, app:Hono):Hono;
	function request(path:String, ?init:Dynamic):Promise<Dynamic>;
	final fetch:Dynamic;
}
