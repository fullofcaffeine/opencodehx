package opencodehx.smoke;

import js.lib.Error;
import opencodehx.account.AccountRepo;
import opencodehx.account.AccountRepo.AccessToken;
import opencodehx.account.AccountRepo.AccountID;
import opencodehx.account.AccountRepo.OrgID;
import opencodehx.account.AccountRepo.RefreshToken;
import opencodehx.externs.node.Fs;
import opencodehx.externs.node.Os;
import opencodehx.host.node.NodePath;

class AccountSmoke {
	public static function run():Void {
		final root = Fs.mkdtempSync(NodePath.join(Os.tmpdir(), "opencodehx-account-"));
		try {
			withRepo(root, "empty", emptyListAndActive);
			withRepo(root, "persist", persistAndGet);
			withRepo(root, "normalize", normalizeUrl);
			withRepo(root, "active", persistSetsActive);
			withRepo(root, "list", listAccounts);
			withRepo(root, "remove", removeDeletes);
			withRepo(root, "use", useActiveOrg);
			withRepo(root, "token", persistToken);
			withRepo(root, "token-null", persistTokenWithoutExpiry);
			withRepo(root, "upsert", persistAccountUpserts);
			withRepo(root, "remove-active", removeClearsActive);
			withRepo(root, "missing", getRowMissing);
			Fs.rmSync(root, {recursive: true, force: true});
		} catch (error:Error) {
			Fs.rmSync(root, {recursive: true, force: true});
			throw error;
		}
	}

	static function withRepo(root:String, name:String, test:AccountRepo->Void):Void {
		final repo = new AccountRepo(NodePath.join(root, '${name}.db'));
		try {
			test(repo);
			repo.close();
		} catch (error:Error) {
			repo.close();
			throw error;
		}
	}

	static function emptyListAndActive(repo:AccountRepo):Void {
		eq(repo.list().length, 0, "account empty list");
		eq(repo.active(), null, "account empty active");
	}

	static function persistAndGet(repo:AccountRepo):Void {
		final id = AccountID.make("user-1");
		repo.persistAccount(account(id, "test@example.com", "https://control.example.com", "at_123", "rt_456", 1000, OrgID.make("org-1")));
		final row = require(repo.getRow(id), "account persisted row");
		eq(row.id.toString(), "user-1", "account persisted id");
		eq(row.email, "test@example.com", "account persisted email");
		final active = require(repo.active(), "account active after persist");
		eq(active.activeOrgID == null ? null : active.activeOrgID.toString(), "org-1", "account active org after persist");
	}

	static function normalizeUrl(repo:AccountRepo):Void {
		final id = AccountID.make("user-normalized");
		repo.persistAccount(account(id, "normal@example.com", "https://control.example.com/", "at_norm", "rt_norm", 1000, null));
		eq(require(repo.getRow(id), "account normalized row").url, "https://control.example.com", "account normalized row url");
		eq(require(repo.active(), "account normalized active").url, "https://control.example.com", "account normalized active url");
	}

	static function persistSetsActive(repo:AccountRepo):Void {
		final first = AccountID.make("active-first");
		final second = AccountID.make("active-second");
		repo.persistAccount(account(first, "first@example.com", "https://control.example.com", "at_1", "rt_1", 1000, OrgID.make("org-1")));
		repo.persistAccount(account(second, "second@example.com", "https://control.example.com", "at_2", "rt_2", 1000, OrgID.make("org-2")));
		final active = require(repo.active(), "account second active");
		eq(active.id.toString(), "active-second", "account last persist active id");
		eq(active.activeOrgID == null ? null : active.activeOrgID.toString(), "org-2", "account last persist active org");
	}

	static function listAccounts(repo:AccountRepo):Void {
		final first = AccountID.make("list-a");
		final second = AccountID.make("list-b");
		repo.persistAccount(account(first, "a@example.com", "https://control.example.com", "at_a", "rt_a", 1000, null));
		repo.persistAccount(account(second, "b@example.com", "https://control.example.com", "at_b", "rt_b", 1000, OrgID.make("org-list")));
		final emails = [for (item in repo.list()) item.email];
		emails.sort((left, right) -> left < right ? -1 : left > right ? 1 : 0);
		eq(emails.join(","), "a@example.com,b@example.com", "account list emails");
	}

