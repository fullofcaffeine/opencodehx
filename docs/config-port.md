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
- `OPENCODE_CONFIG` and `OPENCODE_CONFIG_CONTENT` overlays for early env-driven parity.
- Legacy `theme`, `keybinds`, and `tui` stripping from main OpenCode config.
- Strict top-level key rejection for the known upstream config field set.
- Narrow Node fs/os externs used only by the config smoke and host boundary.

Smoke coverage lives in `opencodehx.smoke.ConfigSmoke` and exercises missing config defaults, JSONC precedence, env substitution, file substitution, legacy TUI key stripping, invalid JSON, and invalid schema fields.

## Deliberate Boundaries

Provider, agent, MCP, formatter, LSP, command, tools, permission, enterprise, compaction, and experimental nested shapes are accepted as `Dynamic` for now because their authoritative schemas belong to later port slices. They remain boundary debt and should be tightened as those modules are ported.

This slice does not reimplement upstream's Effect service layer, remote account config, plugin origin provenance, npm dependency install side effects, global config migration, or `.opencode` directory discovery. Those should be added when the dependent session/provider/server slices need them.

## genes-ts Lesson

Using Haxe std `Reflect.fields` exposed a generic `genes-ts` issue: `haxe.extern.Rest<T>` aliases could leak into generated TS expression casts as `Rest<T>`. The fix landed in `../genes` commit `7ccc162886aa35e925fdc06fa995058d870f45a6`, with a full-suite guard against `unsafeCast<Rest<...>>`.
