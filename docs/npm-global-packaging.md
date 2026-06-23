# npm Global Packaging

**Beads:** `opencodehx-037`, `opencodehx-61d`

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
- the installed bin passes `--version`, `--help`, deterministic `run --model openai/gpt-5.2`, and `serve --help`;
- the installed bin starts `serve --hostname 127.0.0.1 --port 0`, reports the bound URL, answers `/health` with the `opencodehx` service payload, and terminates cleanly when the harness stops the child process.

Useful command:

```bash
npm run package:smoke
```

`npm run ci:full` and GitHub CI now include `package:smoke`, so package drift is part of the normal gate.

## Boundary

Installed `serve` evidence is intentionally narrow: it proves the packed global binary can start the Node/Hono server runtime, bind a host/port, answer `/health`, and stay alive until the harness terminates the process. Broader installed server behavior such as auth, server attach, long-running session workflows, workspace proxying, PTY WebSocket exercise from the installed binary, and production process shutdown policy remain separate server/CLI integration work.
