# Config Port

**Bead:** `opencodehx-011`  
**Upstream oracle:** `../opencode/packages/opencode/src/config/*`, `../opencode/packages/opencode/test/config/config.test.ts`, and `../opencode/packages/opencode/test/config/agent-color.test.ts`

## Slice

This slice starts the Haxe-owned config core without pulling in upstream Effect/Zod wholesale.

Implemented:

- `opencodehx.config.ConfigInfo` as the authoritative Haxe model for early config fields.
- Haxe enums for closed config domains: `ShareMode` and `AutoUpdate`.
- JSONC parsing with comment stripping and trailing-comma support.
- Variable substitution for `{env:NAME}` and `{file:path}` at the config boundary.
- Project load order where `opencode.jsonc` overrides `opencode.json` in the same directory.
- Ancestor project config discovery from worktree root to leaf, followed by discovered `.opencode/opencode.{json,jsonc}` directories.
- `OPENCODE_DISABLE_PROJECT_CONFIG` skips project and `.opencode` discovery while still allowing explicit config inputs.
- `OPENCODE_CONFIG_DIR` loads `opencode.{json,jsonc}` as an explicit directory source and overrides project-local config in this early slice.
- `OPENCODE_CONFIG` and `OPENCODE_CONFIG_CONTENT` overlays for early env-driven parity.
- Remote well-known config loading from authenticated `/.well-known/opencode` URLs through the async loader, including trailing-slash normalization, token env substitution, default `$schema`, and project-over-remote precedence.
- Remote active account/org config as an explicit async loader source, including `OPENCODE_CONSOLE_TOKEN` injection for config-template substitution and account-config-over-project precedence.
- Managed config source parsing for MDM/mobileconfig JSON, including metadata-key stripping and final managed-over-user precedence through an explicit loader source.
- Best-effort `$schema` write-back for file-backed configs without expanding `{env:...}` or `{file:...}` tokens into the persisted file.
- Typed plugin specs for string and `[specifier, options]` config entries, aligned plugin origins, and upstream-style later-wins deduplication by package identity or exact file URL.
- Auto-discovered local plugin files from `plugin/*.{ts,js}` and `plugins/*.{ts,js}` under `.opencode` and `OPENCODE_CONFIG_DIR`, normalized to file URL specs with local/global provenance.
- File-backed path-like plugin specs (`file://`, relative `.` specs, absolute POSIX paths, and Windows-drive paths) resolve relative to the config file that declared them before merge/dedupe, including package-directory and index-file target handling.
- Global config loading with upstream precedence (`config.json`, then `opencode.json`, then `opencode.jsonc`), and global update target selection (`opencode.jsonc`, `opencode.json`, `config.json`, falling back to a new `opencode.jsonc`).
- Local config updates that merge writable config into `config.json`, matching the server route's instance update target.
- JSONC-preserving global updates through upstream's `jsonc-parser` behavior, with plugin provenance omitted from persisted config.
- Best-effort legacy global TOML migration from extensionless `config`, including `provider`/`model` to `model` translation, modern `config.json` write-back, and legacy file removal.
- Markdown-backed command discovery from `command/**/*.md` and `commands/**/*.md`, including nested path-derived names and typed command records.
- Markdown-backed agent discovery from `agent/**/*.md` and `agents/**/*.md`, including nested path-derived names, typed agent records, tool-to-permission migration, color, options passthrough, and primary-mode promotion.
- Markdown-backed mode discovery from `mode/*.md` and `modes/*.md`, promoted into `agent` entries with `mode: "primary"` like upstream.
- Markdown parser parity for `@file` reference extraction and frontmatter fallback behavior, including comments, colon-heavy values, block scalars, empty values, empty/no-frontmatter files, Markdown-header-only files, weird model IDs, nested tool maps, and content preservation.
- Project JSON agent color parsing, config-backed agent lookup through the minimal `AgentRuntime.get` facade, and strict `Color.hexToAnsiBold` conversion for `#RRGGBB` inputs.
- Legacy `theme`, `keybinds`, and `tui` stripping from main OpenCode config.
- Strict top-level key rejection for the known upstream config field set.
- Typed provider config records for provider entries, model entries, model API override, modalities, cost, limits, headers, variants, whitelist, and blacklist. Provider SDK `options` and `variants` stay open as documented passthrough maps.
- Typed permission config as the upstream-shaped `permission -> action | pattern map` record, with runtime narrowing isolated in `PermissionRules.fromConfig`.
- LSP config refinement for the upstream boundary rule: boolean toggles pass, builtin server IDs such as `typescript` can omit `extensions`, disabled custom servers can omit `extensions`, and enabled custom servers must declare an `extensions` array.
- Typed top-level legacy `tools` config as `tool -> enabled` and normalize it into `permission`, with write/edit/patch collapsing to `edit` and explicit permission config taking precedence.
- Final config normalization for `OPENCODE_PERMISSION`, deprecated `autoshare: true` to `share: "auto"`, and `OPENCODE_DISABLE_AUTOCOMPACT` / `OPENCODE_DISABLE_PRUNE` compaction overrides.
- Environment reads for config loading and `{env:...}` substitution now go through the `NodeProcess` host seam. That keeps platform-specific `process.env` behavior and raw Node access centralized instead of embedding `js.Syntax.code` in config logic.
- Focused TUI config loading from global `tui.{json,jsonc}`, `OPENCODE_TUI_CONFIG`, project `tui.{json,jsonc}`, and discovered `.opencode/tui.{json,jsonc}` sources.
- TUI config normalization covers nested `tui` flattening, top-level override precedence, keybind merges, plugin spec merge/dedup by package identity, tuple option preservation, plugin provenance, and `plugin_enabled` merges.
- Legacy TUI migration moves `theme`, `keybinds`, and nested `tui` values out of `opencode.{json,jsonc}` into `tui.json`, writes a backup, strips migrated keys from the main config, and drops unknown nested TUI keys.
- Typed `skills` config for local extra skill paths and remote skill index URLs. Local path consumption and remote URL discovery/cache behavior are covered by `docs/skill-registry-port.md`.
- Narrow Node fs/os/url externs used only by the config smoke and host boundary.

