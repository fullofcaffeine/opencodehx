package opencodehx.server;

import genes.js.Async.await;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.Headers;
import js.html.Request;
import js.html.Response;
import js.html.URL;
import js.lib.Promise;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.externs.web.GlobalFetch.GlobalForwardFetchInit;
import opencodehx.externs.web.WebStreams.WebResponseStreams;
import opencodehx.sync.SyncRouteRuntime.SyncRouteKnownSeq;
import opencodehx.sync.WorkspaceSyncRuntime;

typedef WorkspaceProxyTarget = {
	final url:String;
	final headers:Null<DynamicAccess<String>>;
}

typedef WorkspaceProxyFetchFunction = (url:String, init:GlobalForwardFetchInit) -> Promise<Response>;

class WorkspaceProxy {
	static final HOP_HEADERS = [
		"connection",
		"keep-alive",
		"proxy-authenticate",
		"proxy-authorization",
		"proxy-connection",
		"te",
		"trailer",
		"transfer-encoding",
		"upgrade",
		"host",
	];

	static inline final SYNC_HEADER = "x-opencode-sync";

	public static function shouldServeLocal(method:String, path:String):Bool {
		if (path == "/session/status" || StringTools.startsWith(path, "/session/status/"))
			return false;
		if (method == "GET" && (path == "/session" || StringTools.startsWith(path, "/session/")))
			return true;
		return false;
	}

	public static function proxyUrl(target:String, requestUrl:String):String {
		final source = new URL(requestUrl);
		final next = new URL(target);
		next.pathname = '${trimTrailingSlash(next.pathname)}${source.pathname}';
		next.search = source.search;
		next.hash = source.hash;
		next.searchParams.delete("workspace");
		return next.href;
	}

	public static function websocketUrl(target:String):String {
		final next = new URL(target);
		if (next.protocol == "http:")
			next.protocol = "ws:";
		if (next.protocol == "https:")
			next.protocol = "wss:";
		return next.href;
	}

	public static function forwardingHeaders(request:Request, extra:Null<DynamicAccess<String>>):Headers {
		final out = new Headers(request.headers);
		for (key in HOP_HEADERS) {
			out.delete(key);
		}
		out.delete("accept-encoding");
		out.delete("x-opencode-directory");
		out.delete("x-opencode-workspace");
		if (extra != null) {
			for (key in extra.keys()) {
				out.set(key, extra.get(key));
			}
		}
		return out;
	}

	@:async
	public static function http(request:Request, workspaceID:String, target:WorkspaceProxyTarget, sync:WorkspaceSyncRuntime,
			?fetch:WorkspaceProxyFetchFunction):Promise<Response> {
		if (!sync.isSyncing(workspaceID)) {
			return new Response('broken sync connection for workspace: ${workspaceID}', {
				status: 503,
				headers: {"content-type": "text/plain; charset=utf-8"},
			});
		}

		final forward = fetch == null ? defaultFetch : fetch;
		final url = proxyUrl(target.url, request.url);
		final init = @:await forwardInit(request, target.headers);
		final response = @:await forward(url, init);
		final state = parseFence(response.headers);
		final headers = responseHeaders(response.headers);
		if (state.length > 0) {
			final fence = sync.waitForSyncFence(workspaceID, state);
			if (!fence.synced) {
				return new Response(fence.message, {
					status: 504,
					statusText: "Gateway Timeout",
					headers: {"content-type": "text/plain; charset=utf-8"},
				});
			}
		}
		// Response accepts a standard BodyInit, but the Haxe Web extern does not
		// connect ReadableStream<Uint8Array> to that union. Keep the cast local
		// to the proxy response boundary.
		return new Response(cast WebResponseStreams.body(response), {
			status: response.status,
			statusText: response.statusText,
			headers: headers,
		});
	}

	public static function parseFence(headers:Headers):Array<SyncRouteKnownSeq> {
		final raw:Null<String> = headers.get(SYNC_HEADER);
		if (raw == null || raw == "")
			return [];
		try {
			// `x-opencode-sync` is untrusted remote JSON. Keep the Dynamic value
			// inside this decoder and copy only string/int pairs into typed state.
			final parsed:Dynamic = Json.parse(raw);
			final out:Array<SyncRouteKnownSeq> = [];
			for (field in Reflect.fields(parsed)) {
				final value = Reflect.field(parsed, field);
				if (Std.isOfType(value, Int)) {
					out.push({aggregateID: field, seq: value});
				}
			}
			return out;
		} catch (_:Dynamic) {
			return [];
		}
	}

	static function responseHeaders(headers:Headers):Headers {
		final out = new Headers(headers);
		out.delete("content-encoding");
		out.delete("content-length");
		return out;
	}

	@:async
	static function forwardInit(request:Request, extra:Null<DynamicAccess<String>>):Promise<GlobalForwardFetchInit> {
		final method = request.method;
		final headers = forwardingHeaders(request, extra);
		if (method == "GET" || method == "HEAD") {
			return {
				method: method,
				headers: headers,
				redirect: "manual",
				signal: request.signal,
			};
		}
		return {
			method: method,
			headers: headers,
			body: @:await request.text(),
			redirect: "manual",
			signal: request.signal,
		};
	}

	static function defaultFetch(url:String, init:GlobalForwardFetchInit):Promise<Response> {
		return GlobalFetch.forwardResponse(url, init);
	}

	static function trimTrailingSlash(path:String):String {
		if (path.length > 1 && StringTools.endsWith(path, "/"))
			return path.substr(0, path.length - 1);
		return path;
	}
}
