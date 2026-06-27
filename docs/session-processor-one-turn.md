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
- `SessionLlm.hasToolCalls` ports the pure upstream `session.llm.hasToolCalls` helper over typed AI SDK prompt messages, including string-content, text-only, tool-call, tool-result, and mixed-content cases.
- `SessionLlm.resolveTools` ports the upstream active-tool filtering rule: agent and prompt permissions are merged in order, prompt permissions can re-enable a tool denied by the agent, and `user.tools[name] === false` still hides a tool.
- `SessionLlm.compatibilityTools` ports the upstream LiteLLM/GitHub Copilot compatibility rule that injects a `_noop` AI SDK tool only when active tools are empty and message history already contains tool-call/tool-result content.
- `SessionLlm.requestHeaders` ports the upstream streaming request header assembly rule, including the `opencode*` provider branch, default session affinity/user-agent headers, optional parent session IDs, and model/plugin header override order.
- `SessionLlm.composeSystem`, `finalizeSystemTransform`, and `requestMessages` port the upstream system-message assembly seam: agent prompts replace provider prompts, call/user system fragments append in order, plugin-added system fragments rejoin when the original header remains first, and OpenAI OAuth/workflow requests skip synthetic system-message prepending.
- `SessionLlm.activeToolNames` and `workflowPreapprovedTools` port two upstream tool-selection rules around `streamText`: the repair-only `invalid` tool is excluded from active tools, and GitLab workflow preapproval follows last-matching permission rules while only `ask` requires approval.
- `SessionLlm.workflowApprovalNames`, `workflowApprovalPatterns`, `workflowAlreadyApproved`, and `rememberWorkflowApproval` port the pure GitLab workflow approval-shaping rules: unique tool names gate repeat approval, approval prompt patterns prefer JSON `title ?? name` values when truthy, invalid JSON falls back to the tool name, and accepted tool names append to the session preapproval list.
- `SessionLlm.workflowUnknownToolResult`, `workflowToolExecutionResult`, and `workflowToolExecutionError` port the pure GitLab workflow tool-executor result shaping: unknown tools return the upstream error string, string tool results pass through, object tool results prefer `output` with `title`/`metadata`, objects without `output` use the JSON fallback, and caught errors expose the user-facing message.
- `SessionLlm.repairToolCall` ports the upstream `experimental_repairToolCall` decision: case-only tool-name misses are repaired to a registered lower-case tool, while other failures are routed to the `invalid` tool with a JSON error payload.
- `SessionLlm.requestOptions` ports the upstream request-option assembly seam: provider-transform base options merge with model options, agent options, and selected model variants in order; small requests use `smallOptions` and skip variants; OpenAI OAuth requests receive joined system `instructions`.
- `SessionLlm.requestParams` ports the upstream chat parameter defaults: agent temperature/topP override provider transforms, unsupported temperature emits absent, topK/maxOutputTokens come from `ProviderTransform`, and the assembled provider options are forwarded unchanged.
- `SessionLlm.transformStreamPrompt` ports the upstream AI SDK middleware branch that applies `ProviderTransform.message` only for stream requests and leaves non-stream prompt params untouched.
- `SessionLlm.telemetryOptions` ports the pure `experimental_telemetry` assembly for `streamText`: OpenTelemetry enablement remains `undefined` unless configured, `functionId` is `session.llm`, tracer is an unknown passthrough, and metadata uses the configured username or `unknown`.
- The async path now dispatches the first model-emitted AI SDK tool call through the existing `ToolRegistry`/permission-aware tool execution path, normalizing parsed JSON or JSON-string tool input before tool schema validation.
- The async path advertises the live `ToolRegistry` to `streamText` by translating Haxe `ToolDef` parameter records into AI SDK JSON Schema tools without `execute`; model calls can see tool schemas, while execution stays in the OpenCodeHX registry/permission path.
- After successful model-emitted tool calls, the async path performs bounded repeated `streamText` follow-up calls with deterministic tool-result continuation prompts and replaces the assistant text with the final answer. This is continuation evidence, not the full upstream message-history loop.
- `SessionExport` emits the upstream CLI export data shape `{ info, messages }` from a `SessionStore`, using `MessageCodec.encodeWithParts` for message DTOs and an opt-in sanitization pass for session title/directory plus known text/file/snapshot-style part payloads.
- `Cli.runAsync` and `run --mock-ai-sdk` exercise that bridge from the generated CLI process while remaining credential-free.
- `SessionPersistenceSmoke` covers store-backed export and sanitized export fixtures, while `SessionProcessorSmoke` covers the pure LLM tool-call detector, active-tool permission filtering, tool-call repair/fallback, request-option merge order, chat parameter assembly, stream-prompt transform branching, telemetry option assembly, workflow approval shaping, workflow tool-executor result/error shaping, `_noop` compatibility tool injection/skipping, active-tool-name filtering, workflow preapproval rule matching, streaming request header assembly, system-message assembly/transform/request-message branching, model stream events, a permission-approved `read` call, final assistant text, retry status/part creation, context-overflow compaction markers, abort recording, SQLite hydration, recovery through the persisted `SessionStore`, a credential-free AI SDK mock-model session run, AI SDK-emitted tool-call dispatch, provider-call evidence that registry tools are advertised to the model, and repeated follow-up model calls after successful tool results.

