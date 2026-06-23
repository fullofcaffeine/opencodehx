# npm Global Packaging

**Beads:** `opencodehx-037`, `opencodehx-61d`, `opencodehx-5kz`

## Slice

OpenCodeHX now has a first local npm global-install path:

- `package.json` exposes the `opencodehx` binary through `bin/opencodehx.mjs`;
- the bin shim is a small ESM entrypoint that imports the generated `dist/index.js`;
- the npm package file allowlist contains `bin/`, `dist/`, and `src-gen/`, plus npm's standard metadata files;
- `src-gen/` stays in the package so generated TypeScript remains inspectable and declaration/source-map references have a source surface;
- `.beads/`, Haxe source, docs, tests, and local scripts are excluded from the packed artifact.

The package remains `0.x` beta and local-install focused. This is not a stable published OpenCode replacement claim.

## Evidence

`scripts/harness/package-smoke.mjs` builds on `npm pack --json` and installs the resulting tarball into a temporary global prefix. The smoke verifies:

- packed file membership includes the bin shim, generated JS entrypoint, generated TS source, copied runtime resources, generated resource manifests, and parser/TUI worker fixtures;
- packed file membership excludes Beads metadata and Haxe source;
- `npm install -g --prefix <tmp> <tarball>` exposes an executable `opencodehx` bin;
- the installed package manifest records prompt, JSON, WASM, and worker resources with byte counts and hashes;
- the installed bin passes `--version`, `--help`, deterministic `run --model openai/gpt-5.2`, deterministic `run --dir <workspace> --format json`, mock AI SDK `run --mock-ai-sdk --dir <workspace> --format json`, and `serve --help`;
- installed `run --dir` transcripts preserve the requested workspace in assistant path metadata for both the deterministic fake-provider path and the credential-free mock AI SDK path;
- the installed bin starts `serve --hostname 127.0.0.1 --port 0`, reports the bound URL, answers `/health` with the `opencodehx` service payload, and terminates cleanly when the harness stops the child process.

Useful command:

```bash
npm run package:smoke
```

`npm run ci:full` and GitHub CI now include `package:smoke`, so package drift is part of the normal gate.

## Boundary

Installed `serve` evidence is intentionally narrow: it proves the packed global binary can start the Node/Hono server runtime, bind a host/port, answer `/health`, and stay alive until the harness terminates the process. Broader installed server behavior such as auth, server attach, long-running session workflows, workspace proxying, PTY WebSocket exercise from the installed binary, and production process shutdown policy remain separate server/CLI integration work.

Installed `run --dir` evidence is still a headless bootstrap smoke, not full OpenCode chat parity. It proves the package can resolve a real workspace path and run both deterministic and mock AI SDK session paths from the installed binary. It does not yet ingest file attachments, continue prior sessions, initialize projects, attach to a server, prompt for permissions, or perform live provider chat without the explicit `--live-ai-sdk` opt-in path.
