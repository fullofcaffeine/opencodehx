package opencodehx.account;

import genes.ts.Unknown;
import genes.ts.UnknownNarrow;
import genes.ts.UnknownRecord;
import opencodehx.host.node.BetterSqlite;

abstract AccountID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):AccountID {
		return new AccountID(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract OrgID(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):OrgID {
		return new OrgID(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract AccessToken(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):AccessToken {
		return new AccessToken(value);
	}

	public inline function toString():String {
		return this;
	}
}

abstract RefreshToken(String) from String to String {
	public inline function new(value:String) {
		this = value;
	}

	public static inline function make(value:String):RefreshToken {
		return new RefreshToken(value);
	}

	public inline function toString():String {
		return this;
	}
}

typedef AccountInfo = {
	final id:AccountID;
	final email:String;
	final url:String;
	final activeOrgID:Null<OrgID>;
}

typedef AccountRow = {
	final id:AccountID;
	final email:String;
	final url:String;
	final accessToken:AccessToken;
	final refreshToken:RefreshToken;
	final tokenExpiry:Null<Float>;
}

typedef PersistAccountInput = {
	final id:AccountID;
	final email:String;
	final url:String;
	final accessToken:AccessToken;
	final refreshToken:RefreshToken;
	final expiry:Float;
	final orgID:Null<OrgID>;
}

typedef PersistTokenInput = {
	final accountID:AccountID;
	final accessToken:AccessToken;
	final refreshToken:RefreshToken;
	final expiry:Null<Float>;
}

/**
	SQLite-backed account repository for upstream account/repo parity.

	This owns the account table/state semantics used by local account-backed
	config loading. The higher-level HTTP account service, device login, token
	refresh scheduling, and org/config fetching stay outside this repository.
**/
class AccountRepo {
	static inline final ACCOUNT_STATE_ID = 1;

	final sql:BetterSqlite;

	public function new(path:String) {
		sql = new BetterSqlite(path);
		sql.pragma("foreign_keys = ON");
		sql.pragma("busy_timeout = 5000");
		createSchema();
	}

	public function close():Void {
		sql.close();
	}

	public function active():Null<AccountInfo> {
		final row = activeRow();
		return row == null ? null : infoFromRow(row, nullableString(row, "active_org_id"));
	}

	public function list():Array<AccountInfo> {
		final rows = sql.all("select id, email, url, access_token, refresh_token, token_expiry from account");
		final accounts:Array<AccountInfo> = [];
		for (row in rows)
			accounts.push(infoFromRow(record(row), null));
		return accounts;
	}

	public function getRow(id:AccountID):Null<AccountRow> {
		final row = sql.get("select id, email, url, access_token, refresh_token, token_expiry from account where id = ?", [id.toString()]);
		return row == null ? null : accountRowFromRecord(record(row));
	}

	public function persistAccount(input:PersistAccountInput):Void {
		final url = normalizeServerUrl(input.url);
		sql.transaction(() -> {
			sql.run("insert into account (id, email, url, access_token, refresh_token, token_expiry) values (?, ?, ?, ?, ?, ?) on conflict(id) do update set email = excluded.email, url = excluded.url, access_token = excluded.access_token, refresh_token = excluded.refresh_token, token_expiry = excluded.token_expiry",
				[
					input.id.toString(),
					input.email,
					url,
					input.accessToken.toString(),
					input.refreshToken.toString(),
					input.expiry,
				],);
			setActive(input.id, input.orgID);
		});
	}

	public function persistToken(input:PersistTokenInput):Void {
		sql.run("update account set access_token = ?, refresh_token = ?, token_expiry = ? where id = ?", [
			input.accessToken.toString(),
			input.refreshToken.toString(),
			input.expiry,
			input.accountID.toString(),
		],);
	}

	public function remove(id:AccountID):Void {
		sql.transaction(() -> {
			sql.run("update account_state set active_account_id = null, active_org_id = null where active_account_id = ?", [id.toString()]);
			sql.run("delete from account where id = ?", [id.toString()]);
		});
	}

	public function use(id:AccountID, orgID:Null<OrgID>):Void {
		setActive(id, orgID);
	}

	function setActive(id:AccountID, orgID:Null<OrgID>):Void {
		sql.run("insert into account_state (id, active_account_id, active_org_id) values (?, ?, ?) on conflict(id) do update set active_account_id = excluded.active_account_id, active_org_id = excluded.active_org_id",
			[ACCOUNT_STATE_ID, id.toString(), orgID == null ? null : orgID.toString(),],);
	}

	function activeRow():Null<UnknownRecord> {
		final row = sql.get("select account.id as id, account.email as email, account.url as url, account.access_token as access_token, account.refresh_token as refresh_token, account.token_expiry as token_expiry, account_state.active_org_id as active_org_id from account_state join account on account.id = account_state.active_account_id where account_state.id = ?",
			[ACCOUNT_STATE_ID],);
		return row == null ? null : record(row);
	}

	function createSchema():Void {
		sql.exec("
			create table if not exists account (
				id text primary key,
				email text not null,
				url text not null,
				access_token text not null,
				refresh_token text not null,
				token_expiry integer,
				time_created integer,
				time_updated integer
			);
			create table if not exists account_state (
				id integer primary key,
				active_account_id text references account(id) on delete set null,
				active_org_id text
			);
		");
	}

	static function accountRowFromRecord(row:UnknownRecord):AccountRow {
		return {
			id: AccountID.make(requiredString(row, "id")),
			email: requiredString(row, "email"),
			url: requiredString(row, "url"),
			accessToken: AccessToken.make(requiredString(row, "access_token")),
			refreshToken: RefreshToken.make(requiredString(row, "refresh_token")),
			tokenExpiry: nullableNumber(row, "token_expiry"),
		};
	}

	static function infoFromRow(row:UnknownRecord, activeOrgID:Null<String>):AccountInfo {
		return {
			id: AccountID.make(requiredString(row, "id")),
			email: requiredString(row, "email"),
			url: requiredString(row, "url"),
			activeOrgID: activeOrgID == null ? null : OrgID.make(activeOrgID),
		};
	}

	static function record(row:Unknown):UnknownRecord {
		final out = UnknownNarrow.record(row);
		if (out == null)
			throw 'account row expected object';
		return out;
	}

	static function requiredString(row:UnknownRecord, field:String):String {
		final value = UnknownNarrow.string(row.get(field));
		if (value == null)
			throw 'account row missing string ${field}';
		return value;
	}

	static function nullableString(row:UnknownRecord, field:String):Null<String> {
		final value = row.get(field);
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value) ? null : UnknownNarrow.string(value);
	}

	static function nullableNumber(row:UnknownRecord, field:String):Null<Float> {
		final value = row.get(field);
		return UnknownNarrow.isNull(value) || UnknownNarrow.isUndefined(value) ? null : UnknownNarrow.number(value);
	}

	static function normalizeServerUrl(value:String):String {
		var out = value;
		while (out.length > 1 && out.charAt(out.length - 1) == "/")
			out = out.substr(0, out.length - 1);
		return out;
	}
}
