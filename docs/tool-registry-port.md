# Tool Registry Port

**Bead:** `opencodehx-016`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/tool.ts`, `registry.ts`, `invalid.ts`, `glob.ts`, `grep.ts`, and `../opencode/packages/opencode/test/tool/{registry,glob,grep}.test.ts`

## Slice

This slice adds the first Haxe-owned tool surface:

- `ToolDef`, `ToolSchema`, `ToolContext`, and `ToolResult` records.
- `ToolException` with explicit `UnknownTool`, `DisabledTool`, `InvalidArguments`, and `ExecutionFailed` failure variants.
- `ToolRegistry` with builtin ids, lookup, disabled filtering, and invocation.
- Initial `invalid`, `glob`, and `grep` tool definitions.
- `ToolSmoke` coverage for builtin ids, schema fields, unknown/disabled failures, invalid argument text, glob directory rejection, glob file matching, grep directory/file search, and no-match output.

## Deliberate Boundaries

This is not the full upstream Effect/Zod/plugin registry. Dynamic description hooks, provider/model filtering, plugin-defined tools, truncation integration, permissions, LSP/MCP tools, bash/PTY, edit/write/apply_patch, and task/subagent descriptions are deferred to their owning beads.

The registry keeps validation explicit rather than depending on Zod externs. If more tools repeat schema boilerplate, derive simple validators with a macro instead of expanding broad `Dynamic` usage.
