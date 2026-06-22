package opencodehx.sync;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import haxe.DynamicAccess;
import haxe.Json;
import js.html.AbortSignal;
import js.html.Response;
import js.html.URL;
import js.lib.Promise;
import js.lib.Uint8Array;
import opencodehx.externs.web.GlobalFetch;
import opencodehx.externs.web.WebStreams.WebReadableStream;
import opencodehx.externs.web.WebStreams.WebResponseStreams;
import opencodehx.sync.SyncRouteRuntime.SyncHistoryEvent;
import opencodehx.sync.SyncRouteRuntime.SyncReplayRequest;
import opencodehx.sync.SyncRouteRuntime.SyncRouteKnownSeq;

typedef WorkspaceSyncFetchInit = {
	final method:String;
	final headers:DynamicAccess<String>;
	@:optional final body:String;
	@:optional final signal:AbortSignal;
}

typedef WorkspaceSyncFetchFunction = (url:String, init:WorkspaceSyncFetchInit) -> Promise<Response>;

typedef WorkspaceSyncHistoryResult = {
	final url:String;
	final events:Array<SyncHistoryEvent>;
}

typedef WorkspaceSyncReplayResult = {
	final url:String;
	final sessionID:String;
}

class WorkspaceSyncHttpError extends haxe.Exception {
	public final status:Int;
	public final body:String;

	public function new(message:String, status:Int, body:String) {
		super(message);
		this.status = status;
		this.body = body;
	}
}

class WorkspaceSyncRemoteHttp {
	final fetch:WorkspaceSyncFetchFunction;

	public function new(?fetch:WorkspaceSyncFetchFunction) {
		this.fetch = fetch == null ? defaultFetch : fetch;
	}

	public static function route(base:String, path:String):String {
		final url = new URL(base);
		final trimmed = StringTools.endsWith(url.pathname, "/") ? url.pathname.substr(0, url.pathname.length - 1) : url.pathname;
		url.pathname = trimmed + path;
		url.search = "";
		url.hash = "";
		return url.href;
	}

	@:async
	public function connectSse(base:String, ?headers:DynamicAccess<String>, ?signal:AbortSignal):Promise<WebReadableStream<Uint8Array>> {
		final response = @:await fetch(route(base, "/global/event"), {
			method: "GET",
			headers: cloneHeaders(headers),
			signal: signal,
		});
		if (!response.ok)
			throw new WorkspaceSyncHttpError('Workspace sync HTTP failure: ${response.status}', response.status, "");
		final body = WebResponseStreams.body(response);
		if (body == null)
			throw new haxe.Exception("No response body from global sync");
		return body;
	}

	@:async
	public function syncHistory(base:String, headers:Null<DynamicAccess<String>>, known:Array<SyncRouteKnownSeq>,
			?signal:AbortSignal):Promise<WorkspaceSyncHistoryResult> {
		final requestHeaders = cloneHeaders(headers);
		requestHeaders.set("content-type", "application/json");
		final url = route(base, "/sync/history");
		final response = @:await fetch(url, {
			method: "POST",
			headers: requestHeaders,
			body: Json.stringify(knownSeqObject(known)),
			signal: signal,
		});
		if (!response.ok) {
			final body = @:await response.text();
			throw new WorkspaceSyncHttpError('Workspace history HTTP failure: ${response.status} ${body}', response.status, body);
		}
		final raw = Unknown.fromBoundary(@:await response.json());
		return {
			url: url,
			events: decodeHistory(raw),
		};
	}

	@:async
	public function replay(base:String, headers:Null<DynamicAccess<String>>, request:SyncReplayRequest,
			?signal:AbortSignal):Promise<WorkspaceSyncReplayResult> {
		final requestHeaders = cloneHeaders(headers);
		requestHeaders.set("content-type", "application/json");
		final url = route(base, "/sync/replay");
		final response = @:await fetch(url, {
			method: "POST",
			headers: requestHeaders,
			body: Json.stringify(request),
			signal: signal,
		});
		if (!response.ok) {
			final body = @:await response.text();
			throw new WorkspaceSyncHttpError('Workspace replay HTTP failure: ${response.status} ${body}', response.status, body);
		}
		final record = UnknownNarrow.record(Unknown.fromBoundary(@:await response.json()));
		final sessionID = record == null ? null : UnknownNarrow.string(record.get("sessionID"));
		if (sessionID == null)
			throw new haxe.Exception("Workspace replay response missing sessionID");
		return {
			url: url,
			sessionID: sessionID,
		};
	}

	static function defaultFetch(url:String, init:WorkspaceSyncFetchInit):Promise<Response> {
		return GlobalFetch.response(url, init);
	}

	static function cloneHeaders(source:Null<DynamicAccess<String>>):DynamicAccess<String> {
		final out = new DynamicAccess<String>();
		if (source != null) {
			for (key in source.keys())
				out.set(key, source.get(key));
		}
		return out;
	}

	static function knownSeqObject(known:Array<SyncRouteKnownSeq>):DynamicAccess<Int> {
		final out = new DynamicAccess<Int>();
		for (item in known)
			out.set(item.aggregateID, item.seq);
		return out;
	}

	static function decodeHistory(raw:Unknown):Array<SyncHistoryEvent> {
		final result:Array<SyncHistoryEvent> = [];
		switch SyncRouteRuntime.decodeHistoryEvents(raw) {
			case SyncDecoded(events):
				return events;
			case SyncRejected(_):
				return result;
		}
	}
}
