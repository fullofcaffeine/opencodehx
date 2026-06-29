# Message V2 Port

**Bead:** `opencodehx-013`  
**Upstream oracle:** `../opencode/packages/opencode/src/session/schema.ts`, `../opencode/packages/opencode/src/session/message-v2.ts`, and `../opencode/packages/opencode/test/session/message-v2.test.ts`

## Slice

This starts the Haxe-owned Session/Message V2 DTO layer:

- String newtypes for `SessionID`, `MessageID`, and `PartID`.
- Haxe discriminated enums for `Info`, `Part`, `ToolState`, `FilePartSource`, and `OutputFormat`.
- Stored JSON codec for `WithParts` that validates upstream `role`, `type`, and `status` discriminants.
- Cursor encode/decode parity using Node `base64url`.
- Smoke coverage for user text parts, assistant tool completion with attachments, JSON-schema output format retry defaulting, cursor roundtrip, and unknown part rejection.

## Current Evidence

`SessionProcessorSmoke` now also exercises Message V2 records after storage recovery in the live AI SDK path. The recovered prompt carries text parts, provider metadata for same-model assistant/tool history, compaction/subtask synthetic prompts, non-text/non-directory user file parts, assistant tool-call/tool-result history, media-capable completed tool-result attachments, unsupported-provider synthetic media injection, interrupted tool output, and normal tool errors through public AI SDK `ModelMessage[]` into the converted provider prompt. A focused Anthropic fixture proves recovered media tool-result history survives `ProviderTransform.message(...)` at the inspected provider prompt boundary.

Full upstream `MessageV2.toModelMessages(...)` parity is still partial. Remaining edges are broader prompt/session lifecycle cases outside the focused recovered-history bridge.

## Deliberate Boundaries

Provider IDs, model IDs, LSP ranges, snapshot diffs, assistant errors, tool inputs, tool metadata, and structured provider payloads are kept as boundary-shaped `String` or `Dynamic` fields for now. Those schemas belong to provider, LSP, snapshot, and Effect/Zod bridge slices.

The codec is intentionally hand-written for this first message schema. If the same decode/encode pattern repeats across session events and provider protocol DTOs, that is the right point to derive it with a macro and snapshot the generated glue.

## Haxe Modeling Lesson

OpenCode's stored message parts are JSON objects, but the port should not leak free-form objects through the core. Decode into Haxe enums at the boundary, keep the upstream discriminant strings in encoded output, and treat broad `Dynamic` fields as tracked interop debt rather than the default modeling strategy.
