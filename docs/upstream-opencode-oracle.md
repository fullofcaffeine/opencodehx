# Upstream OpenCode Oracle Manifest

**Bead:** `opencodehx-004`  
**Recorded:** 2026-06-18T03:33:09Z  
**Machine-readable pin:** `reference/upstream-opencode.pin.json`

## Snapshot

OpenCodeHX uses the sibling checkout `../opencode` as the upstream behavioral oracle.

| Field | Value |
| --- | --- |
| Checkout | `../opencode` |
| Remote | `git@github.com:sst/opencode.git` |
| Branch | `dev` |
| Upstream ref | `origin/dev` |
| Commit | `69b7f3b8db82c3ab9dacd72d715a57d375de18e4` |
| Commit date | 2026-04-22T16:29:44Z |
| Commit subject | `chore: generate` |
| Package | `packages/opencode` |
| OpenCode version | `1.14.20` |
| Package manager | `bun@1.3.13` |
| Binary | `packages/opencode/bin/opencode` |

The local branch reports `ahead 16, behind 2471` relative to `origin/dev`, so the oracle is the exact commit above, not the moving remote branch. The working tree has no tracked changes; untracked repomix artifacts are present and ignored for oracle purposes.

## Source And Tests

| Surface | Path | Count |
| --- | --- | ---: |
| Source root | `../opencode/packages/opencode/src` | 523 files |
| Test root | `../opencode/packages/opencode/test` | 187 files |
| Source matrix | `reference/opencode-source-parity-matrix.csv` | 523 source rows |
| Test matrix | `reference/opencode-test-priority-matrix.csv` | 187 test rows |

Approximate source LOC at this snapshot: 98,796.

## Reference Commands

Run upstream package commands from `packages/opencode`, not the repo root:

```sh
cd ../opencode/packages/opencode
bun run typecheck
bun test --timeout 30000
bun run test:ci
bun run build
```

Root-level tests are intentionally disabled by upstream:

```sh
cd ../opencode
bun test
```

## Conditional Runtime Imports

OpenCode already defines runtime seams that OpenCodeHX should preserve:

| Alias | Bun | Node | Default |
| --- | --- | --- | --- |
| `#db` | `./src/storage/db.bun.ts` | `./src/storage/db.node.ts` | `./src/storage/db.bun.ts` |
| `#pty` | `./src/pty/pty.bun.ts` | `./src/pty/pty.node.ts` | `./src/pty/pty.bun.ts` |
| `#hono` | `./src/server/adapter.bun.ts` | `./src/server/adapter.node.ts` | `./src/server/adapter.bun.ts` |

## Oracle Policy

- Use this checkout for behavior, command output, source shape, tests, fixtures, and golden parity evidence.
- Do not edit `../opencode` from OpenCodeHX unless explicitly asked.
- Do not vendor or copy the full OpenCode source tree into OpenCodeHX by default.
- If upstream is refreshed later, follow [upstream-rebase-procedure.md](upstream-rebase-procedure.md): update `reference/upstream-opencode.pin.json`, regenerate the source/test matrices, and create Beads for any drift.
