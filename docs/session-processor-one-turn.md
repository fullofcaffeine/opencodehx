# Session Processor One-Turn Slice

`opencodehx-022` introduces the first storage-backed one-turn session processor.

## What Landed

- `opencodehx.session.SessionProcessor` creates deterministic user and assistant messages from the fake provider.
- The headless `run` command now emits its JSON transcript through the processor instead of constructing messages directly in the harness.
- Optional tool execution records upstream-shaped `step-start`, `tool`, `text`, and `step-finish` assistant parts.
- Tool calls run through `ToolRegistry` and can use `PermissionRuntime.toToolAsk()` for the current synchronous tool surface.
- When a `SessionStore` is supplied, the processor upserts project/session metadata and persists messages plus parts.
- `SessionRetry` models the first provider retry classification/backoff rules, including retry headers, 5xx retryability, context-overflow non-retry, JSON rate-limit messages, and plain-text rate-limit patterns.
- `SessionCompaction` models usable context and overflow decisions from provider model limits plus config compaction settings, and can create upstream-shaped compaction parts for the current fixture processor.
- `SessionProcessor.runAiSdk` is the first async provider/session bridge. It accepts a typed `AiLanguageModel`, consumes `AiSdkProvider.stream`, maps SDK text/tool/error/finish events into the session event shape, and reuses the same user/assistant message construction path.
- `Cli.runAsync` and `run --mock-ai-sdk` exercise that bridge from the generated CLI process while remaining credential-free.
- `SessionProcessorSmoke` covers model stream events, a permission-approved `read` call, final assistant text, retry status/part creation, context-overflow compaction markers, abort recording, SQLite hydration, recovery through the persisted `SessionStore`, and a credential-free AI SDK mock-model session run.

## Current Boundary

The default headless CLI path remains deliberately fake-provider based so transcript parity stays deterministic. The session module now also has an async AI SDK path, but live CLI chat still needs model selection, auth/config loading, cancellation, retry scheduling, tool-call dispatch from model output, and upstream prompt construction before it can be called bootable as an agentic client.

This is not the full upstream Effect session loop yet. Live provider streaming, retry scheduling, async cancellation propagation, automatic compaction continuation, full prompt construction, and resume/import/export UX remain later session/provider slices.

## Haxe Modeling Notes

- `SessionToolCall` and `SessionToolOutcome` are typed records rather than broad `Dynamic`, while individual tool inputs remain dynamic at the npm/OpenCode boundary.
- Retryable provider failures are a typed Haxe enum first; only the final retry-part error payload is serialized into the upstream JSON shape.
- Compaction decisions are pure Haxe functions over typed `ConfigInfo`, `ProviderModel`, and `TokenUsage` records, so overflow behavior can be retargeted without TypeScript runtime assumptions.
- Assistant tool lifecycle uses the existing `ToolState` enum so illegal status strings do not leak into Haxe source.
- Session stream/status events are a typed structural record (`SessionEvent`) rather than broad `Dynamic`, while still encoding the upstream JSON event field names. This keeps generated TypeScript at `SessionEvent[]` instead of `any[]` for normal event handling.
- The no-tool path preserves the original golden transcript IDs and timestamps to keep upstream differential evidence stable.
- Non-default fixture sessions derive message/part IDs from the session ID so persisted multi-session recovery does not collide on primary keys.