Smoke coverage lives in `opencodehx.smoke.ConfigSmoke` and is grouped around:

- Config discovery and merge order: missing defaults, JSONC precedence, ancestor and `.opencode` discovery, `OPENCODE_CONFIG_DIR`, project config disable behavior, and invalid JSON/schema fields.
- Substitution and remote sources: env substitution, file substitution, remote well-known config, remote account config token substitution, managed config metadata stripping, and `$schema` auto-add with raw token preservation.
- Plugin and dependency config: plugin merge/dedup/origin alignment, plugin directory discovery, plugin path resolution, and dependency bootstrap gitignore/install success/failure behavior.
- User-authored config files: markdown file-reference/frontmatter parsing, command/agent/mode discovery, JSON project agent colors, config-backed agent lookup color propagation, and LSP config refinement.
- Writable and legacy config paths: global load/update precedence, JSONC comment-preserving global writes, legacy global TOML migration, local `config.json` writes, top-level legacy tools migration, env-driven finalization flags, and legacy TUI key stripping.
- Focused TUI config: `tui.json` precedence, keybind/plugin/plugin-enabled merges, tuple plugin options, nested `tui` flattening, legacy migration backup/strip behavior, and env/file substitution.

`UtilSmoke` covers strict color hex-to-ANSI conversion and invalid hex/theme inputs.

## Deliberate Boundaries

Provider and permission config are now typed at the Haxe boundary because their owner slices exist. Provider `options`, model `options`, headers, and variants remain open maps only where upstream treats them as provider-SDK passthrough data.

MCP, watcher, enterprise, layout, and experimental nested shapes are still accepted as documented boundary debt because their authoritative schemas belong to later port slices. LSP config now has the upstream custom-server refinement at the config boundary, but `ConfigInfo.lsp` still stores the raw nested config until the live LSP process/download slice owns the full runtime schema. Formatter config is still stored raw in `ConfigInfo` after merge, but `FormatRuntime` now narrows the formatter-specific shape at the service boundary. Compaction is typed for the upstream-owned scalar fields used by config finalization. Other nested shapes should be tightened as those modules are ported.

Markdown frontmatter is intentionally typed as an `unknown` boundary at parse time. Command and agent loaders immediately narrow the fields they own into typed Haxe records; unknown agent frontmatter keys survive only through the documented `options` passthrough.

Plugin options remain open passthrough maps because upstream models them as `Record<string, unknown>` for plugin packages to consume. Path-like specs are normalized for file-backed config loads, but this slice does not load plugin modules or install npm dependencies; those belong to the plugin/runtime slices.

This slice does not reimplement upstream's Effect service layer, the real account repo/service, platform-specific managed preference discovery, live npm package-manager side effects, plugin runtime loading, full TUI service/runtime layering, Windows-specific keybind platform cases, or readonly migration-strip fallback behavior. Dependency bootstrap is represented by a typed `ConfigDependencyRuntime` seam and deterministic smoke fixture; live package-manager harnessing should stay opt-in.

The writable JSON tree in `ConfigWriter` is intentionally typed as an `unknown` boundary in generated TypeScript. It exists only to round-trip arbitrary JSON/JSONC fields whose owning modules are not ported yet; app-facing code should stay on `ConfigInfo` and typed nested records.

## genes-ts Lesson

Using Haxe std `Reflect.fields` exposed a generic `genes-ts` issue: `haxe.extern.Rest<T>` aliases could leak into generated TS expression casts as `Rest<T>`. The fix landed in `../genes` commit `7ccc162886aa35e925fdc06fa995058d870f45a6`, with a full-suite guard against `unsafeCast<Rest<...>>`.
