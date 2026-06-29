# ShareNext Runtime

**Bead:** `opencodehx-37pd`  
**Upstream oracle:** `../opencode/packages/opencode/src/share/share-next.ts` and `../opencode/packages/opencode/test/share/share-next.test.ts`

## Slice

This slice starts the ShareNext port with the request-routing decision that does not require live network or persistence:

- `ShareNextRuntime.request(...)` uses the legacy `/api/share` API when no active org account exists.
- Legacy requests use configured enterprise URL when present, otherwise `https://opncd.ai`.
- Active org accounts use the console `/api/shares` API with typed `authorization` and `x-org-id` header entries.
- Missing active-account tokens fail before any request can be constructed.

`ShareSmoke` covers legacy enterprise URL, default legacy URL, active org account headers/endpoints, and missing-token failure.

## Boundaries

This is not the full upstream ShareNext service yet. Create/remove persistence, full sync data gathering, delayed queue coalescing, event subscriptions, disabled-share flags, and HTTP response handling remain deferred to later share/runtime slices.

Headers are modeled as typed `{ name, value }` entries instead of a string-keyed map so Haxe callers use `ShareRequestHeaderName` and generated TypeScript stays free of broad maps or raw `any`.
