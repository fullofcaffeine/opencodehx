# LSP Minimum Surface

**Beads:** `opencodehx-029`, `opencodehx-000.7.1`

## Upstream Oracles

- `../opencode/packages/opencode/test/lsp/client.test.ts`
- `../opencode/packages/opencode/test/lsp/index.test.ts`
- `../opencode/packages/opencode/test/lsp/launch.test.ts`
- `../opencode/packages/opencode/test/lsp/lifecycle.test.ts`
- `../opencode/packages/opencode/src/tool/lsp.ts`

## Current Surface

OpenCodeHX now has a typed, dependency-free LSP service seam:

- `opencodehx.lsp.LspRuntime` models enabled/disabled LSP configuration, inside-workspace checks, TypeScript extension matching, Deno marker exclusion, lazy client spawn, broken-server suppression, idempotent init, status, typed diagnostics aggregation, empty no-client results, and shutdown.
- `opencodehx.lsp.LspClient` models the minimum JSON-RPC client lifecycle over an injected endpoint: initialize, initialized notification, client responses for `workspace/workspaceFolders`, `client/registerCapability`, and `client/unregisterCapability`, request forwarding, initialization failure, and timeout handling.
- `opencodehx.lsp.LspDiagnostic` mirrors upstream diagnostic `pretty()` and error-only `report()` formatting.
- `opencodehx.tool.LspTool` ports the first LSP tool facade over an injected runtime, including permission request shape, file existence checks, no-server errors, 1-based to 0-based position conversion, title formatting, and no-result output.
- `opencodehx.smoke.LspSmoke` proves the current behavior with deterministic fake endpoints, including a fake language server request path and failure/timeout cases.

## Boundaries

This slice intentionally does not spawn real language server binaries, download ESLint/Vue servers, or bind `vscode-jsonrpc/node`. Runtime process/stdin/stdout transport, Windows `.cmd` script spawning, package-manager backed binary discovery, and full SDK-compatible JSON-RPC streaming remain follow-up work.

JSON-RPC request and response payloads are kept as `genes.ts.Unknown` at the protocol boundary. Domain-owned values such as diagnostics, locations, statuses, server definitions, and tool arguments are typed before storage or use; diagnostics are grouped through `LspDiagnostics` instead of an open object map.