## Current Boundary

The default headless CLI path remains deliberately fake-provider based so transcript parity stays deterministic. The session module now also has an async AI SDK path with tool schema advertisement, repeated tool-call dispatch, bounded follow-up model calls after successful tool results, and server/client resume evidence through persisted messages. Live CLI chat still needs cancellation, retry scheduling, and upstream prompt/message-history construction before it can be called bootable as an agentic client.

This is not the full upstream Effect session loop yet. Live provider streaming, retry scheduling, async cancellation propagation, automatic compaction continuation, full prompt/message-history construction, the interactive export command, and the broader CLI import flow remain later session/provider/CLI slices.

## Haxe Modeling Notes

- `SessionToolCall` and `SessionToolOutcome` are typed records rather than broad `Dynamic`, while individual tool inputs remain dynamic at the npm/OpenCode boundary.
- Retryable provider failures are a typed Haxe enum first; only the final retry-part error payload is serialized into the upstream JSON shape.
- Compaction decisions are pure Haxe functions over typed `ConfigInfo`, `ProviderModel`, and `TokenUsage` records, so overflow behavior can be retargeted without TypeScript runtime assumptions.
- Assistant tool lifecycle uses the existing `ToolState` enum so illegal status strings do not leak into Haxe source.
- Session stream/status events are a typed structural record (`SessionEvent`) rather than broad `Dynamic`, while still encoding the upstream JSON event field names. This keeps generated TypeScript at `SessionEvent[]` instead of `any[]` for normal event handling.
- `SessionLlm.requestOptions` intentionally owns a localized `ProviderOptions` deep-merge boundary because upstream and provider SDKs treat those records as open `Record<string, any>` passthrough data; stable request fields remain typed outside that merge.
- `SessionLlm.workflowApprovalPatterns` parses provider-supplied workflow tool args as `genes.ts.Unknown` and narrows only the optional `title`/`name` fields needed for upstream prompt text. Missing/null title falls through to name like upstream `??`; falsey non-null values do not.
- `SessionLlm.workflowToolExecutionResult` accepts the raw provider/tool boundary value as `genes.ts.Unknown`, narrows the stable string/title/output cases, preserves metadata as unknown passthrough data, and keeps JSON fallback stringification localized to the GitLab workflow executor seam.
- `SessionLlm.telemetryOptions` keeps the OpenTelemetry tracer as `genes.ts.Unknown` because the real tracer is owned by the Effect/OpenTelemetry runtime; stable telemetry metadata remains typed.
- The no-tool path preserves the original golden transcript IDs and timestamps to keep upstream differential evidence stable.
- Non-default fixture sessions derive message/part IDs from the session ID so persisted multi-session recovery does not collide on primary keys.
