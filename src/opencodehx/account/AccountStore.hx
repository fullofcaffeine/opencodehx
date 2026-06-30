package opencodehx.account;

import genes.js.Async.await;
import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import haxe.DynamicAccess;
import js.lib.Promise;
import opencodehx.config.ConfigLoader.AccountRemoteConfig;
import opencodehx.externs.node.Fs;
import opencodehx.externs.web.Fetch;
import opencodehx.externs.web.Fetch.AccountConfigPayload;
import opencodehx.host.node.BetterSqlite;
import opencodehx.storage.StorageDatabasePath;

using StringTools;

typedef ActiveAccountRow = {
	final id:String;
	final email:String;
	final url:String;
	final accessToken:String;
	final activeOrgID:String;
}

/**
	Read-only account config bridge for the live CLI path.

	This intentionally is not the full upstream account service. It reads the
	active account selection from OpenCode's SQLite tables and fetches `/api/config`
	with the selected org header. Login, token refresh, and account mutation belong
	to a later account-service port.
**/
class AccountStore {
	@:async
	public static function loadRemoteConfigs(env:DynamicAccess<String>):Promise<Array<AccountRemoteConfig>> {
		final active = activeAccount(env);
		if (active == null)
			return [];
		try {
			final base = normalizeBaseUrl(active.url);
			final response = @:await Fetch.fetchAccountConfig(base + "/api/config", {
				headers: requestHeaders(active),
			});
			if (!response.ok)
				return [];
			final payload:AccountConfigPayload = @:await response.json();
			if (payload.config == null)
				return [];
			return [
				{
					url: base,
					token: active.accessToken,
					config: payload.config,
				}
			];
		} catch (_:Dynamic) {
			// Upstream treats remote account config as best-effort and logs debug
			// failures. Dynamic is required because host fetch/SQLite failures can
			// throw JS-native values that do not share a Haxe exception type.
			return [];
		}
	}

	static function activeAccount(env:DynamicAccess<String>):Null<ActiveAccountRow> {
		final path = databasePath(env);
		if (!Fs.existsSync(path))
			return null;
		var sql:Null<BetterSqlite> = null;
		try {
			sql = new BetterSqlite(path);
			final row = sql.get("select account.id as id, account.email as email, account.url as url, account.access_token as accessToken, account_state.active_org_id as activeOrgID from account_state join account on account.id = account_state.active_account_id where account_state.id = 1");
			final active = decodeActiveRow(Unknown.fromBoundary(row));
			sql.close();
			return active;
		} catch (_:Dynamic) {
			if (sql != null)
				sql.close();
			// Missing tables, older databases, and native SQLite errors should not
			// block local config loading. The account config fetch is optional.
			return null;
		}
	}

	static function decodeActiveRow(value:Unknown):Null<ActiveAccountRow> {
		final record = UnknownNarrow.record(value);
		if (record == null)
			return null;
		final id = fieldString(record, "id");
		final email = fieldString(record, "email");
		final url = fieldString(record, "url");
		final accessToken = fieldString(record, "accessToken");
		final activeOrgID = fieldString(record, "activeOrgID");
		if (id == null || email == null || url == null || accessToken == null || activeOrgID == null)
			return null;
		return {
			id: id,
			email: email,
			url: url,
			accessToken: accessToken,
			activeOrgID: activeOrgID,
		};
	}

	static function requestHeaders(account:ActiveAccountRow):DynamicAccess<String> {
		final headers = new DynamicAccess<String>();
		headers.set("authorization", "Bearer " + account.accessToken);
		headers.set("x-org-id", account.activeOrgID);
		return headers;
	}

	static function databasePath(env:DynamicAccess<String>):String {
		return StorageDatabasePath.path(env, "latest");
	}

	static function normalizeBaseUrl(value:String):String {
		var out = value;
		while (out.length > 1 && out.endsWith("/"))
			out = out.substr(0, out.length - 1);
		return out;
	}

	static function fieldString(record:UnknownRecord, field:String):Null<String> {
		return UnknownNarrow.string(record.get(field));
	}
}
