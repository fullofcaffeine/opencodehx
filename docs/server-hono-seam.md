# Server Hono Seam

**Bead:** `opencodehx-026`

## Upstream Oracle

Primary upstream evidence:

- `../opencode/packages/opencode/src/server/adapter.node.ts`
- `../opencode/packages/opencode/src/server/adapter.ts`
- `../opencode/packages/opencode/src/server/server.ts`
- `../opencode/packages/opencode/src/server/routes/instance/event.ts`
- `../opencode/packages/opencode/src/server/routes/instance/session.ts`
- `../opencode/packages/opencode/src/server/routes/instance/sync.ts`
- `../opencode/packages/opencode/src/server/routes/instance/tui.ts`
- `../opencode/packages/opencode/test/control-plane/sse.test.ts`
- `../opencode/packages/opencode/test/server/session-{actions,list,messages,select}.test.ts`

## What Landed

OpenCodeHX now has a first Node/Hono server seam:

- `opencodehx.externs.hono.Hono` defines the narrow context/request/handler surface used by current routes. It preserves Hono's real `req.param()`/`req.query()` boundary as `string | undefined` in generated TypeScript while route code normalizes it to `String`/`Null<String>`.
- `opencodehx.externs.hono.NodeWs` models `createNodeWebSocket()` as a typed `NodeWebSocketRuntime` instead of a broad `Dynamic` value.
- `opencodehx.externs.hono.NodeServer` models `createAdaptorServer()` as Hono's exported `ServerType` with a narrow Haxe structural method surface, so the adapter keeps TypeScript package assignability without hiding server lifecycle logic in `Syntax.code`.
- `opencodehx.server.NodeHonoAdapter` starts and stops the Node server in Haxe, injects WebSocket support, preserves upstream's port-0 behavior of trying `4096` before a random port, guards the TCP address shape, and structurally narrows optional Node close helpers.
- `opencodehx.server.OpenCodeServer` exposes a first route set: `/health`, `/event`, `/session` GET/POST, `/session/:sessionID/message`, `/session/:sessionID/abort`, `/sync/start`, `/sync/replay`, `/sync/history`, `/tui/select-session`, `/pty`, `/pty/:ptyID`, and `/pty/:ptyID/connect`.
- `opencodehx.smoke.ServerSmoke` covers in-memory `app.request()` routes, SSE text emission, cursor headers, bad/missing session cases, select-session validation, abort success, PTY HTTP routes, listener start/stop, and a real PTY WebSocket write/replay/tail flow.
- `opencodehx.sync.SyncRouteRuntime` decodes sync replay/history request bodies from `genes.ts.Unknown` into typed route records before route logic sees them. Raw sync event `data` remains `unknown` until the full SyncEvent schema/projector registry lands.

## Typing Lesson

Upstream TypeScript uses `any` in some server areas, especially open payload queues and proxy/schema forwarding, but the Node adapter does not require `any` for the WebSocket runtime or listener. OpenCodeHX should recover stronger Haxe types wherever current usage makes the shape knowable. If `genes-ts` emits noisy TypeScript from a good Haxe model, fix or track the compiler issue instead of weakening the port source.

`js.Syntax.code` is treated like `untyped`: it is allowed only as a small, justified boundary. The large raw `NodeHonoAdapter.listen` Promise block was replaced with Haxe over narrow externs, and the later `opencodehx-1le` audit retired the server-side SSE and PTY binary-frame raw snippets into typed Web facades. The current repo-wide classification lives in `syntax-code-audit.md`.

Remaining `Dynamic` values in this slice are boundary debt:

- JSON request bodies remain dynamic until each route gets its Zod/schema-equivalent Haxe decoder.
- JSON response payload helpers remain dynamic until route-specific response DTOs are ported.
- Non-PTY WebSocket/proxy callback payloads remain future boundary work; PTY WebSocket frames now narrow through `PtyService` and the server adapter before application logic sees them.
- `SessionInfo` title patching uses a temporary mutable cast because the storage DTO has final fields; this should move to a named copy/update helper with the fuller session model.

## Dependency Note

Upstream currently uses `@hono/node-server@1.19.11` and deprecated `@hono/node-ws@1.3.0`. OpenCodeHX uses `@hono/node-ws@1.3.0` to match the upstream adapter seam, but pins `@hono/node-server@1.19.13` because `npm audit` reports the earlier range as vulnerable.

## Deferred Scope

This is not full server parity yet. Remaining work includes Bus/AsyncQueue-backed events, OpenAPI middleware, request validation/error taxonomy, generated SDK compatibility, real session prompt/action routes, provider streams, auth/CORS/compression, workspace routing, daemon-style remote workspace background task side effects, workspace proxy integration, and Bun adapter parity.
