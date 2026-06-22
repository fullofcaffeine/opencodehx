package opencodehx.externs.web;

import genes.ts.Unknown;
import js.lib.Promise;
import opencodehx.externs.web.Fetch.AccountConfigResponse;
import opencodehx.externs.web.Fetch.FetchInit;
import opencodehx.externs.web.Fetch.FetchResponse;

extern typedef UnknownJsonFetchResponse = {
	final ok:Bool;
	final status:Int;
	function text():Promise<String>;
	function json():Promise<Unknown>;
}

/**
 * Narrow global `fetch` entry points used by NodeNext/browser-compatible host
 * seams.
 *
 * The response body type is intentionally chosen by the caller-specific
 * wrapper: config loaders use typed payload DTOs, while generic remote skill
 * discovery receives JSON as `Unknown` and decodes it itself.
 */
@:native("globalThis")
extern class GlobalFetch {
	@:native("fetch")
	static function config(url:String):Promise<FetchResponse>;

	@:native("fetch")
	static function accountConfig(url:String, init:FetchInit):Promise<AccountConfigResponse>;

	@:native("fetch")
	static function unknownJson(url:String):Promise<UnknownJsonFetchResponse>;
}
