# MCP/ACP Minimum Surface

**Bead:** `opencodehx-028`

## Upstream Oracles

- `../opencode/packages/opencode/test/mcp/headers.test.ts`
- `../opencode/packages/opencode/test/mcp/lifecycle.test.ts`
- `../opencode/packages/opencode/test/mcp/oauth-auto-connect.test.ts`
- `../opencode/packages/opencode/test/acp/agent-interface.test.ts`
- `../opencode/packages/opencode/test/acp/event-subscription.test.ts`

## Current Surface

OpenCodeHX now has a dependency-free first MCP/ACP protocol surface:

- `opencodehx.mcp.McpRuntime` models server registration, connect/disconnect status, disabled and failed servers, needs-auth status, cached tool discovery, tool-change refresh, prompt/resource listing for connected clients only, client replacement cleanup, sanitized server/tool prefixes, and remote transport option construction for headers plus default OAuth.
- `opencodehx.acp.AcpAgent` exposes the upstream-checked ACP agent method set: `initialize`, `newSession`, `prompt`, `cancel`, `loadSession`, `setSessionMode`, `authenticate`, `listSessions`, `unstable_forkSession`, `unstable_resumeSession`, and `unstable_setSessionModel`.
- `opencodehx.smoke.McpAcpSmoke` proves the current runtime behavior with deterministic fake MCP clients and a fake ACP connection. The smoke covers MCP lifecycle/cache/error cases and ACP session-scoped `message.part.delta`, ignored live user text updates, repeated `loadSession` subscription dedupe, and permission reply routing.

## Boundaries

This is not real MCP/ACP package integration yet. `package.json` does not include `@modelcontextprotocol/sdk` or `@agentclientprotocol/sdk`, so this slice deliberately avoids SDK-specific externs and network/process transports.

The current MCP tool schema uses `genes.ts.Unknown` because JSON Schema payloads are provider-owned boundary data until tool-specific schemas are decoded. ACP event routing is typed around the discriminants exercised by the upstream oracle tests, but broader event payloads and the real SDK router belong to a later transport/runtime bead.

Remaining MCP/ACP work includes real stdio/HTTP/SSE transports, OAuth browser/callback/device behavior, auth persistence, timeout/cancellation handling, CLI commands, package exports, and direct SDK compatibility tests.
