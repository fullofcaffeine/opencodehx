# Tool Registry Port

**Bead:** `opencodehx-016`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/tool.ts`, `registry.ts`, `invalid.ts`, `glob.ts`, `grep.ts`, `question.ts`, `webfetch.ts`, and `../opencode/packages/opencode/test/tool/{registry,glob,grep,question,webfetch}.test.ts`

## Slice

This slice adds the first Haxe-owned tool surface:

- `ToolDef`, `ToolSchema`, `ToolContext`, and `ToolResult` records.
- `ToolException` with explicit `UnknownTool`, `DisabledTool`, `InvalidArguments`, and `ExecutionFailed` failure variants.
- `ToolRegistry` with builtin ids, lookup, disabled filtering, and invocation.
- `KnownToolID` plus `ToolIDs.known("...")` for source-authored fixed tool references. The registry still accepts raw `String` values at runtime so model-emitted, plugin, config, and unknown-tool failure paths remain boundary data.
- `ToolCallInput` for the registry's JSON/tool-call boundary, with built-in tools decoding into typed Haxe input records before application logic runs.
- Initial `invalid`, `glob`, and `grep` tool definitions.
- `QuestionTool` as an async Haxe runtime over `QuestionRuntime`, including nested question decoding, pending request metadata, answer formatting, and answer metadata.
- `WebFetchTool` as an async Haxe runtime for text responses, SVG text passthrough, and image file attachments. It is not registered in the synchronous `ToolRegistry` yet.
- Typed `ToolResultAttachment` file records plus session processor propagation into completed tool-state attachments.
- `ToolDefinition` coverage for fresh object/factory init snapshots without mutating source-authored definitions.
- `ToolSmoke` coverage for builtin ids, schema fields, unknown/disabled failures, invalid argument text, glob directory rejection, glob file matching, grep directory/file search, no-match output, question ask/reply output, webfetch text/SVG/image handling, and `ToolDefinition` fresh-init behavior.

## Deliberate Boundaries

This is not the full upstream Effect/Zod/plugin registry. Dynamic description hooks, provider/model filtering, plugin-defined tools, full `Tool.define` Effect/Zod wrapping, truncation service file-spill/cleanup behavior, LSP/MCP tools, bash/PTY, and task/subagent descriptions are deferred to their owning beads. `QuestionTool` and `WebFetchTool` are async and remain outside the synchronous registry/session tool loop until async tool execution lands. Core file tool permissions and read/write/edit/apply_patch scaffolding live in `docs/core-file-tools-port.md`.

The registry keeps validation explicit rather than depending on Zod externs. Built-ins receive typed inputs; only the registry edge handles unknown tool-call JSON. If more tools repeat schema boilerplate, derive simple validators with a macro instead of expanding broad weak typing.

`npm run typed-boundary:scan` tracks the remaining `Dynamic`, `DynamicAccess`, `cast`, `untyped`, raw `Syntax.code`, `@:ts.type`, and reflection debt across product source. Its baseline is a ratchet: reductions pass, but new or increased weak markers fail until justified.

`npm run macro:diagnostics` includes a generated negative Haxe fixture for `ToolIDs.known("grepp")`, proving typos in source-authored tool IDs fail at compile time. The current checked-string audit status for provider IDs, event discriminants, resource names, JS harness generated targets, and deliberate boundary strings is tracked in `docs/checked-artifact-constructors.md`.
