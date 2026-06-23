# Changelog

OpenCodeHX uses semantic-release with `0.x` beta prereleases while the Haxe port works toward upstream OpenCode parity.

Release notes are generated here during release preparation.

Current beta packaging expectations include a local `npm pack` plus temporary global-install smoke for the generated `opencodehx` bin, including deterministic `run`, deterministic `run --dir`, mock AI SDK `run --mock-ai-sdk --dir`, installed TUI scaffold execution through package-local Bun, and installed `serve` health/SSE/session/PTY workflow; keep that gate in sync with package metadata, CLI workspace resolution, TUI scaffold/preload packaging, or CLI server startup changes before the next generated release notes are prepared.

Current source-safety expectations include macro-checked built-in plugin routes, built-in keybind action references, source-authored tool IDs, built-in provider IDs, server event types, copied-resource paths, and `npm run macro:diagnostics` as the negative compile gate for typo diagnostics.

Current platform-parity expectations include the Windows shell smoke workflow for `cmd.exe`, PowerShell, Git Bash, PTY shell args, and `killTree` behavior; keep `npm run windows:shell:smoke`, `.github/workflows/ci.yml`, and release-contract checks synchronized when changing shell or process teardown behavior.

Current CI bootstrap expectations include checking out sibling `genes-ts` for Haxe/lix jobs, explicitly rebuilding the `better-sqlite3` native addon and installing the local `bun` binary after `npm ci --ignore-scripts`, and installing `ripgrep` before the Node smoke file-search seam runs.

Current live package-manager parity expectations include an explicit opt-in `npm run live:package-managers` harness. It must stay out of normal smoke/CI, require `OPENCODEHX_LIVE_PACKAGE_MANAGERS=1`, and keep side effects inside temp prefixes/projects or package-manager dry-run/noop modes.

Current native watcher parity expectations include an explicit `npm run file:watcher:smoke` harness for host-timed Node `fs.watch` evidence. Keep the deterministic injected watcher path in `npm run smoke`, and keep the native harness out of normal CI unless it becomes stable across hosted platforms.

Current instance bootstrap parity expectations include the typed upstream-order service graph in `InstanceBootstrapRuntime` and the `command.executed` init hook that marks a project initialized. Keep concrete service bodies incremental and documented until share, snapshot, live plugin loading, and real LSP process boot are fully ported.
