# Session Processor One-Turn Slice

`opencodehx-022` introduces the first storage-backed one-turn session processor.

## What Landed

- `opencodehx.session.SessionProcessor` creates deterministic user and assistant messages from the fake provider.
- The headless `run` command now emits its JSON transcript through the processor instead of constructing messages directly in the harness.
- Optional tool execution records upstream-shaped `step-start`, `tool`, `text`, and `step-finish` assistant parts.
- Tool calls run through `ToolRegistry` and can use `PermissionRuntime.toToolAsk()` for the current synchronous tool surface.
- When a `SessionStore` is supplied, the processor upserts project/session metadata and persists messages plus parts.
- `SessionProcessorSmoke` covers model stream events, a permission-approved `read` call, final assistant text, and SQLite hydration.

## Current Boundary

The processor is deliberately synchronous because the fake provider, permission runtime, and tool registry are synchronous today. That keeps the fixture deterministic and gives the next provider/server/TUI work a concrete contract. When provider streams become async, keep the pure message-building helpers and promote only the event/tool execution edge.

## Haxe Modeling Notes

- `SessionToolCall` and `SessionToolOutcome` are typed records rather than broad `Dynamic`, while individual tool inputs remain dynamic at the npm/OpenCode boundary.
- Assistant tool lifecycle uses the existing `ToolState` enum so illegal status strings do not leak into Haxe source.
- The no-tool path preserves the original golden transcript IDs and timestamps to keep upstream differential evidence stable.
