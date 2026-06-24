# OpenCode Test Port Matrix

**Bead:** `opencodehx-000.1`

## Summary

- Upstream test root: `../opencode/packages/opencode/test`
- Upstream test items tracked: 187
- Machine-readable matrix: `reference/opencode-test-port-matrix.csv`

| Port status | Kind | Count |
| --- | --- | ---: |
| deferred | test | 57 |
| direct | test | 19 |
| partial | test | 80 |
| ported | fixture | 1 |
| ported | test | 3 |
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

OpenCodeHX has direct executable evidence for selected utility, config, file, message, storage, tool, permission, provider registry, credential-free AI SDK stream mechanics, OpenAI-compatible/OpenAI/xAI/Azure/Google/Vertex/Anthropic/Bedrock/Mistral/Groq/Cohere/Perplexity/OpenRouter/DeepInfra/Cerebras/Gateway/TogetherAI/Vercel/Alibaba/GitLab SDK factory paths, first provider request-option, variant, and schema transforms, CLI, project/git/worktree/sync/npm, parser-backed bash permissions, PTY lifecycle/WebSocket replay, and one-turn session behavior. Large product surfaces remain deferred: full server/API and SDK compatibility, broader provider SDK loading/transforms, full session lifecycle, MCP/ACP, plugin loading, LSP, live TUI, live package-manager installation side effects, and packaging.

The next practical move is to use this matrix while selecting Beads: before starting a subsystem, filter `reference/opencode-test-port-matrix.csv` by `next_bead` and promote the relevant upstream tests into Haxe-owned fixtures or differential harnesses.
