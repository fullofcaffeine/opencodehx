# OpenCodeHX Docs

Design notes, parity matrices, host-seam ledgers, guardrails, and decision records live here.

Prefer checked-in evidence over transient notes. If a lesson changes how agents should work in this repo, update `AGENTS.md` in the same change.

## Current Evidence

CLI and session evidence:

- `headless-run-scaffold.md` covers deterministic, mock AI SDK, and local live AI SDK `run`, plus `run --dir`, `run --file`, `run --session`, `run --continue`, `run --fork`, and non-interactive `export <sessionID>`.
- `session-processor-one-turn.md` covers the one-turn and async AI SDK-backed session processor, store-backed export/recovery, model-emitted tool dispatch, accumulated tool-result history, live config-denied write enforcement, and permission-skip approval for config-asked writes.
- `fake-provider-transcript-harness.md` keeps the credential-free transcript oracle for deterministic parity.

Live CLI and packaging evidence:

- Local no-network OpenAI-compatible fixtures prove streaming success, provider-error transcript/export, live `read`/`write`/`edit`/`apply_patch`/`bash` tool calls, write-then-read tool chains, config-denied write calls, and `--dangerously-skip-permissions` approval for config-asked writes.
- `npm-global-packaging.md` proves the packed binary through installed `run`, mock/live runs, persistence/export/resume/continue/fork, TUI scaffold execution, and installed `serve` health/SSE/session/PTY workflows.
- `cli-command-surface.md` tracks upstream command aliases, help text, known-command errors, and the first side-effecting export path.

Provider, config, and runtime foundations:

- `provider-registry-port.md` covers the typed provider registry, AI SDK factory smokes, provider transforms, registry-derived tool schemas, and models.dev cache/fetch behavior.
- `config-port.md`, `permission-model-port.md`, `bash-shell-seam.md`, `project-runtime-parity.md`, `formatter-port.md`, and `effect-runtime-parity.md` cover config loading, permissions, parser-backed bash permissions, project/git/sync foundations, formatting, observability resources, run-service memo behavior, and instance state.
- `resource-imports.md`, `bus-runtime-parity.md`, `pty-runtime.md`, and `fixture-smoke-parity.md` cover host/runtime resources, event delivery, PTY lifecycle/WebSocket replay, and smoke tmpdir parity.

Protocol, plugin, and UI foundations:

- `server-hono-seam.md` covers the first Node/Hono server seam plus SDK-compatible create/list/resume/event flow.
- `mcp-acp-minimum.md`, `lsp-minimum.md`, and `plugin-runtime-minimum.md` cover the first MCP/ACP, LSP, and plugin runtime surfaces.
- `tui-scaffold.md` covers the TUI scaffold/transcript replay path plus route/keybind macro diagnostics.

Quality and planning references:

- `compiler-output-profiles.md`, `generated-ts-readability-gate.md`, `syntax-code-audit.md`, `checked-artifact-constructors.md`, `tool-registry-port.md`, `performance-ux-benchmark.md`, and `portability-classification-ledger.md` capture generated output, raw-boundary, checked-artifact, tool-ID, benchmark, and portability evidence.

The top-level `README.md` carries the public-facing ASCII progress bar. Refresh it from Beads when closing meaningful port slices so newcomers see a current completion snapshot without digging through issue history.

Public-readiness checks live in `scripts/ci/version-sync-check.mjs`, `scripts/ci/release-contracts-check.mjs`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, and `.github/workflows/security-gitleaks.yml`. The release setup intentionally stays on `0.x` beta prereleases until OpenCode parity and packaging smoke evidence justify stable release claims.

Testing strategy:

- `haxe-authored-testing-strategy.md` records the plan for Haxe-authored test facades that generate idiomatic Jest/Vitest and Playwright specs while preserving upstream OpenCode tests as oracles.

Planning matrices:

- `opencode-source-inventory.md` summarizes the upstream source inventory and points to `reference/opencode-source-parity-matrix.csv`.
- `opencode-test-port-matrix.md` summarizes per-test port status and points to `reference/opencode-test-port-matrix.csv`.
- `upstream-rebase-procedure.md` defines the controlled process for refreshing the `../opencode` oracle snapshot, reviewing matrix drift, updating evidence, and creating Beads for unresolved upstream changes.
- Regenerate source/test matrices with `npm run inventory:matrix`.

Decision records:

- `m3-replacement-checkpoint.md` records the 2026-06-18 M3 decision to continue the port, keep the next phase Node-first/server-focused, and defer replacement claims until broader parity evidence exists.
