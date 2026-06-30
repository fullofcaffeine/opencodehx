package opencodehx.account;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownArray;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import js.html.URL;
import js.lib.Error;
import js.lib.Promise;
import opencodehx.account.AccountError.AccountServiceError;
import opencodehx.account.AccountError.AccountTransportError;
import opencodehx.account.AccountRepo.AccessToken;
import opencodehx.account.AccountRepo.AccountID;
import opencodehx.account.AccountRepo.AccountInfo;
import opencodehx.account.AccountRepo.AccountRow;
import opencodehx.account.AccountRepo.OrgID;
import opencodehx.account.AccountRepo.RefreshToken;

typedef AccountHttpHeader = {
	final name:String;
	final value:String;
}

typedef AccountHttpRequest = {
	final method:String;
	final url:String;
	final headers:Array<AccountHttpHeader>;
}

typedef AccountHttpResponse = {
	final status:Int;
	final body:Unknown;
}

typedef AccountHttpClient = AccountHttpRequest->Promise<AccountHttpResponse>;

typedef AccountOrg = {
	final id:OrgID;
	final name:String;
}

typedef AccountOrgs = {
	final account:AccountInfo;
	final orgs:Array<AccountOrg>;
}

typedef AccountLogin = {
	final code:String;
	final user:String;
	final url:String;
	final server:String;
	final expiryMs:Float;
	final intervalMs:Float;
}

enum AccountPollResult {
	PollSuccess(email:String);
	PollPending;
	PollSlow;
	PollExpired;
	PollDenied;
	PollError(cause:String);
}

/**
	Credential-free account service slice over a typed repository and HTTP seam.

	This ports the deterministic account/service behavior that can be proven with
	an injected HTTP client. Eager token refresh, refresh coalescing, and live
	CLI account side effects remain separate account-service work.
**/
class AccountService {
	static inline final CLIENT_ID = "opencode-cli";

	final repo:AccountRepo;
	final http:AccountHttpClient;

	public function new(repo:AccountRepo, http:AccountHttpClient) {
		this.repo = repo;
		this.http = http;
	}

	@:async
	public function login(server:String):Promise<AccountLogin> {
		final normalized = normalizeServerUrl(server);
		final response = @:await execute({
			method: "POST",
			url: normalized + "/auth/device/code",
			headers: [{name: "accept", value: "application/json"}],
		});
		requireOk(response, "Account login failed");
		final body = record(response.body, "account login response");
		final verification = requireString(body, "verification_uri_complete", "account login verification");
		final expires = requireNumber(body, "expires_in", "account login expires");
		final interval = requireNumber(body, "interval", "account login interval");
		return {
			code: requireString(body, "device_code", "account login device code"),
			user: requireString(body, "user_code", "account login user code"),
			url: normalized + verification,
			server: normalized,
			expiryMs: expires * 1000,
			intervalMs: interval * 1000,
		};
	}

	@:async
	public function orgsByAccount():Promise<Array<AccountOrgs>> {
		final out:Array<AccountOrgs> = [];
		for (account in repo.list()) {
			final orgs = @:await orgs(account.id);
			out.push({account: account, orgs: orgs});
		}
		return out;
	}

	@:async
	public function orgs(accountID:AccountID):Promise<Array<AccountOrg>> {
		final row = repo.getRow(accountID);
		if (row == null)
			return [];
		final response = @:await execute({
			method: "GET",
			url: row.url + "/api/orgs",
			headers: authHeaders(row.accessToken, null),
		});
		requireOk(response, "Account org fetch failed");
		return decodeOrgs(response.body);
	}

	@:async
	public function config(accountID:AccountID, orgID:OrgID):Promise<Null<UnknownRecord>> {
		final row = repo.getRow(accountID);
		if (row == null)
			return null;
		final response = @:await execute({
			method: "GET",
			url: row.url + "/api/config",
			headers: authHeaders(row.accessToken, orgID),
		});
		if (response.status == 404)
			return null;
		requireOk(response, "Account config fetch failed");
		final root = record(response.body, "account config response");
		return UnknownNarrow.record(root.get("config"));
	}

