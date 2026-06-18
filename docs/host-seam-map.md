# Host Seam Map

**Bead:** `opencodehx-008`  
**Goal:** keep OpenCodeHX Node-first and Bun-aware while preserving a portable Haxe app core.

## Policy

OpenCodeHX should model OpenCode behavior in Haxe-facing modules, then isolate runtime-specific APIs in small host modules. The host layer starts with Node implementations because the first generated TypeScript target is NodeNext ESM. Bun support remains a classified seam, not a reason to block early parity.

Current proof: `opencodehx.host.node.NodePath` wraps the `node:path` extern used by the smoke build. Future host modules should follow the same direction: narrow externs, named Haxe facades, and upstream parity fixtures.

## Runtime Class Meanings

| Class | Meaning | Port rule |
| --- | --- | --- |
| `portable` | Pure Haxe logic or host-agnostic data modeling | Keep free of Node/Bun imports. |
| `node-host` | Node built-ins or Node-specific packages | Put under `opencodehx.host.node` or a narrow host facade. |
| `bun-host` | Bun APIs, Bun-only packages, or Bun packaging assumptions | Defer or wrap behind the same app-facing interface as Node. |
| `browser` | Browser globals such as `window`, DOM, Web Crypto, or browser auth pages | Keep behind plugin/TUI/server web facades. |
| `tsx` | Solid/OpenTUI components and TSX codegen | Treat as TUI compiler/runtime seam. |
| `resource` | Text, JSON, sound, wasm, prompt, or static assets | Track copy/import behavior explicitly. |
| `generated-ts-only` | A generated TypeScript artifact needed for packaging or review | Never hand-edit; regenerate from Haxe or scripts. |

## Seam Table

