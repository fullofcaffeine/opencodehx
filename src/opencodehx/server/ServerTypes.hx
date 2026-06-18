package opencodehx.server;

import js.lib.Promise;

typedef ServerOptions = {
	final directory:String;
	final dbPath:String;
	@:optional final hostname:String;
}

typedef ServerListener = {
	final port:Int;
	final hostname:String;
	final url:String;
	final stop:(?close:Bool) -> Promise<Void>;
}
