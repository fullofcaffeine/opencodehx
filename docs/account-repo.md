# Account Repo And Service Parity

**Beads:** `opencodehx-26bn`, `opencodehx-p4yr`
**Upstream oracle:** `../opencode/packages/opencode/src/account/{repo.ts,account.sql.ts,schema.ts,url.ts,account.ts}` and `../opencode/packages/opencode/test/account/{repo,service}.test.ts`.

## Slice

`opencodehx.account.AccountRepo` is the first Haxe-owned account repository seam. It uses the existing `BetterSqlite` host facade, creates the upstream `account` and `account_state` tables, and models account IDs, org IDs, access tokens, and refresh tokens as typed Haxe abstracts.

`opencodehx.account.AccountService` is the first credential-free account service seam. It runs over `AccountRepo` and an injected typed HTTP client so service behavior can be proven without global fetch monkey-patching or live account credentials.

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
- login URL normalization and transport error mapping
- org fetching grouped by account
- config fetch authorization and selected-org headers
- device-poll success persistence with first org selection
- device-poll pending, slow, denied, expired, and generic error states

## Evidence

`AccountSmoke` runs through the default `npm run smoke` path. The sync fixtures exercise repository cases against isolated temp SQLite databases. The async fixtures exercise service cases through an injected HTTP client and produce the `account-async-smoke:ok` marker.

This is not the full upstream account service. Eager token refresh, token refresh persistence, concurrent config/token refresh coalescing, full Effect service layering, and live CLI account side effects remain in `account/service.test.ts` and the account/provider follow-up backlog.
