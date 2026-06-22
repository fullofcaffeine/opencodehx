package opencodehx.server;

import js.lib.Promise;
import opencodehx.sync.SyncRouteRuntime;

typedef ServerOptions = {
	final directory:String;
	final dbPath:String;
	@:optional final hostname:String;
	@:optional final syncTypes:Array<String>;
	@:optional final syncRuntime:SyncRouteRuntime;
}

typedef ServerListener = {
	final port:Int;
	final hostname:String;
	final url:String;
	final stop:(?close:Bool) -> Promise<Void>;
}
