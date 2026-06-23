# npm Global Packaging

**Bead:** `opencodehx-037`

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

- packed file membership includes the bin shim, generated JS entrypoint, generated TS source, and copied runtime resources;
- packed file membership excludes Beads metadata and Haxe source;
- `npm install -g --prefix <tmp> <tarball>` exposes an executable `opencodehx` bin;
- the installed bin passes `--version`, `--help`, deterministic `run --model openai/gpt-5.2`, and `serve --help`.

Useful command:

```bash
npm run package:smoke
```

`npm run ci:full` and GitHub CI now include `package:smoke`, so package drift is part of the normal gate.

## Boundary

The installed `serve` evidence is currently command-surface help, not a long-running installed server process. The server runtime itself has Node listener smoke coverage in `server-hono-seam.md`; wiring a side-effecting installed `serve` process that starts, reports its URL, accepts `/health`, and shuts down cleanly belongs to a later CLI/server integration slice.
