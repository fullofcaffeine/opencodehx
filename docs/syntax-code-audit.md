# Syntax.code Audit

**Bead:** `opencodehx-1le`

OpenCodeHX treats `js.Syntax.code` like `untyped`: use it only when Haxe externs, typed facades, standard library APIs, or a generic `genes-ts` improvement cannot express the runtime operation yet. The `opencodehx-1le` cleanup retired the large and repeated raw blocks from app code into typed seams.

Current scan command:

```bash
rg -n "Syntax\.code|js\.Syntax" src test hxml scripts docs AGENTS.md README.md
```

## Remaining Source Sites

| File | Classification | Reason |
| --- | --- | --- |
| `src/opencodehx/interop/JsIdentityKey.hx` | Justified JS identity boundary | Models an opaque host object reference that may only be selected and compared by upstream JavaScript reference identity. Haxe has no portable type for arbitrary JS object identity plus `===`, so product code receives a semantic `JsIdentityKey` instead of raw object access. |
| `src/opencodehx/externs/js/EsmModule.hx` | Justified ESM metadata boundary | Haxe/genes-ts does not expose a structured `import.meta` expression. The raw expression is a tiny string-valued facade used by typed URL/resource code. |
| `src/opencodehx/externs/web/WebStreams.hx` | Justified Web runtime predicate boundary | Localizes `typeof value === "string"` and `value instanceof ArrayBuffer` checks used to narrow WebSocket/stream payloads from `Unknown` into typed Web facades. Callers must prove the predicate before retrieving the narrowed value. |
| `src/opencodehx/smoke/SmokeFetchStub.hx` | Smoke-only monkey-patch boundary | Adapts a typed smoke fixture callback to the host `typeof fetch` declaration. The cast is restricted to replacing/restoring `globalThis.fetch` in credential-free remote-config smoke tests. |

## Retired Patterns

- Console, process, environment, cwd/chdir, shell execution, and platform reads now go through host/node externs and facades.
- Data URL percent decoding, clocks, timers, Buffer operations, response streams, event streams, web binary payloads, and URI decoding now use named host or Web facades.
- Unknown JSON/object probing is centralized in transitional decoder helpers instead of repeated raw field access in product modules.
- Hono server lifecycle, SSE response construction, PTY WebSocket smoke orchestration, and server smoke stream reading now use typed extern/facade code.
- Tree-sitter, better-sqlite3, AI SDK abort/fetch/error, and resource URL access were narrowed into local externs or tiny boundary facades.

## Follow-up Policy

Do not add new app-level `Syntax.code` for ordinary host APIs. Add a narrow extern or facade first. If a raw snippet is still necessary, keep it tiny, document the runtime contract next to the call, and create a Bead when the pattern repeats or belongs in `genes-ts`.
