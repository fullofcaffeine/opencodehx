# Account Repo Parity

**Bead:** `opencodehx-26bn`
**Upstream oracle:** `../opencode/packages/opencode/src/account/{repo.ts,account.sql.ts,schema.ts,url.ts}` and `../opencode/packages/opencode/test/account/repo.test.ts`.

## Slice

`opencodehx.account.AccountRepo` is the first Haxe-owned account repository seam. It uses the existing `BetterSqlite` host facade, creates the upstream `account` and `account_state` tables, and models account IDs, org IDs, access tokens, and refresh tokens as typed Haxe abstracts.

Covered behavior:

- empty account list and active-account lookup
- account insert/get-row
- trailing-slash server URL normalization before storage
- active account/org state after account persistence
- account listing
- account removal and active-state clearing
- explicit active-account/org selection
- token field update with and without expiry
- account upsert on ID conflict
- missing-row lookup

## Evidence

`AccountSmoke` runs through the default `npm run smoke` path and exercises those cases against an isolated temp SQLite database.

This is not the full upstream account service. Device login, polling, eager token refresh, org/config HTTP fetches, service-layer error mapping, and live CLI account side effects remain in `account/service.test.ts` and the account/provider follow-up backlog.
