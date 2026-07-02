package opencodehx.share;

typedef ShareApi = {
	final create:String;
	final sync:String->String;
	final remove:String->String;
	final data:String->String;
}

enum abstract ShareRequestHeaderName(String) from String to String {
	var Authorization = "authorization";
	var OrgID = "x-org-id";
}

typedef ShareRequestHeader = {
	final name:ShareRequestHeaderName;
	final value:String;
}

typedef ShareRequest = {
	final headers:Array<ShareRequestHeader>;
	final api:ShareApi;
	final baseUrl:String;
}

typedef ShareActiveAccount = {
	final id:String;
	final url:String;
	@:optional final token:String;
	@:optional final activeOrgID:String;
}

typedef ShareRequestOptions = {
	@:optional final enterpriseUrl:String;
	@:optional final activeAccount:ShareActiveAccount;
}

typedef ShareRecord = {
	final sessionID:String;
	final id:String;
	final url:String;
	final secret:String;
}

typedef ShareHttpRequest = {
	final method:String;
	final url:String;
	final headers:Array<ShareRequestHeader>;
	final body:String;
}

typedef ShareHttpResponse = {
	final status:Int;
	@:optional final share:ShareCreateResponse;
}

typedef ShareCreateResponse = {
	final id:String;
	final url:String;
	final secret:String;
}

typedef ShareHttpClient = ShareHttpRequest->ShareHttpResponse;

/**
	Small typed model of upstream ShareNext request routing.

	This intentionally covers only the credential-free decision surface from
	`ShareNext.request`: choose legacy `/api/share` endpoints when no active org
	account exists, or org `/api/shares` endpoints with auth headers when an
	active org account is available. Network create/sync/remove persistence stays
	with the later ShareNext service slice.
**/
class ShareNextRuntime {
	public static inline final DEFAULT_BASE_URL = "https://opncd.ai";

	public static function request(options:ShareRequestOptions):ShareRequest {
		final active = options.activeAccount;
		if (active == null || active.activeOrgID == null || active.activeOrgID == "") {
			return {
				headers: [],
				api: api("share"),
				baseUrl: normalizeBaseUrl(options.enterpriseUrl == null
					|| options.enterpriseUrl == "" ? DEFAULT_BASE_URL : options.enterpriseUrl),
			};
		}

		if (active.token == null || active.token == "")
			throw "No active account token available for sharing";

		return {
			headers: [
				{name: Authorization, value: "Bearer " + active.token},
				{name: OrgID, value: active.activeOrgID},
			],
			api: api("shares"),
			baseUrl: normalizeBaseUrl(active.url),
		};
	}

	public static function header(request:ShareRequest, name:ShareRequestHeaderName):Null<String> {
		for (header in request.headers)
			if (header.name == name)
				return header.value;
		return null;
	}

	static function api(resource:String):ShareApi {
		return {
			create: '/api/${resource}',
			sync: shareID -> '/api/${resource}/${shareID}/sync',
			remove: shareID -> '/api/${resource}/${shareID}',
			data: shareID -> '/api/${resource}/${shareID}/data',
		};
	}

	static function normalizeBaseUrl(value:String):String {
		var out = value;
		while (out.length > 1 && StringTools.endsWith(out, "/"))
			out = out.substr(0, out.length - 1);
		return out;
	}
}

/**
	Injected-client model of ShareNext create/remove persistence.

	This intentionally stays in-memory and synchronous. The full upstream service
	uses Effect, HTTP layers, and SQL tables; this seam keeps the stable API,
	request, response, and persistence behavior testable without those layers.
**/
class ShareNextServiceRuntime {
	final requestInfo:ShareRequest;
	final client:ShareHttpClient;
	final records:Map<String, ShareRecord>;

	public function new(requestInfo:ShareRequest, client:ShareHttpClient) {
		this.requestInfo = requestInfo;
		this.client = client;
		records = new Map();
	}

	public function create(sessionID:String):ShareRecord {
		final response = client({
			method: "POST",
			url: requestInfo.baseUrl + requestInfo.api.create,
			headers: requestInfo.headers.copy(),
			body: "{}",
		});
		if (!ok(response.status) || response.share == null)
			throw 'Share create failed with status ${response.status}';

		final created = response.share;
		final record:ShareRecord = {
			sessionID: sessionID,
			id: created.id,
			url: created.url,
			secret: created.secret,
		};
		records.set(sessionID, record);
		return record;
	}

	public function remove(sessionID:String):Bool {
		final existing = records.get(sessionID);
		if (existing == null)
			return false;

		final response = client({
			method: "DELETE",
			url: requestInfo.baseUrl + requestInfo.api.remove(existing.id),
			headers: requestInfo.headers.copy(),
			body: "",
		});
		if (!ok(response.status))
			throw 'Share remove failed with status ${response.status}';

		records.remove(sessionID);
		return true;
	}

	public function get(sessionID:String):Null<ShareRecord> {
		return records.get(sessionID);
	}

	static function ok(status:Int):Bool {
		return status >= 200 && status < 300;
	}
}
