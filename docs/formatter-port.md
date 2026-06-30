# Formatter Port

**Beads:** `opencodehx-bvh`, `opencodehx-000.11.16`

## Upstream Oracle

Primary upstream evidence:

- `../opencode/packages/opencode/src/format/index.ts`
- `../opencode/packages/opencode/src/format/formatter.ts`
- `../opencode/packages/opencode/test/format/format.test.ts`

## What Landed

`opencodehx.format.FormatRuntime` ports the first formatter service seam:

- `formatter: false` disables all formatters and makes `file()` return `false`.
- `formatter: true` enables the built-in registry subset needed by the upstream formatter tests.
- Formatter object config preserves built-ins, removes disabled entries, supports custom command/environment/extensions entries, and mirrors the linked `ruff`/`uv` disable behavior.
- Formatter object config is narrowed through `genes.ts.UnknownRecord`/`UnknownArray`/`UnknownNarrow` before app code reads command, environment, extension, or disabled fields.
- Matching formatter enabled checks run in parallel through `Promise.all`, while commands for the same file run sequentially.
- `$FILE` substitution happens immediately before process execution.
- Command execution is behind an injectable `FormatterRunner`; the default runner uses Node `spawnSync` through the existing host process seam.

Smoke coverage lives in `opencodehx.smoke.FormatterSmoke`. It covers default/no-config status behavior, disabled/no-op file formatting, object config, linked `ruff`/`uv` disables, per-directory status isolation, parallel enabled checks, sequential command ordering, command cwd/env forwarding, `$FILE` substitution, and a real Node-backed two-command file mutation from `x` to `xAB`.

## Boundaries

`ConfigInfo.formatter` still stores the merged raw config value because `ConfigLoader` owns top-level discovery and merge precedence. `FormatRuntime` owns formatter-specific narrowing, defaults, and command execution. Its constructor remains the raw config boundary; internal formatter fields are copied into typed records before use. Broader route integration for `/formatter` belongs to the server/API surface, not this service slice.
