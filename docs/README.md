# OpenCodeHX Docs

Design notes, parity matrices, host-seam ledgers, guardrails, and decision records live here.

Prefer checked-in evidence over transient notes. If a lesson changes how agents should work in this repo, update `AGENTS.md` in the same change.

Current executable evidence includes the credential-free fake provider transcript harness in `fake-provider-transcript-harness.md`, the typed provider registry in `provider-registry-port.md`, the resource import adapter in `resource-imports.md`, the headless run scaffold in `headless-run-scaffold.md`, the Node-backed shell seam in `bash-shell-seam.md`, the permission model in `permission-model-port.md`, the one-turn session processor in `session-processor-one-turn.md`, the first Node/Hono server seam in `server-hono-seam.md`, and the TUI scaffold/transcript replay path in `tui-scaffold.md`.

The top-level `README.md` carries the public-facing ASCII progress bar. Refresh it from Beads when closing meaningful port slices so newcomers see a current completion snapshot without digging through issue history.

Public-readiness checks live in `scripts/ci/version-sync-check.mjs`, `scripts/ci/release-contracts-check.mjs`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`, and `.github/workflows/security-gitleaks.yml`. The release setup intentionally stays on `0.x` beta prereleases until OpenCode parity and packaging smoke evidence justify stable release claims.

Testing strategy:

- `haxe-authored-testing-strategy.md` records the plan for Haxe-authored test facades that generate idiomatic Jest/Vitest and Playwright specs while preserving upstream OpenCode tests as oracles.

Planning matrices:

- `opencode-source-inventory.md` summarizes the upstream source inventory and points to `reference/opencode-source-parity-matrix.csv`.
- `opencode-test-port-matrix.md` summarizes per-test port status and points to `reference/opencode-test-port-matrix.csv`.
- Regenerate source/test matrices with `npm run inventory:matrix`.

Decision records:

- `m3-replacement-checkpoint.md` records the 2026-06-18 M3 decision to continue the port, keep the next phase Node-first/server-focused, and defer replacement claims until broader parity evidence exists.