| Seam | Upstream evidence | Class | Initial Node target | Future/Bun notes |
| --- | --- | --- | --- | --- |
| Paths and path normalization | `file/index.ts`, `session/session.ts`, `tool/*.ts`, `shell/shell.ts` | `node-host` facade with portable call sites | Extend `opencodehx.host.node.NodePath` into an app-facing `Path` facade when call sites grow beyond smoke. | Path behavior must preserve Windows separators, `path.relative`, project escape checks, and upstream display strings. |
| Global app directories | `global/index.ts` | `node-host` | `opencodehx.host.node.NodeGlobalPaths` using `xdg-basedir`, `os.homedir`, and `fs.mkdir`. | Preserve `OPENCODE_TEST_HOME` and cache version behavior. Bun can share paths but not necessarily file APIs. |
| Environment state | `env/index.ts`, `flag/flag.ts` | `portable` service over host snapshot | `opencodehx.env.Env` should snapshot `process.env` through a Node env facade, then expose mutable per-instance state. | Avoid direct `process.env` reads outside env/flag seams; this makes config fixtures deterministic. |
| Filesystem | `file/index.ts`, `util/filesystem.ts`, `storage/storage.ts`, `tool/read.ts`, `tool/write.ts` | `node-host` service | Narrow `opencodehx.host.node.NodeFileSystem` with read/write/stat/glob/temp/chmod/remove streams as each slice needs them. | Treat `@opencode-ai/shared/filesystem` behavior as oracle. Preserve BOM, permission errors, recursive ops, glob ordering, and Windows normalization. |
| Storage JSON files and migrations | `storage/storage.ts`, `storage/json-migration.ts` | portable service over filesystem | Haxe `Storage` interface backed by Node filesystem facade; port migrations as pure transformations plus file effects. | `Date.now()` in migrations needs clock seam for tests. Later DB storage may share repository interfaces. |
| SQLite database | `storage/db.node.ts`, `storage/db.bun.ts`, `storage/schema.sql.ts` | `node-host`/`bun-host` | Defer until storage slice requires channel DB; use a repository interface before choosing Node SQLite package. | Bun uses `bun:sqlite`/`drizzle-orm/bun-sqlite`; Node needs a separate adapter. Keep SQL schema source portable. |
| Server HTTP/WebSocket adapter | `server/adapter.node.ts`, `server/adapter.bun.ts`, `server/server.ts` | `node-host`/`bun-host` | Node adapter around `@hono/node-server` and `@hono/node-ws`. | Both adapters should implement one Haxe `ServerAdapter` interface with `listen`, `stop`, and `upgradeWebSocket`. Preserve port-0 fallback to 4096 then random. |
| Fetch and network | `lsp/server.ts`, `plugin/codex.ts`, `tool/webfetch.ts`, `provider/*` | `portable` facade over runtime fetch | Start with global `fetch` extern under Node 20+ and wrap it as `HttpClient` when repeated patterns appear. | Keep auth, redirects, stream bodies, and abort behavior testable. Browser/plugin fetch interception is a later seam. |
| Streams and buffers | `server/event.ts`, `provider/*`, `lsp/server.ts`, `tool/read.ts` | `node-host` until Web Streams are proven | Bind only used Node stream helpers, such as `node:stream/consumers`, and prefer Web Stream types at app boundary. | Provider streaming should converge on Haxe typed enums for events before host transport details. |
| Process spawning and shell | `shell/shell.ts`, `tool/bash.ts`, `lsp/server.ts`, `util/process.ts` | `node-host` | `NodeProcess` facade for `spawn`, cwd/env, stdout/stderr capture, kill, exit code, and timers. | Preserve Windows shell selection, Git Bash detection, and environment case sensitivity. |
| PTY | `pty/index.ts`, `pty/pty.node.ts`, `pty/pty.bun.ts`, `server/routes/instance/pty.ts` | `node-host`/`bun-host` | Define an app-facing `PtyHost` matching upstream `Proc`; Node implementation uses `@lydell/node-pty`. | Bun implementation uses `bun-pty`. Keep WebSocket control-frame protocol portable. |
| LSP | `lsp/client.ts`, `lsp/server.ts`, `tool/lsp.ts` | mostly `node-host` | Start with process/filesystem/fetch facades and a narrow `vscode-jsonrpc/node` extern. | LSP downloads and language-specific installers are host-heavy; port after config/tools. |
| Plugin loading | `plugin/index.ts`, `plugin/loader.ts`, `cli/cmd/tui/plugin/runtime.ts` | `node-host` plus `bun-host` plus browser-ish plugin APIs | Start with config metadata and server plugin loading through dynamic import facade. | Upstream exposes `Bun.$` when available and TUI plugins have browser-like APIs. Keep plugin API contracts portable. |
| MCP/ACP transports | `mcp/*`, `acp/*`, `cli/cmd/mcp.ts` | portable protocols over host fetch/process | Model protocol messages with Haxe enums/typedefs first; host transport adapters later. | OAuth/device flows need clock, fetch, env, and browser-open seams. |
| Clock and timers | `id/id.ts`, `session/session.ts`, `mcp/auth.ts`, TUI contexts | portable facade | `Clock.nowMillis`, `Clock.sleep`, `Clock.timeout` wrapping `Date.now` and timers. | Required for deterministic ids, sessions, auth expiry, debounce tests, and TUI replays. |
| Crypto and ids | `id/id.ts`, `plugin/codex.ts`, `cli/cmd/github.ts` | `node-host`/browser | Node crypto facade for random bytes/UUID/digest; keep `Identifier` Haxe-native. | Web Crypto is needed in browser/plugin contexts; do not leak it into core ids. |
| OS/platform | `shell/shell.ts`, `file/protected.ts`, `tool/bash.ts`, `lsp/server.ts` | `node-host` facade | `HostPlatform` with `platform`, `arch`, `homedir`, `tmpdir`, executable extension helpers. | Platform decisions should be injectable in tests and recorded in fixtures. |
| Terminal/TUI | `cli/cmd/tui/**/*.tsx`, `@opentui/*`, `Bun.stringWidth`, sound/clipboard/editor utils | `tsx`, `node-host`, `bun-host` | Defer until TSX compiler fixture exists; isolate sound, clipboard, editor, terminal title, and string width. | `Bun.stringWidth` needs a Node-compatible facade before TUI parity. |
| Resources/assets | prompt `.txt`, theme `.json`, sound `.wav`, tree-sitter `.wasm` imports | `resource` | Add manifest/copy support in scripts or `genes-ts` fixtures before broad port. | Do not inline large resources accidentally. Resource imports are a compiler/task seam (`opencodehx-010`). |
| Browser/open behavior | `plugin/codex.ts`, `open` package usage, auth flows | `browser`/`node-host` | Narrow `OpenExternal` facade for URLs/files. | Needs UX parity for OAuth and device auth, but can wait behind config/provider work. |

## Initial Port Order

1. `Path`, `Env`, `Clock`, and `HostPlatform` because config, flags, ids, and session DTOs need them.
2. `NodeFileSystem` plus storage JSON interface because config/tool/session parity needs fixtures.
3. `NodeProcess`, shell, and basic fetch because tools and LSP depend on them.
4. Server adapter and PTY host once headless/session basics exist.
5. Plugin, MCP/ACP, LSP downloads, TUI utilities, and Bun adapters after the core behavior is measurable.

## Design Rules

- App-facing modules should depend on `opencodehx.host.*` interfaces or portable facades, not raw `node:*`, `Bun`, or browser globals.
- Direct host calls are acceptable only in `opencodehx.externs.*`, `opencodehx.host.node.*`, future `opencodehx.host.bun.*`, or a documented one-file bootstrap.
- If a seam needs `Dynamic`, record it in `docs/genes-ts-limitation-ledger.md` only when the debt is related to code generation or type modeling. Pure runtime-adapter TODOs should become Beads instead.
- Preserve upstream host quirks until parity tests say otherwise: port fallback, Windows shell/env behavior, XDG paths, cache versioning, PTY control frames, and filesystem error shapes.
- Prefer Haxe typed enums at app boundaries for provider events, protocol messages, permission outcomes, and process/PTY state transitions. Keep strings and broad objects at host/JSON boundaries.
