# Bun Binary Packaging Feasibility

**Bead:** `opencodehx-038`

This report evaluates whether OpenCodeHX should restore upstream OpenCode-style Bun single-binary packaging for generated TypeScript output.

## Decision

Do not claim supported Bun single-binary packaging yet.

The path is feasible enough for a future packaging slice, but the current OpenCodeHX runtime should stay npm/Node-first. A local Bun `--compile` probe successfully produced a 69 MB macOS arm64 executable, but that executable failed before `--version` because the bundled startup path imported `@lydell/node-pty` and Bun did not include its dynamically resolved platform package.

The near-term recommendation is to keep the existing npm global package as the supported local packaging gate and add Bun binary packaging only after native addon, worker, resource, and server startup seams are made explicit.

## Evidence

Local probe, on this checkout:

```sh
node_modules/.bin/bun --version
# 1.3.14

mkdir -p .artifacts/bun-packaging
node_modules/.bin/bun build --compile ./bin/opencodehx.mjs --outfile .artifacts/bun-packaging/opencodehx-probe
# [280ms]  bundle  987 modules
# [244ms] compile  .artifacts/bun-packaging/opencodehx-probe

ls -lh .artifacts/bun-packaging/opencodehx-probe
# 69M
```

Runtime probe:

```sh
.artifacts/bun-packaging/opencodehx-probe --version
```

Failed before CLI dispatch:

```text
error: The @lydell/node-pty package supports your platform (darwin-arm64), but it could not find the platform-specific package for it: @lydell/node-pty-darwin-arm64
```

The package is present in `node_modules`, so this is a compile/bundle reachability issue, not a missing local install:

```sh
npm ls @lydell/node-pty-darwin-arm64 better-sqlite3 --depth=1
```

Output showed `@lydell/node-pty-darwin-arm64@1.2.0-beta.10` and `better-sqlite3@12.11.1`.

## Upstream Pattern

Upstream OpenCode builds binaries from `packages/opencode/script/build.ts`. The important packaging moves are:

- uses `Bun.build({ compile: ... })` with `conditions: ["browser"]`, the OpenTUI Solid transform plugin, `format: "esm"`, `minify: true`, and `splitting: true`;
- cross-builds named packages for Darwin, Linux, Linux musl, and Windows across arm64/x64, including x64 baseline variants;
- passes explicit compile options for target, output path, runtime `execArgv`, and disabled `.env`/`bunfig` autoload;
- embeds version, migrations, channel, libc, and worker paths as build-time constants;
- includes the main entrypoint, OpenTUI parser worker, TUI worker, and optional generated web UI file map as build entrypoints;
- pre-installs platform variants for packages such as `@opentui/core` and `@parcel/watcher`;
- emits one package per platform binary and a wrapper package that selects the current platform binary, including AVX2/baseline and musl fallback logic.

Bun's current executable docs support the primitives upstream relies on: compile to standalone executables, cross-target builds, worker entrypoints, embedded files via `with { type: "file" }`, Node `fs` reads against embedded file paths, and N-API addon embedding when a `.node` addon is directly required.

## Current OpenCodeHX Shape

OpenCodeHX currently packages:

- `bin/opencodehx.mjs`, a Node shebang shim that imports `dist/index.js`;
- generated NodeNext ESM output in `dist/`;
- generated TypeScript and TUI TSX source in `src-gen/`;
- copied resources in `dist/resources` and `src-gen/resources`;
- resource manifests covering prompt text, JSON, WAV, WASM, and worker files;
- a package-local Bun dependency used by the TUI scaffold smoke;
- `better-sqlite3` for SQLite storage;
- `@lydell/node-pty` for PTY lifecycle;
- Hono/Node WebSocket server adapters.

The existing package gate is strong for npm:

```sh
npm run package:smoke
```

It packs, globally installs into a temp prefix, runs the installed bin, checks resources/manifests, runs the installed TUI scaffold through package-local Bun, starts `serve`, exercises SSE/session routes, and verifies PTY WebSocket behavior.

## Blockers

