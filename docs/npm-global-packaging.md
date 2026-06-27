# npm Global Packaging

**Beads:** `opencodehx-037`, `opencodehx-61d`, `opencodehx-5kz`, `opencodehx-d5b`, `opencodehx-jr4`, `opencodehx-x4i`, `opencodehx-o48`, `opencodehx-000.2.3`

## Slice

OpenCodeHX now has a first local npm global-install path:

- `package.json` exposes the `opencodehx` binary through `bin/opencodehx.mjs`;
- the bin shim is a small ESM entrypoint that imports the generated `dist/index.js`;
- the npm package file allowlist contains `bin/`, `dist/`, and `src-gen/`, plus npm's standard metadata files;
- `src-gen/` stays in the package so generated TypeScript remains inspectable and declaration/source-map references have a source surface;
- the generated TUI TSX scaffold under `src-gen/tui/` is included after `package:smoke` builds the TUI scaffold;
- `bin/opencodehx-opentui-solid-preload.mjs` packages the Bun/OpenTUI/Solid transform used by the TUI scaffold;
- `.beads/`, Haxe source, docs, tests, and local scripts are excluded from the packed artifact.

The package remains `0.x` beta and local-install focused. This is not a stable published OpenCode replacement claim.

## Evidence

`scripts/harness/package-smoke.mjs` builds on `npm pack --json` and installs the resulting tarball into a temporary global prefix. The smoke verifies:

- packed file membership includes the bin shim, packaged TUI preload, generated JS entrypoint, generated TS source, generated TUI TSX scaffold source, copied runtime resources, generated resource manifests, and parser/TUI worker fixtures;
- packed file membership excludes Beads metadata and Haxe source;
- `npm install -g --prefix <tmp> <tarball>` exposes an executable `opencodehx` bin;
- the installed package manifest records prompt, JSON, WASM, and worker resources with byte counts and hashes;
- the installed bin passes `--version`, `--help`, deterministic `run --model openai/gpt-5.2`, deterministic `run --dir <workspace> --format json`, deterministic `run --file <path>` attachment ingestion, mock AI SDK `run --mock-ai-sdk --dir <workspace> --format json`, local no-network OpenAI-compatible `run --model installed-live/chat` without the scaffold flag, plain plain config-model live resolution, local live provider-error persistence/export, deterministic/mock/live AI SDK default and `OPENCODE_DB` `run`/`export`/`run --session` append, deterministic/live `run --continue` append, deterministic/live `run --fork` child-session export, deterministic persisted file-part export, and `serve --help`;
- installed `run --dir` transcripts preserve the requested workspace in assistant path metadata for the deterministic fake-provider path, the credential-free mock AI SDK path, and the local live AI SDK path;
- installed live run evidence asserts the local OpenAI-compatible request path, bearer authorization header, `stream: true` request body, no-scaffold-flag `--model provider/model` routing, plain config-model routing, provider-error events with assistant `finish: "error"` export, default database export, resumed append, latest-root continue, and fork parent linkage while avoiding external credentials;
- the installed package exposes its package-local pinned Bun binary and runs `src-gen/tui/index.tsx` with the packaged preload, producing `tui-scaffold:ok`;
- the installed bin starts `serve --hostname 127.0.0.1 --port 0`, reports the bound URL, answers `/health` with the `opencodehx` service payload, opens `/event` as an SSE stream, observes `server.connected` and the live `session.created` event for a created session, lists that session, reads a message page, selects the session through `/tui/select-session`, aborts it, creates a `cat`-backed PTY, writes through `/pty/:id/connect`, verifies replay/tail cursor behavior, deletes the PTY, and terminates cleanly when the harness stops the child process.

Useful command:

```bash
npm run package:smoke
```

`npm run ci:full` and GitHub CI now include `package:smoke`, so package drift is part of the normal gate.

## Boundary

Installed `serve` evidence is still a bootstrap smoke: it proves the packed global binary can start the Node/Hono server runtime, bind a host/port, answer `/health`, drive the current in-memory session HTTP workflow, stream first server/session SSE events, exercise a deterministic PTY WebSocket path, and stay alive until the harness terminates the process. Broader installed server behavior such as auth, server attach, long-running/live provider session workflows, workspace proxying, multi-shell terminal behavior from the installed binary, and production process shutdown policy remain separate server/CLI integration work.

Installed `run --dir`, `run --file`, default storage, and `OPENCODE_DB` override evidence is still a headless bootstrap smoke, not full OpenCode chat parity. It proves the package can resolve a real workspace path, record local file attachment metadata as user parts, run deterministic, mock AI SDK, and local live AI SDK session paths from the installed binary, route explicit non-fake `--model provider/model` values to the live path, use merged config `model` through `--live-ai-sdk`, capture local live provider errors, persist fresh sessions, export them, append by explicit session ID, append deterministic runs through latest-root `--continue`, fork a persisted child session with parent linkage, and use recovered text history in the resumed AI SDK prompt. It does not yet construct full tool/file-aware history prompts for prior sessions, initialize projects, attach to a server, prompt for permissions, perform richer live provider attachment handling, or prove external credential-backed live provider chat beyond local no-network fixtures.

Installed TUI evidence is the existing OpenTUI test-renderer scaffold, not the final live terminal UI. It proves the packed tarball contains generated TUI TSX, the preload needed for OpenTUI/Solid transforms, and a package-local Bun runtime capable of executing that scaffold after global install. Live prompt focus, terminal worker lifecycle, server attachment, model/provider dialogs backed by real data, and long-running TUI interaction remain later TUI integration work.
