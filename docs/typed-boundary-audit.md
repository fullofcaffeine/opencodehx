# Typed Boundary Audit

OpenCodeHX should be as typed as practical at every product boundary. Broad `Dynamic`, `DynamicAccess`, `cast`, `untyped`, raw `Syntax.code`, `@:ts.type`, generated `any`, and string-keyed reflection are boundary debt unless they are isolated, documented, and tracked.

## Current Guard

Run:

```bash
npm run typed-boundary:scan
```

The scan compares `src/opencodehx/**/*.hx` against `reference/typed-boundary-baseline.json`. The current ratcheted baseline is 1345 source markers. Reductions pass automatically. New weak-type markers, new weakly typed files, or per-file increases fail until the code is narrowed or the baseline is deliberately updated with evidence:

```bash
npm run typed-boundary:update
```

Update the baseline only when the remaining weak marker is an intentional boundary with a nearby comment, focused doc note, or Bead.

## Improved In This Slice

- Built-in tool execution no longer exposes `execute(args:Dynamic, ctx)`.
- `ToolRegistry.execute` now accepts `ToolCallInput`, an explicit unknown JSON/tool-call boundary.
- Built-in tools decode once through `ToolValidation` and then run on typed records.
- `ToolResult.metadata`, `ToolPermissionRequest.metadata`, and permission ask records now use typed metadata wrappers instead of `Dynamic`.
- Session tool calls and `ToolState` records use `ToolCallInput` plus `ToolStateMetadata` instead of raw `Dynamic` for stored tool input and tool-state metadata.
- Open message DTO fields for symbol ranges, JSON schema output format, user summary diffs/tools, assistant error/structured data, part metadata, and retry errors use `MessageJson` backed by generic `genes.ts.JsonValue` checked construction instead of raw `Dynamic`, broad `Unknown`, or a product-local JSON alias.
- Tool and LSP smoke metadata checks no longer use `Reflect.field` or a local `cast Reflect.field` helper for stable JSON metadata assertions.
- `PluginMeta` reloads persisted plugin metadata through `genes.ts.UnknownRecord` and `UnknownNarrow` instead of `Dynamic` plus reflection.
- `PluginShared` reads package.json metadata through `genes.ts.UnknownRecord`, with typed string/array narrowing for package name, entrypoint, version, and `oc-themes`.
- LSP diagnostics now use `LspDiagnostics`, a typed URI-keyed registry, instead of `DynamicAccess<Array<LspDiagnosticInfo>>`.
- `AuthStore` and `AccountStore` decode auth JSON and active-account SQLite rows through `genes.ts.UnknownRecord`/`UnknownNarrow` instead of local reflection/cast helpers.
- `FormatRuntime` narrows formatter object config through `genes.ts.UnknownRecord`/`UnknownArray`/`UnknownNarrow` instead of local reflection/cast helpers.
- `PtyRouteProtocol` decodes PTY create/update request bodies through `genes.ts.UnknownRecord`/`UnknownArray`/`UnknownNarrow`, preserving typed PTY DTOs and copying only validated env strings into the Node PTY env map.
- `ServerSessionProtocol` decodes session create/select/update route bodies through `genes.ts.UnknownRecord`/`UnknownNarrow`, keeping runtime JS narrowing out of macro-owned `ServerProtocol`.
- `CliSmoke` parses run/export transcript JSON and diagnostic golden JSON through `genes.ts.UnknownRecord`/`UnknownArray` helpers instead of threading `Dynamic` and `Reflect.field` through stable provider/request/message/event/diagnostic assertions.
- `ProviderSmoke` parses fake-provider transcript JSON through `genes.ts.UnknownRecord`/`UnknownArray` helpers and decodes the assistant message through `JsonCodec` plus `MessageCodec.parseWithParts`, avoiding smoke-local `Dynamic`, `Reflect.field`, and casts for stable transcript assertions.
- `ProviderSmoke` reads env/config and Bedrock provider option assertions through `ProviderOptionAccess` instead of raw reflection over the open provider SDK passthrough map.
- `ProviderSmoke` reads Cloudflare metadata and GitLab instance/header/feature-flag option assertions through `ProviderOptionAccess` maps instead of raw reflection over provider passthrough options.
- `ProviderSmoke` reads custom provider/model, variant, and Vertex proxy option assertions through `ProviderOptionAccess` plus `UnknownRecord` field checks; only the local fixture `config(...)` builder still uses reflection there.
- `ProviderSmoke` narrows local config fixture scalars and provider lists through `UnknownRecord`/`UnknownArray` helpers; provider-map passthrough stays in one documented fixture boundary.
- `SessionProcessorSmoke` reads request-option nested records, optional stream tool-choice, and workflow tool metadata through `ProviderOptionAccess`, typed optional fields, and `UnknownRecord` helpers instead of smoke-local reflection.
- `ConfigSmoke` reads plugin tuple/resolved option assertions through `ConfigPlugin.stringOption(...)`, keeping plugin passthrough narrowing in the config plugin boundary instead of raw smoke reflection.
- `ConfigSmoke` reads LSP server presence, disabled flags, and extensions through `ConfigLsp` Unknown-based accessors instead of raw reflection over the still-open `ConfigInfo.lsp` boundary.
- `ConfigSmoke` builds local-update permission patches with the typed `PermissionConfigValue` map and asserts through map reads instead of object-literal casts or reflection.
- `ConfigSmoke` narrows the remote MCP override assertion through `UnknownRecord`/`UnknownNarrow` instead of casting a smoke-local typedef from `Reflect.field`.
- `ServerSmoke` reads listener/app health and the first PTY create/list/get/update/missing route assertions through `UnknownRecord`/`UnknownArray` helpers and typed `Response.status` instead of raw reflection and casts.
- `ServerSmoke` reads sync replay/history route responses through `UnknownRecord`/`UnknownArray` helpers and typed `Response.status` instead of raw `Dynamic`, reflection, and casts.
- `ServerSmoke` reads basic session create/list/message/status responses through `UnknownRecord`/`UnknownArray` helpers and typed `Response.status`; legacy high-volume message helper narrowing remains a separate slice.
- `ServerSmoke` reads workspace proxy statuses through typed `Response.status` and narrows WebSocket PTY create JSON through `UnknownRecord` instead of smoke-local reflection.
- `ServerSmoke` reads legacy high-volume message page IDs through `UnknownArray`/`UnknownRecord` helpers instead of a `Dynamic` helper with nested reflection.
- `ServerSmoke` reads session pagination/search/global-list response records through `UnknownRecord`/`UnknownArray` helpers instead of raw `Dynamic`, casts, and reflection.
- `ServerSmoke` reads archive session create/patch/default/included response records through `UnknownRecord`/`UnknownArray` helpers instead of raw `Dynamic`, casts, and reflection.
- `ServerSmoke` reads alternate-directory session creation plus directory/root filter lists through `UnknownRecord`/`UnknownArray` helpers instead of raw `Dynamic`, casts, and reflection.
- `ServerSmoke` reads live-event and multi-project session assertions through `UnknownRecord`/`UnknownArray` helpers and a typed record lookup, retiring the old smoke-local `Dynamic` response ID helpers.
- `ServerSmoke` reads project git init/current/already-git route responses through `UnknownRecord` helpers instead of smoke-local reflection.
- `ServerSmoke` decodes PTY WebSocket cursor control frames through `UnknownRecord` helpers instead of smoke-local `Dynamic` plus `Reflect.field`.
- `PtySmoke` decodes fake-socket PTY cursor control frames through `UnknownRecord` helpers instead of smoke-local `Dynamic` plus `Reflect.field`.
- `MessageSmoke` verifies encoded tool-state roundtrips through the typed message codec instead of reflecting into encoded JSON.
- `UtilSmoke` reads process failure objects and diagnostics golden JSON through `UnknownRecord` helpers instead of assertion-local `Dynamic` and reflection.
- `EffectSmoke` builds fixture environment maps from typed key/value entries instead of a `Dynamic` object plus `Reflect.fields`.
- `ConfigWriter` recurses through writable JSON/JSONC config trees with `UnknownRecord.keys/get` instead of `Reflect.fields`, `Reflect.field`, and casts.
- `ConfigInfo.mergeObject` merges open config maps through `UnknownRecord.keys/get` instead of recursive `Reflect.fields`/`Reflect.field`/`Reflect.setField`.
- `PermissionRules.fromConfig` iterates typed permission map keys instead of reflecting over the config object.
- `SyncSqliteEventPersistence` decodes SQLite row objects through `UnknownRecord`/`UnknownNarrow` instead of local `Dynamic` row helpers and `Reflect.field`.
- `ProjectRuntimeSmoke` centralizes repeated fixture cleanup catches behind one documented helper instead of carrying many local `Dynamic` catch boundaries through project, worktree, watcher, and clone smoke cases.
- `McpRuntime.transportOptions` assembles SDK transport options through typed record branches instead of `Dynamic`, `Reflect.setField`, and a final cast.
- `McpAcpSmoke` asserts typed MCP transport option presence through optional fields instead of `Reflect.hasField`.
- `ModuleResolver` and `ProcessRuntime` read package/error boundary strings through `UnknownRecord` helpers instead of utility-local reflection.
- Copilot chat SSE and Responses decoders read private JSON object fields through `UnknownRecord` helpers instead of reflection while preserving typed decoder outputs.
- `CopilotChatSseDecoder` now parses untrusted SSE JSON into `UnknownRecord`, decodes arrays through `UnknownArray`, and avoids local dynamic array casts while preserving typed stream chunk outputs.
- `CopilotResponsesResponseDecoder` now threads parsed `/responses` HTTP bodies through `UnknownRecord`/`UnknownArray` narrowing and validates open JSON passthrough fields with `JsonCodec.narrow` before crossing into the AI SDK JSONValue bridge.
- `CopilotResponsesStream` maps OpenAI Responses SSE chunks through `UnknownRecord`/`UnknownNarrow` field helpers instead of local `Dynamic` JSON access and `Reflect.field`.
- `FileSmoke` asserts `AppFileSystem.readJson` payloads through `UnknownRecord` helpers instead of smoke-local `Dynamic` plus `Reflect.field`.
- `FileSmoke` centralizes repeated temp-directory, chmod, and environment cleanup catches behind one documented smoke helper.
- `SmokeCleanup` provides module-level sync cleanup helpers so `FileSmoke`, `PluginSmoke`, `StorageSmoke`, `LspSmoke`, `PatchSmoke`, and `ProjectRuntimeSmoke` share one documented broad exception boundary instead of repeating fixture-local cleanup catches.
- `SmokeCleanup` now also owns async smoke cleanup, so `FileSmoke.runAsync`, `FormatterSmoke`, `SkillSmoke.runRemote`, and `ToolSmoke` share one documented async exception boundary instead of repeated temp-directory cleanup catches.
- `Reflect.compare` has been removed from OpenCodeHX source in favor of typed comparators, and the boundary scan now guards it with a zero-count budget.
- Provider JSON Schema intent checks now use modeled `const`, `$ref`, and `additionalProperties` fields instead of `Reflect.hasField`; the `const` value remains an opaque documented JSON-literal boundary until inspected.
- `OpenCodeCompatClient.messages` constructs typed message-page records directly instead of mutating a dynamic result with reflection for optional pagination headers.
- `AppFileSystem` reads Node filesystem error codes through `UnknownRecord` narrowing, types readable-stream chunks as Node string-or-buffer data, accepts checked `JsonValue` for JSON writes, and returns `Unknown` for JSON reads instead of broad `Dynamic`.
- `Npm` centralizes Node filesystem, injected reify, and JSON.parse fallback handling behind one documented host-failure helper instead of repeated `Dynamic` catch blocks.
- `PatchRuntime` centralizes read/delete/write filesystem failures behind typed patch helpers and narrows parser-only catches to `haxe.Exception` while preserving verification result behavior.

## Remaining Hotspots

- Message/session codecs still own broad JSON DTO debt in `MessageTypes`, `MessageCodec`, `SessionProcessor`, and export paths.
- Provider/config/plugin loaders still use open maps and reflection where upstream data is schema-owned or provider-SDK passthrough.
- Storage and server adapters still contain row/HTTP JSON boundary `Dynamic` that should move behind typed decoders.
- Externs and `genes.ts` helpers intentionally contain raw target interop; replace only when a narrower extern or generic compiler improvement exists.
- Smokes still use reflection for parsed JSON assertions; migrate repeated patterns to typed smoke JSON helpers.

## Ratchet Rules

- Prefer `genes.ts.Unknown`, `UnknownNarrow`, `UnknownRecord`, typed records, enums, abstracts, and narrow externs.
- Keep raw JSON, provider SDK passthrough, plugin/custom tools, HTTP payloads, and SQLite rows at named boundary adapters.
- Do not copy upstream `any` or `unknown` into Haxe source without checking whether OpenCodeHX can recover a stronger type.
- If good Haxe emits weak or noisy TypeScript, reduce the case and fix `genes-ts` generically instead of weakening OpenCodeHX source.