	static function removeDeletes(repo:AccountRepo):Void {
		final id = AccountID.make("remove-user");
		repo.persistAccount(account(id, "remove@example.com", "https://control.example.com", "at_r", "rt_r", 1000, null));
		repo.remove(id);
		eq(repo.getRow(id), null, "account removed row");
	}

	static function useActiveOrg(repo:AccountRepo):Void {
		final first = AccountID.make("use-first");
		final second = AccountID.make("use-second");
		repo.persistAccount(account(first, "use1@example.com", "https://control.example.com", "at_u1", "rt_u1", 1000, null));
		repo.persistAccount(account(second, "use2@example.com", "https://control.example.com", "at_u2", "rt_u2", 1000, null));
		repo.use(first, OrgID.make("org-99"));
		final activeWithOrg = require(repo.active(), "account use active with org");
		eq(activeWithOrg.id.toString(), "use-first", "account use active id");
		eq(activeWithOrg.activeOrgID == null ? null : activeWithOrg.activeOrgID.toString(), "org-99", "account use active org");
		repo.use(first, null);
		eq(require(repo.active(), "account use active no org").activeOrgID, null, "account use clears org");
	}

	static function persistToken(repo:AccountRepo):Void {
		final id = AccountID.make("token-user");
		repo.persistAccount(account(id, "token@example.com", "https://control.example.com", "old_token", "old_refresh", 1000, null));
		repo.persistToken({
			accountID: id,
			accessToken: AccessToken.make("new_token"),
			refreshToken: RefreshToken.make("new_refresh"),
			expiry: 7200,
		});
		final row = require(repo.getRow(id), "account token row");
		eq(row.accessToken.toString(), "new_token", "account token access");
		eq(row.refreshToken.toString(), "new_refresh", "account token refresh");
		eq(row.tokenExpiry, 7200, "account token expiry");
	}

	static function persistTokenWithoutExpiry(repo:AccountRepo):Void {
		final id = AccountID.make("token-no-expiry-user");
		repo.persistAccount(account(id, "token-null@example.com", "https://control.example.com", "old_token", "old_refresh", 1000, null));
		repo.persistToken({
			accountID: id,
			accessToken: AccessToken.make("new_token"),
			refreshToken: RefreshToken.make("new_refresh"),
			expiry: null,
		});
		eq(require(repo.getRow(id), "account token null row").tokenExpiry, null, "account token expiry null");
	}

	static function persistAccountUpserts(repo:AccountRepo):Void {
		final id = AccountID.make("upsert-user");
		repo.persistAccount(account(id, "upsert@example.com", "https://control.example.com", "at_v1", "rt_v1", 1000, OrgID.make("org-1")));
		repo.persistAccount(account(id, "upsert@example.com", "https://control.example.com", "at_v2", "rt_v2", 2000, OrgID.make("org-2")));
		final matching = [for (item in repo.list()) if (item.id.toString() == "upsert-user") item];
		eq(matching.length, 1, "account upsert single row");
		eq(require(repo.getRow(id), "account upsert row").accessToken.toString(), "at_v2", "account upsert token");
		eq(require(repo.active(), "account upsert active").activeOrgID == null ? null : require(repo.active(), "account upsert active").activeOrgID.toString(),
			"org-2", "account upsert active org");
	}

	static function removeClearsActive(repo:AccountRepo):Void {
		final id = AccountID.make("remove-active-user");
		repo.persistAccount(account(id, "remove-active@example.com", "https://control.example.com", "at", "rt", 1000, OrgID.make("org-1")));
		repo.remove(id);
		eq(repo.active(), null, "account remove clears active");
	}

	static function getRowMissing(repo:AccountRepo):Void {
		eq(repo.getRow(AccountID.make("nope")), null, "account missing row");
	}

	static function account(id:AccountID, email:String, url:String, access:String, refresh:String, expiry:Float,
			orgID:Null<OrgID>):opencodehx.account.AccountRepo.PersistAccountInput {
		return {
			id: id,
			email: email,
			url: url,
			accessToken: AccessToken.make(access),
			refreshToken: RefreshToken.make(refresh),
			expiry: expiry,
			orgID: orgID,
		};
	}

	static function require<T>(value:Null<T>, label:String):T {
		if (value == null)
			throw new Error('${label} expected value');
		return value;
	}

	static function eq<T>(actual:T, expected:T, label:String):Void {
		if (actual != expected)
			throw new Error('$label expected ${expected} got ${actual}');
	}
}
