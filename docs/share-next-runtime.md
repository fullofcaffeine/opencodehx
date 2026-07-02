# ShareNext Runtime

**Bead:** `opencodehx-37pd`  
**Upstream oracle:** `../opencode/packages/opencode/src/share/share-next.ts` and `../opencode/packages/opencode/test/share/share-next.test.ts`

## Slice

This slice starts the ShareNext port with deterministic request-routing and injected-client persistence behavior that does not require live network or database services:

- `ShareNextRuntime.request(...)` uses the legacy `/api/share` API when no active org account exists.
- Legacy requests use configured enterprise URL when present, otherwise `https://opncd.ai`.
- Active org accounts use the console `/api/shares` API with typed `authorization` and `x-org-id` header entries.
- Missing active-account tokens fail before any request can be constructed.
- `ShareNextServiceRuntime.create(...)` posts to the selected create endpoint, persists the returned share by session ID, and exposes the persisted row.
- `ShareNextServiceRuntime.remove(...)` deletes the persisted row after a successful delete endpoint response and returns `false` when no share is persisted for the session.
- `ShareNextServiceRuntime.queueDiff(...)` keeps only the latest queued diff per shared session, and `flushSync(...)` posts one upstream-shaped `session_diff` payload with the persisted share secret.
- Non-OK create responses fail and do not persist a share.

`ShareSmoke` covers legacy enterprise URL, default legacy URL, active org account headers/endpoints, missing-token failure, create/remove persistence, request method/URL shape, latest-diff sync coalescing, missing-row removal, and non-OK create failure without persistence.

## Boundaries

This is not the full upstream ShareNext service yet. Full sync data gathering, delayed timer scheduling, event subscriptions, disabled-share flags, real database persistence, and live HTTP layer integration remain deferred to later share/runtime slices.

Headers are modeled as typed `{ name, value }` entries instead of a string-keyed map so Haxe callers use `ShareRequestHeaderName` and generated TypeScript stays free of broad maps or raw `any`.
