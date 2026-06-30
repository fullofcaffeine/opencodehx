# PTY Runtime

**Beads:** `opencodehx-3qi`, `opencodehx-m5b`, `opencodehx-o48`, `opencodehx-000.11.17`
**Upstream oracle:** `../opencode/packages/opencode/src/pty/index.ts`, `../opencode/packages/opencode/src/pty/pty.node.ts`, `../opencode/packages/opencode/test/pty/*.test.ts`

## Slice

OpenCodeHX now has a real Node PTY lifecycle and WebSocket interaction seam:

- `opencodehx.pty.PtyService` owns active PTY sessions, generated `pty_` IDs, titles, status, command, args, cwd, pid, and lifecycle events.
- `opencodehx.externs.node.NodePty` binds the used subset of `@lydell/node-pty`.
- `PtyService.create()` uses the typed shell-argument helper to add `-l` for login shells, sets upstream terminal environment variables, spawns a real pseudo-terminal, and publishes `pty.created`.
- PTY exit publishes `pty.exited` then removes the session and publishes `pty.deleted`.
- Explicit `remove()` on a running PTY publishes the same created/exited/deleted lifecycle order deterministically before teardown.
- `PtyService` buffers recent output, tracks a monotonic cursor, sends upstream-style `0x00 + JSON.stringify({cursor})` control frames on connect/replay, and chunks replay output.
- `connect()` returns typed message/close callbacks for route adapters and keys subscribers by the same `ws.data` object-identity rule upstream uses to prevent recycled socket wrappers from leaking output.
- `OpenCodeServer` exposes `/pty`, `/pty/:ptyID`, and `/pty/:ptyID/connect` routes for create/list/get/update/delete plus WebSocket write/replay/tail behavior.
- `PtyRouteProtocol` narrows create/update JSON bodies through `genes.ts.UnknownRecord`, `UnknownArray`, and `UnknownNarrow` before constructing `PtyCreateInput`/`PtyUpdateInput`; the only open object shape left on this route is the validated string env map passed to Node PTY.

## Evidence

Runtime smoke in `PtySmoke` covers:

- short-lived `/usr/bin/env sh -c "sleep 0.1"` lifecycle,
- long-lived `/bin/sh` create/remove lifecycle,
- shell-selection parity for `Shell.name`, `Shell.login`, `Shell.posix`, blacklisted Windows shells, Git Bash path normalization, `/usr/bin/bash` Git Bash resolution, and bare PowerShell resolution,
- bash login argument insertion when `/bin/bash` exists,
- deterministic PTY shell args for Windows PowerShell and Git Bash without requiring a Windows host,
- Windows PTY shell argument parity through `npm run windows:shell:smoke`: available `pwsh`/`powershell` commands get no login args, while available Git Bash gets `-l`,
- buffered output replay and `cursor=-1` tail connections,
- subscriber isolation for reused WebSocket wrappers,
- Bun-style socket object recycling before reconnect,
- in-place `ws.data` mutation preserving the active connection.

Shell-selection parity for `Shell.preferred`/`Shell.acceptable`, Git Bash normalization, and PowerShell fallback is covered in `PtySmoke` through the shared `NodeProcess` host facade used by `PtyService.create()`.

`ServerSmoke` covers:

- PTY HTTP create/list/get/update/delete routes,
- real WebSocket connect through Hono/node-ws,
- writing to a PTY through a WebSocket message,
- replaying buffered output from `cursor=0`,
- tailing from `cursor=-1` without replaying old output.

`scripts/harness/package-smoke.mjs` now repeats the deterministic `cat`-backed PTY WebSocket path through the globally installed package binary, proving the packed server can create a PTY, echo WebSocket input, replay buffered output, tail without replay, and delete the PTY from a real listener.

Run:

```bash
npm run build
npm run smoke
```

## Boundary

This is still Node-first. Bun's `bun-pty` adapter, full Effect service integration, OpenAPI route metadata, and deeper native Windows PTY lifecycle coverage remain follow-up work.

`@lydell/node-pty` currently ships declarations that TypeScript cannot resolve through the package `exports` field. `types/lydell-node-pty.d.ts` is a local declaration bridge for the narrow API used here; remove it when the package exposes its own declarations correctly.
