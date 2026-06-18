# NPM Extern Strategy

**Bead:** `opencodehx-007`  
**Goal:** compile OpenCodeHX against the TypeScript/Node ecosystem without porting every npm dependency into Haxe.

## Policy

Use narrow typed externs and Haxe-facing facades around the APIs OpenCode actually uses. Do not port external npm libraries wholesale during the parity line.

Priority order:

1. **Host/build foundations:** Node built-ins, path/fs/process/streams, conditional runtime seams.
2. **Schema/config/session foundations:** `effect`, `zod`, `jsonc-parser`, `drizzle-orm`.
3. **Provider/server/tooling:** `ai`, `@ai-sdk/*`, `hono`, MCP/ACP SDKs, JSON-RPC, PTY.
4. **TUI:** `solid-js`, `@opentui/core`, `@opentui/solid`.
5. **Polish and package surfaces:** plugin SDK, GitHub/Copilot helpers, markdown/highlight dependencies, updater/install helpers.

Each extern should be one of:

- **Direct extern:** exact typed binding for a stable API call.
- **Facade extern:** small Haxe-owned interface over a dynamic or overloaded npm API.
- **Host seam:** Node/Bun-specific API hidden behind `opencodehx.host.*`.
- **Temporary dynamic boundary:** explicitly documented and tracked in `docs/genes-ts-limitation-ledger.md` or Beads.

## Required Coverage

| Family | Initial plan |
| --- | --- |
| Node built-ins | Create `opencodehx.externs.node.*` for used APIs; wrap host behavior under `opencodehx.host.*`. |
| `effect` | Add a dedicated `opencodehx.fx` plan and minimal extern/facade in `opencodehx-009`; do not reimplement Effect first. |
| `ai` / `@ai-sdk/*` | Start with fake provider DTOs, then narrow stream/tool-call facades for one real provider path. |
| `hono` | Bind only route/app/SSE/WebSocket APIs needed by OpenCode server parity. |
| `solid-js` / OpenTUI | Add TSX/HXX compiler fixtures before broad TUI externs; keep TUI externs separate from core runtime. |
| `drizzle-orm` | Prefer schema/query facades around existing storage seam; keep Bun/Node SQLite adapters separate. |
| `zod` | Use narrow validation/schema externs initially; consider Haxe schema derivation macros only after config/message shapes stabilize. |
| MCP/ACP SDKs | Bind protocol DTOs and client/server surfaces used by upstream tests first. |
| JSON-RPC / LSP | Bind process and message lifecycle under `opencodehx.host.lsp` and protocol typedefs. |
| PTY | Keep `@lydell/node-pty` behind a Node host seam. |

## Naming And Layout

```text
src/opencodehx/
  externs/
    node/
    effect/
    zod/
    hono/
    ai/
    solid/
    opentui/
    drizzle/
    mcp/
    acp/
    jsonrpc/
  host/
    node/
    bun/
  fx/
```

Extern modules should mirror the runtime import only when that helps generated TypeScript stay readable. Haxe-facing modules should use domain names, not npm package quirks.

## Generator Pipeline

The repeatable extern flow is:

1. Use `reference/opencode-source-parity-matrix.csv` to identify imports and source slices.
2. Inspect only the upstream call sites needed for the claimed Bead.
3. Hand-author a narrow extern/facade for those calls.
4. Add a compile smoke or fixture under OpenCodeHX.
5. If generated TS is poor or invalid, add a minimized `../genes` repro and record it in `docs/genes-ts-limitation-ledger.md`.
6. Tighten `Dynamic` after parity tests are green.

Do not generate massive externs from `.d.ts` files by default. A generator may be added later for repetitive DTOs, but the output must be reviewed, minimal, and tracked.

## First Compile Proof

The first extern package is `opencodehx.externs.node.Path`, backed by a `@:jsRequire("node:path")` binding. `opencodehx.host.node.NodePath` wraps it for Haxe-facing use.

This proves:

- a Node built-in extern compiles through `genes-ts`,
- the generated TypeScript imports `node:path`,
- `tsc` accepts the generated NodeNext output,
- the runtime smoke can call through a host facade.
