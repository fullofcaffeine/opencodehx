# Config Port

**Bead:** `opencodehx-011`  
**Upstream oracle:** `../opencode/packages/opencode/src/config/*` and `../opencode/packages/opencode/test/config/config.test.ts`

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
- Best-effort `$schema` write-back for file-backed configs without expanding `{env:...}` or `{file:...}` tokens into the persisted file.
- Typed plugin specs for string and `[specifier, options]` config entries, aligned plugin origins, and upstream-style later-wins deduplication by package identity or exact file URL.
- Auto-discovered local plugin files from `plugin/*.{ts,js}` and `plugins/*.{ts,js}` under `.opencode` and `OPENCODE_CONFIG_DIR`, normalized to file URL specs with local/global provenance.
- Global config loading with upstream precedence (`config.json`, then `opencode.json`, then `opencode.jsonc`), and global update target selection (`opencode.jsonc`, `opencode.json`, `config.json`, falling back to a new `opencode.jsonc`).
- Local config updates that merge writable config into `config.json`, matching the server route's instance update target.
- JSONC-preserving global updates through upstream's `jsonc-parser` behavior, with plugin provenance omitted from persisted config.
- Best-effort legacy global TOML migration from extensionless `config`, including `provider`/`model` to `model` translation, modern `config.json` write-back, and legacy file removal.
- Markdown-backed command discovery from `command/**/*.md` and `commands/**/*.md`, including nested path-derived names and typed command records.
- Markdown-backed agent discovery from `agent/**/*.md` and `agents/**/*.md`, including nested path-derived names, typed agent records, tool-to-permission migration, color, options passthrough, and primary-mode promotion.
- Markdown-backed mode discovery from `mode/*.md` and `modes/*.md`, promoted into `agent` entries with `mode: "primary"` like upstream.
- Legacy `theme`, `keybinds`, and `tui` stripping from main OpenCode config.
- Strict top-level key rejection for the known upstream config field set.
- Typed provider config records for provider entries, model entries, model API override, modalities, cost, limits, headers, variants, whitelist, and blacklist. Provider SDK `options` and `variants` stay open as documented passthrough maps.
- Typed permission config as the upstream-shaped `permission -> action | pattern map` record, with runtime narrowing isolated in `PermissionRules.fromConfig`.
- Typed `skills` config for local extra skill paths and remote skill index URLs. Local path consumption is covered by `docs/skill-registry-port.md`; remote URL discovery is deferred.
- Narrow Node fs/os/url externs used only by the config smoke and host boundary.

Smoke coverage lives in `opencodehx.smoke.ConfigSmoke` and exercises missing config defaults, JSONC precedence, env substitution, file substitution, remote well-known config, remote account config token substitution, `$schema` auto-add with raw token preservation, plugin merge/dedup/origin alignment, plugin directory discovery, global load/update precedence, JSONC comment-preserving global writes, legacy global TOML migration, local `config.json` writes, command/agent/mode markdown discovery, legacy TUI key stripping, ancestor and `.opencode` discovery, `OPENCODE_CONFIG_DIR`, project config disable behavior, invalid JSON, and invalid schema fields.

## Deliberate Boundaries

Provider and permission config are now typed at the Haxe boundary because their owner slices exist. Provider `options`, model `options`, headers, and variants remain open maps only where upstream treats them as provider-SDK passthrough data.

MCP, formatter, LSP, watcher, tools, enterprise, compaction, layout, and experimental nested shapes are still accepted as documented boundary debt because their authoritative schemas belong to later port slices. They should be tightened as those modules are ported.

Markdown frontmatter is intentionally typed as an `unknown` boundary at parse time. Command and agent loaders immediately narrow the fields they own into typed Haxe records; unknown agent frontmatter keys survive only through the documented `options` passthrough.

Plugin options remain open passthrough maps because upstream models them as `Record<string, unknown>` for plugin packages to consume. This slice does not resolve path plugin targets, load plugin modules, or install npm dependencies; those belong to the plugin/runtime slices.

This slice does not reimplement upstream's Effect service layer, the real account repo/service, npm dependency install side effects, remote skill URL downloads, plugin runtime loading/path resolution, or TUI migration. Those should be added when the dependent account/session/provider/server/TUI slices need them.

The writable JSON tree in `ConfigWriter` is intentionally typed as an `unknown` boundary in generated TypeScript. It exists only to round-trip arbitrary JSON/JSONC fields whose owning modules are not ported yet; app-facing code should stay on `ConfigInfo` and typed nested records.

## genes-ts Lesson

Using Haxe std `Reflect.fields` exposed a generic `genes-ts` issue: `haxe.extern.Rest<T>` aliases could leak into generated TS expression casts as `Rest<T>`. The fix landed in `../genes` commit `7ccc162886aa35e925fdc06fa995058d870f45a6`, with a full-suite guard against `unsafeCast<Rest<...>>`.
