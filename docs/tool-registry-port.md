# Tool Registry Port

**Bead:** `opencodehx-016`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/tool.ts`, `registry.ts`, `invalid.ts`, `glob.ts`, `grep.ts`, and `../opencode/packages/opencode/test/tool/{registry,glob,grep}.test.ts`

## Slice

This slice adds the first Haxe-owned tool surface:

- `ToolDef`, `ToolSchema`, `ToolContext`, and `ToolResult` records.
- `ToolException` with explicit `UnknownTool`, `DisabledTool`, `InvalidArguments`, and `ExecutionFailed` failure variants.
- `ToolRegistry` with builtin ids, lookup, disabled filtering, and invocation.
- `KnownToolID` plus `ToolIDs.known("...")` for source-authored fixed tool references. The registry still accepts raw `String` values at runtime so model-emitted, plugin, config, and unknown-tool failure paths remain boundary data.
- Initial `invalid`, `glob`, and `grep` tool definitions.
- `ToolSmoke` coverage for builtin ids, schema fields, unknown/disabled failures, invalid argument text, glob directory rejection, glob file matching, grep directory/file search, and no-match output.

## Deliberate Boundaries

This is not the full upstream Effect/Zod/plugin registry. Dynamic description hooks, provider/model filtering, plugin-defined tools, truncation integration, LSP/MCP tools, bash/PTY, and task/subagent descriptions are deferred to their owning beads. Core file tool permissions and read/write/edit/apply_patch scaffolding live in `docs/core-file-tools-port.md`.

The registry keeps validation explicit rather than depending on Zod externs. If more tools repeat schema boilerplate, derive simple validators with a macro instead of expanding broad `Dynamic` usage.

`npm run macro:diagnostics` includes a generated negative Haxe fixture for `ToolIDs.known("grepp")`, proving typos in source-authored tool IDs fail at compile time. `opencodehx-zot` tracks the remaining checked-string audit for provider/model IDs, event discriminants, config keys, resource names, fixture/snapshot targets, and generated file targets.
