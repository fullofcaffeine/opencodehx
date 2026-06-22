# Plugin Runtime Minimum Surface

**Bead:** `opencodehx-030`

## Upstream Oracles

- `../opencode/packages/opencode/test/plugin/shared.test.ts`
- `../opencode/packages/opencode/test/plugin/meta.test.ts`
- `../opencode/packages/opencode/test/plugin/loader-shared.test.ts`
- `../opencode/packages/opencode/test/plugin/trigger.test.ts`
- `../opencode/packages/opencode/test/plugin/install.test.ts`

## Current Surface

OpenCodeHX now has a dependency-free first plugin runtime seam:

- `opencodehx.plugin.PluginShared` covers upstream-style plugin spec parsing for plain, scoped, versioned, git URL, alias, and `npm:` protocol specs. It also resolves file plugin targets through the existing config path resolver, reads package metadata, resolves basic package entrypoints, resolves plugin IDs, and validates `oc-themes` entries.
- `opencodehx.plugin.PluginMeta` tracks file and npm plugin metadata in JSON: source, requested version, installed version, file modified time, fingerprint, load count, and first/same/updated states.
- `opencodehx.plugin.PluginRuntime` loads configured plugin origins through injected resolver/module-provider seams, preserving deterministic order. It applies the upstream server-plugin shape rules covered in the smoke: default V1 server plugins win over named legacy exports, file V1 plugins need an ID, V1 server+tui exports are rejected, identical legacy function exports dedupe, missing modules skip, and trigger hooks run sequentially.
- `opencodehx.smoke.PluginSmoke` proves parser cases, metadata state transitions, injected npm package metadata, V1 rejection rules, legacy dedupe, default V1 precedence, and `experimental.chat.system.transform` invocation.

## Boundaries

This is not live plugin package integration yet. Dynamic `import(...)`, `Npm.add`, install concurrency, compatibility semver checks, built-in auth plugins, TUI plugin entrypoints, workspace adaptors, browser-like plugin APIs, and event bus subscriptions remain follow-up work.

The runtime uses injected module providers so the first parity evidence is deterministic and credential-free. JSON package metadata and persisted metadata are narrowed at the boundary; arbitrary plugin hook input remains `genes.ts.Unknown` until the owning hook schemas are ported.