1. **Top-level native addon reachability.** `Main.hx` imports smoke modules, server smoke, and PTY smoke at the top level. Generated `dist/index.js` reaches `PtyService`, which imports `@lydell/node-pty`, before simple CLI commands such as `--version` can return. Binary packaging needs a CLI-only entrypoint or lazy imports so optional native surfaces are not loaded until needed.
2. **Dynamic optional native packages.** `@lydell/node-pty` dynamically resolves `@lydell/node-pty-<platform>`. Bun did not include that package in the probe executable even though it was installed. A supported build must either directly require/import the platform package for each target, mark it as an embedded N-API addon path, or ship sidecar platform packages.
3. **SQLite native addon strategy.** `better-sqlite3` contains `build/Release/better_sqlite3.node`. Bun can embed directly required N-API addons, but OpenCodeHX has not proven this addon through compiled `serve` or session storage paths. The alternative is a Bun `bun:sqlite` adapter, which would be a real host seam, not just packaging.
4. **Resource embedding.** Current runtime resources are copied to `dist/resources` and read by filesystem path. A single binary should replace this with Bun `type: "file"` imports or a generated embedded manifest profile. The resource set includes prompt text, JSON, WAV, parser WASM, and worker files.
5. **Worker entrypoints.** Bun standalone workers must be added as build entrypoints when they need to live inside the executable. OpenCodeHX currently packages parser/TUI worker resources as files only; final live parser/TUI workers need explicit entrypoint ownership.
6. **OpenTUI/Solid transform.** Upstream uses `@opentui/solid/bun-plugin` during binary builds. OpenCodeHX currently runs TUI scaffold TSX through a preload harness, not a Bun binary build step.
7. **Cross-target matrix and CI.** A real release path needs Darwin arm64/x64, Linux arm64/x64, Linux musl variants, Windows arm64/x64, and x64 baseline decisions. It also needs per-target smoke evidence and signing/notarization decisions for macOS/Windows.
8. **Package selection wrapper.** Upstream ships per-platform binary packages and a wrapper that selects AVX2/baseline/musl variants. OpenCodeHX currently has one npm package with generated JS and dependencies; a Bun binary release would need a separate package layout.

## Recommended Plan

1. **Split generated entrypoints.** Add a CLI/runtime entrypoint that excludes smoke modules and imports server/PTY/storage paths lazily. Keep the full smoke entrypoint for `npm run smoke`.
2. **Add a local compile smoke.** Introduce an opt-in `npm run bun:binary:probe` that compiles only the host platform and runs `--version`, `--help`, fake-provider `run`, and a resource read. Keep it outside normal CI until native addon handling is stable.
3. **Fix PTY packaging first.** Either force direct platform imports for `@lydell/node-pty-*` in the Bun build profile or keep PTY as a sidecar/package-managed feature. Prove `serve` can start without eager PTY import when PTY is unused.
4. **Choose SQLite strategy.** Compare embedded `better-sqlite3.node` with a Bun SQLite adapter behind the existing store contract. The adapter route is cleaner long-term because upstream already has Bun/Node database import conditions.
5. **Generate resource build profiles.** Extend `scripts/build/copy-resources.mjs` or add a companion generator that can emit both copied Node resources and Bun embedded import modules.
6. **Model worker entrypoints.** Promote final parser/TUI workers from resource fixtures to owned build entrypoints before claiming single-binary TUI/server parity.
7. **Mirror upstream target packaging.** Only after the host-platform probe passes should OpenCodeHX add platform package names, AVX2/baseline logic, Linux musl variants, and release artifacts.

## Go/No-Go

Current state: **no-go for supported release packaging**.

Next milestone: **go for an opt-in host-platform Bun binary probe** after the entrypoint split prevents `--version` from loading PTY and smoke-only modules.

Full release packaging should wait until the probe proves:

- compiled `--version` and `--help`;
- compiled fake-provider `run`;
- compiled resource manifest/text/WASM read;
- compiled `serve --help`;
- compiled `serve` startup without PTY eager-load failure;
- explicit PTY and SQLite decisions;
- at least one platform package layout compatible with npm install behavior.
