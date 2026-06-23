package opencodehx.server;

import haxe.DynamicAccess;
import js.html.URL;

typedef ServerTraceRequest = {
	final method:String;
	final url:String;
	final params:DynamicAccess<String>;
}

class ServerTrace {
	public static function paramToAttributeKey(param:String):String {
		if (StringTools.endsWith(param, "ID") && param.length > 2)
			return '${param.substr(0, param.length - 2)}.id';
		return 'opencode.${param}';
	}

	public static function requestAttributes(request:ServerTraceRequest):DynamicAccess<String> {
		final attrs = new DynamicAccess<String>();
		attrs.set("http.method", request.method);
		attrs.set("http.path", pathOnly(request.url));
		for (param in request.params.keys()) {
			attrs.set(paramToAttributeKey(param), request.params.get(param));
		}
		return attrs;
	}

	static function pathOnly(url:String):String {
		try {
			return new URL(url).pathname;
		} catch (_:Dynamic) {
			final query = url.indexOf("?");
			final hash = url.indexOf("#");
			final end = if (query == -1) hash; else if (hash == -1) query; else Std.int(Math.min(query, hash));
			return end == -1 ? url : url.substr(0, end);
		}
	}
}
