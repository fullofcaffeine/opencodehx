# PTY Runtime

**Bead:** `opencodehx-3qi`  
**Upstream oracle:** `../opencode/packages/opencode/src/pty/index.ts`, `../opencode/packages/opencode/src/pty/pty.node.ts`, `../opencode/packages/opencode/test/pty/*.test.ts`

## Slice

OpenCodeHX now has a first real Node PTY lifecycle seam:

- `opencodehx.pty.PtyService` owns active PTY sessions, generated `pty_` IDs, titles, status, command, args, cwd, pid, and lifecycle events.
- `opencodehx.externs.node.NodePty` binds the used subset of `@lydell/node-pty`.
- `PtyService.create()` adds `-l` for login shells, sets upstream terminal environment variables, spawns a real pseudo-terminal, and publishes `pty.created`.
- PTY exit publishes `pty.exited` then removes the session and publishes `pty.deleted`.
- Explicit `remove()` on a running PTY publishes the same created/exited/deleted lifecycle order deterministically before teardown.
- `resize`, `write`, `update`, `list`, `get`, and `dispose` are present as app-facing operations for later server/TUI routes.

## Evidence

Runtime smoke in `PtySmoke` covers:

- short-lived `/usr/bin/env sh -c "sleep 0.1"` lifecycle,
- long-lived `/bin/sh` create/remove lifecycle,
- bash login argument insertion when `/bin/bash` exists.

Run:

```bash
npm run build
npm run smoke
```

## Boundary

This is not the full upstream PTY WebSocket protocol yet. Output buffering, cursor control frames, subscriber isolation, server routes, WebSocket connect/write/resize controls, and Bun's `bun-pty` adapter remain follow-up work.

`@lydell/node-pty` currently ships declarations that TypeScript cannot resolve through the package `exports` field. `types/lydell-node-pty.d.ts` is a local declaration bridge for the narrow API used here; remove it when the package exposes its own declarations correctly.
