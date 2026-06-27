# OpenCode Test Port Matrix

**Bead:** `opencodehx-000.1`

## Summary

- Upstream test root: `../opencode/packages/opencode/test`
- Upstream test items tracked: 187
- Machine-readable matrix: `reference/opencode-test-port-matrix.csv`

| Port status | Kind | Count |
| --- | --- | ---: |
| deferred | test | 41 |
| direct | test | 20 |
| partial | test | 77 |
| ported | fixture | 1 |
| ported | test | 21 |
| reference-only | doc | 9 |
| reference-only | fixture | 12 |
| reference-only | helper | 4 |
| reference-only | snapshot | 1 |
| reference-only | test | 1 |

## Status Meanings

- `ported`: current OpenCodeHX smoke/golden evidence covers the upstream item's core behavior.
- `direct`: existing OpenCodeHX executable evidence covers the upstream item's behavior without a separate copied test.
- `partial`: current evidence covers part of the upstream behavior, but the matrix names the missing scope and owning Bead.
- `deferred`: no replacement exists yet because the owning product/runtime slice has not started.
- `reference-only`: upstream fixture/helper/document input, not an executable test. It remains an oracle input for the owning slice.

Every `partial` or `deferred` executable test row has a `skip_or_defer_reason`, a current or pending `replacement_fixture`, and a `next_bead` owner. Keep this file generated from `scripts/inventory/build-parity-matrix.mjs` so status changes are reviewable instead of drifting into markdown prose.

## Current Reading

OpenCodeHX has direct executable evidence in these broad areas:

- CLI/headless run, export, session persistence, resume/continue/fork, and local no-network live streaming.
- Installed npm package workflows for run, tool calls, persistence, TUI scaffold execution, and server health/SSE/session/PTY routes.
- Utility, config, file, message, storage, tool, permission, provider registry, project/git/worktree/sync/npm, PTY, and one-turn session behavior.
- Credential-free AI SDK stream mechanics, local provider-error handling, tool schema advertisement, and side-effecting live tool-loop evidence.
- Bundled SDK factory paths for OpenAI-compatible, OpenAI, xAI, Azure, Google, Vertex, Anthropic, Bedrock, Mistral, Groq, Cohere, Perplexity, OpenRouter, DeepInfra, Cerebras, Gateway, TogetherAI, Vercel, Alibaba, and GitLab.
- First provider request-option, variant, schema, and plugin-hook evidence.

Large product surfaces remain deferred:

- full server/API and SDK compatibility
- broader provider SDK loading and transforms
- full session lifecycle
- MCP/ACP
- plugin loading/install/auth/runtime side effects
- LSP
- live TUI beyond the scaffold
- live package-manager side effects
- Bun/release packaging

The next practical move is to use this matrix while selecting Beads: before starting a subsystem, filter `reference/opencode-test-port-matrix.csv` by `next_bead` and promote the relevant upstream tests into Haxe-owned fixtures or differential harnesses.