	@:async
	public function poll(input:AccountLogin):Promise<AccountPollResult> {
		final tokenResponse = @:await execute({
			method: "POST",
			url: input.server + "/auth/device/token",
			headers: [{name: "accept", value: "application/json"}],
		});
		final tokenBody = record(tokenResponse.body, "account poll token response");
		if (tokenResponse.status != 200)
			return pollError(tokenBody);

		final access = AccessToken.make(requireString(tokenBody, "access_token", "account poll access token"));
		final refresh = RefreshToken.make(requireString(tokenBody, "refresh_token", "account poll refresh token"));
		final expires = requireNumber(tokenBody, "expires_in", "account poll expires");
		final user = @:await fetchUser(input.server, access);
		final remoteOrgs = @:await fetchOrgs(input.server, access);
		final firstOrg = remoteOrgs.length == 0 ? null : remoteOrgs[0].id;
		repo.persistAccount({
			id: user.id,
			email: user.email,
			url: input.server,
			accessToken: access,
			refreshToken: refresh,
			expiry: Date.now().getTime() + expires * 1000,
			orgID: firstOrg,
		});
		return PollSuccess(user.email);
	}

	@:async
	function execute(request:AccountHttpRequest):Promise<AccountHttpResponse> {
		try {
			return @:await http(request);
		} catch (error:Error) {
			throw new AccountTransportError({
				method: request.method,
				url: request.url,
				description: error.message,
			});
		}
	}

	@:async
	function fetchUser(server:String, access:AccessToken):Promise<{final id:AccountID; final email:String;}> {
		final response = @:await execute({
			method: "GET",
			url: server + "/api/user",
			headers: authHeaders(access, null),
		});
		requireOk(response, "Account user fetch failed");
		final body = record(response.body, "account user response");
		return {
			id: AccountID.make(requireString(body, "id", "account user id")),
			email: requireString(body, "email", "account user email"),
		};
	}

	@:async
	function fetchOrgs(server:String, access:AccessToken):Promise<Array<AccountOrg>> {
		final response = @:await execute({
			method: "GET",
			url: server + "/api/orgs",
			headers: authHeaders(access, null),
		});
		requireOk(response, "Account org fetch failed");
		return decodeOrgs(response.body);
	}

	static function pollError(body:UnknownRecord):AccountPollResult {
		final error = requireString(body, "error", "account poll error");
		return switch error {
			case "authorization_pending": PollPending;
			case "slow_down": PollSlow;
			case "expired_token": PollExpired;
			case "access_denied": PollDenied;
			case _: PollError(error);
		}
	}

	static function authHeaders(access:AccessToken, orgID:Null<OrgID>):Array<AccountHttpHeader> {
		final headers:Array<AccountHttpHeader> = [
			{name: "accept", value: "application/json"},
			{name: "authorization", value: "Bearer " + access.toString()},
		];
		if (orgID != null)
			headers.push({name: "x-org-id", value: orgID.toString()});
		return headers;
	}

	static function decodeOrgs(body:Unknown):Array<AccountOrg> {
		final items = array(body, "account org response");
		final out:Array<AccountOrg> = [];
		for (index in 0...items.length) {
			final item = record(items.get(index), 'account org ${index}');
			out.push({
				id: OrgID.make(requireString(item, "id", 'account org ${index} id')),
				name: requireString(item, "name", 'account org ${index} name'),
			});
		}
		return out;
	}

	static function requireOk(response:AccountHttpResponse, label:String):Void {
		if (response.status < 200 || response.status >= 300)
			throw new AccountServiceError('${label}: HTTP ${response.status}');
	}

	static function record(raw:Unknown, label:String):UnknownRecord {
		final out = UnknownNarrow.record(raw);
		if (out == null)
			throw new AccountServiceError('${label}: expected object');
		return out;
	}

	static function array(raw:Unknown, label:String):UnknownArray {
		final out = UnknownNarrow.array(raw);
		if (out == null)
			throw new AccountServiceError('${label}: expected array');
		return out;
	}

	static function requireString(record:UnknownRecord, field:String, label:String):String {
		final value = UnknownNarrow.string(record.get(field));
		if (value == null)
			throw new AccountServiceError('${label}: missing ${field}');
		return value;
	}

	static function requireNumber(record:UnknownRecord, field:String, label:String):Float {
		final value = UnknownNarrow.number(record.get(field));
		if (value == null)
			throw new AccountServiceError('${label}: missing ${field}');
		return value;
	}

	public static function normalizeServerUrl(input:String):String {
		final url = new URL(input);
		url.search = "";
		url.hash = "";
		var path = url.pathname;
		while (path.length > 0 && path.charAt(path.length - 1) == "/")
			path = path.substr(0, path.length - 1);
		return path.length == 0 ? url.origin : url.origin + path;
	}
}
