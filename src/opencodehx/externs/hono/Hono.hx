package opencodehx.externs.hono;

import genes.ts.Unknown;
import genes.ts.Undefinable;
import haxe.extern.EitherType;
import js.html.Request;
import js.html.Response;
import js.html.RequestInit;
import js.lib.Promise;

typedef HonoFetch = Request->EitherType<Response, Promise<Response>>;
typedef HonoQueryValue = Undefinable<String>;

typedef HonoRequest = {
	function json():Promise<Unknown>;
	function param(name:String):HonoQueryValue;
	function query(name:String):HonoQueryValue;
	function header(name:String):HonoQueryValue;
}

typedef HonoContext = {
	final req:HonoRequest;
	function json<T>(payload:T, ?status:Int):Response;
	function header(name:String, value:String):Void;
}

/**
 * Narrow temporary route-handler bridge for Hono's overloaded handler surface.
 *
 * Hono accepts several structurally compatible function shapes whose generic
 * parameters are still being modeled in this port. Keep the Dynamic contained
 * here while application route functions expose typed request/response DTOs.
 */
@:ts.type("import('hono').Handler<any, string, any, any> | import('hono').MiddlewareHandler<any, string, any, any>")
abstract HonoHandler(Dynamic) from Dynamic to Dynamic {}

@:jsRequire("hono", "Hono")
extern class Hono {
	function new();
	function get(path:String, handler:HonoHandler):Hono;
	function post(path:String, handler:HonoHandler):Hono;
	function patch(path:String, handler:HonoHandler):Hono;
	function put(path:String, handler:HonoHandler):Hono;
	function delete(path:String, handler:HonoHandler):Hono;
	function route(path:String, app:Hono):Hono;
	function request(path:String, ?init:RequestInit):Promise<Response>;
	final fetch:HonoFetch;
}
