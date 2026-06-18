package opencodehx.externs.web;

import haxe.DynamicAccess;
import haxe.extern.EitherType;
import js.html.Request;
import js.html.Response;
import js.html.URL;
import js.lib.Promise;
import opencodehx.config.ConfigInfo.OpenConfigValue;

typedef FetchInput = EitherType<String, EitherType<URL, Request>>;
typedef FetchFunction = FetchInput->Promise<Response>;
typedef RemoteConfigObject = DynamicAccess<OpenConfigValue>;

typedef WellKnownPayload = {
	@:optional final config:RemoteConfigObject;
}

extern typedef FetchResponse = {
	final ok:Bool;
	final status:Int;
	function json():Promise<WellKnownPayload>;
}

class Fetch {
	public static inline function fetch(url:String):Promise<FetchResponse> {
		return js.Syntax.code("fetch({0})", url);
	}
}
