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
typedef FetchHeaders = DynamicAccess<String>;

typedef FetchInit = {
	@:optional final headers:FetchHeaders;
}

typedef WellKnownPayload = {
	@:optional final config:RemoteConfigObject;
}

typedef AccountConfigPayload = {
	@:optional final config:RemoteConfigObject;
}

extern typedef FetchResponse = {
	final ok:Bool;
	final status:Int;
	function json():Promise<WellKnownPayload>;
}

extern typedef AccountConfigResponse = {
	final ok:Bool;
	final status:Int;
	function json():Promise<AccountConfigPayload>;
}

class Fetch {
	public static inline function fetch(url:String):Promise<FetchResponse> {
		return GlobalFetch.config(url);
	}

	public static inline function fetchAccountConfig(url:String, init:FetchInit):Promise<AccountConfigResponse> {
		return GlobalFetch.accountConfig(url, init);
	}
}
