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
- Best-effort `$schema` write-back for file-backed configs without expanding `{env:...}` or `{file:...}` tokens into the persisted file.
- Typed plugin specs for string and `[specifier, options]` config entries, aligned plugin origins, and upstream-style later-wins deduplication by package identity or exact file URL.
- Legacy `theme`, `keybinds`, and `tui` stripping from main OpenCode config.
- Strict top-level key rejection for the known upstream config field set.
- Typed provider config records for provider entries, model entries, model API override, modalities, cost, limits, headers, variants, whitelist, and blacklist. Provider SDK `options` and `variants` stay open as documented passthrough maps.
- Typed permission config as the upstream-shaped `permission -> action | pattern map` record, with runtime narrowing isolated in `PermissionRules.fromConfig`.
- Narrow Node fs/os externs used only by the config smoke and host boundary.

Smoke coverage lives in `opencodehx.smoke.ConfigSmoke` and exercises missing config defaults, JSONC precedence, env substitution, file substitution, `$schema` auto-add with raw token preservation, plugin merge/dedup/origin alignment, legacy TUI key stripping, ancestor and `.opencode` discovery, `OPENCODE_CONFIG_DIR`, project config disable behavior, invalid JSON, and invalid schema fields.

## Deliberate Boundaries

Provider and permission config are now typed at the Haxe boundary because their owner slices exist. Provider `options`, model `options`, headers, and variants remain open maps only where upstream treats them as provider-SDK passthrough data.

Agent, MCP, formatter, LSP, command, skills, watcher, tools, enterprise, compaction, layout, and experimental nested shapes are still accepted as documented boundary debt because their authoritative schemas belong to later port slices. They should be tightened as those modules are ported.

Plugin options remain open passthrough maps because upstream models them as `Record<string, unknown>` for plugin packages to consume. This slice does not resolve path plugin targets, load plugin modules, install npm dependencies, or scan plugin directories; those belong to the plugin/runtime slices.

This slice does not reimplement upstream's Effect service layer, remote account config, npm dependency install side effects, global config migration, agent/command/skill directory discovery, or TUI migration. Those should be added when the dependent session/provider/server/TUI slices need them.

## genes-ts Lesson

Using Haxe std `Reflect.fields` exposed a generic `genes-ts` issue: `haxe.extern.Rest<T>` aliases could leak into generated TS expression casts as `Rest<T>`. The fix landed in `../genes` commit `7ccc162886aa35e925fdc06fa995058d870f45a6`, with a full-suite guard against `unsafeCast<Rest<...>>`.
