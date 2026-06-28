# Typed Boundary Audit

OpenCodeHX should be as typed as practical at every product boundary. Broad `Dynamic`, `DynamicAccess`, `cast`, `untyped`, raw `Syntax.code`, `@:ts.type`, generated `any`, and string-keyed reflection are boundary debt unless they are isolated, documented, and tracked.

## Current Guard

Run:

```bash
npm run typed-boundary:scan
```

The scan compares `src/opencodehx/**/*.hx` against `reference/typed-boundary-baseline.json`. Reductions pass automatically. New weak-type markers, new weakly typed files, or per-file increases fail until the code is narrowed or the baseline is deliberately updated with evidence:

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
