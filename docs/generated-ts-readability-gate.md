# Generated TS Readability Gate

**Bead:** `opencodehx-046`  
**genes-ts pin reviewed:** `0ffe38943b9ed51225167b19a4c38b06fd5a30b1`  
**TSX temp follow-up resolved at:** `9c129acf60db6bfef0dae2699d32f8b5e146b6fe`
**Reviewed on:** 2026-06-23

This gate defines the minimum review standard for generated TypeScript in high-risk OpenCodeHX modules. Passing `tsc` is necessary, but it is not enough: the generated output is also a product surface that should be readable, narrow at app boundaries, and debuggable by someone comparing it to upstream OpenCode.

## Checklist

Apply this checklist to generated output before expanding a high-risk subsystem:

- `npm run build` passes against the current `reference/genes.pin.json`.
- Generated imports are NodeNext-compatible and preserve useful type/value import separation.
- User modules do not expose raw Haxe map internals such as `StringMap.inst` or `.inst.get(...)`.
- Method closures on stable receivers do not emit IIFE wrappers around `Register.bind(...)`.
- `any`, `unknown`, `Dynamic`, and `Register.unsafeCast(...)` in user modules are either documented boundary debt or reduced into a paired `../genes` Bead.
- Runtime/schema passthrough boundaries are named and isolated; broad values do not leak into closed domain models.
- Temporary locals keep useful names where source or target structure provides them. Large `tmpN` clusters in review-sensitive output require a compiler follow-up unless they are clearly unavoidable evaluation-order scaffolding.
- Public generated declarations do not expose broad `any` in helper declarations. Any remaining helper-level `any` requires a `../genes` follow-up.
- TUI TSX output must be strict-checkable, preserve JSX type imports, avoid weak boundary types, and remain readable enough for snapshot review.

## Snapshot Scan

The review covered the current generated snapshots for config, session, tool, and TUI surfaces:

| Area | Files | Lines | `any` | `unknown` | `Register.unsafeCast` | `tmp` refs | `_g` refs | `StringMap.inst` / `.inst` map leak | Bind IIFE |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `src-gen/opencodehx/config` | 14 | 2703 | 65 | 4 | 22 | 2 | 79 | 0 | 0 |
| `src-gen/opencodehx/session` | 8 | 2436 | 155 | 9 | 17 | 0 | 25 | 0 | 0 |
| `src-gen/opencodehx/tool` | 17 | 2877 | 33 | 1 | 44 | 4 | 80 | 0 | 0 |
| `src-gen/tui/opencodehx/tui` | 8 | 1220 | 0 | 0 | 0 | 52 | 37 | 0 | 0 |

The scan is intentionally mechanical. Counts identify review hotspots, not automatic failures. The important gate outcome is whether each hotspot is either an accepted boundary, an OpenCodeHX modeling issue, or a generic `genes-ts` issue.

## Findings

Config output is strict-checkable and no longer exposes recent provider/server compiler regressions such as map backing details or bind IIFEs. The remaining broad fields in `ConfigInfo.ts` are mostly known config-schema passthrough seams: watcher, MCP, formatter, LSP, layout, enterprise, experimental, and merge-object helpers. Those fields are acceptable for this gate because their owning subsystem slices still define the schema boundary, but future subsystem ports should narrow them instead of spreading `any`.

Session output is strict-checkable. `MessageCodec.ts` still contains many `any` values because it is the current JSON DTO decode/encode boundary for upstream-shaped stored messages and tool payloads. This is acceptable only as boundary debt: closed message and part discriminants should continue moving toward typed Haxe models and `genes.ts.Unknown`-based narrowing as their owners land.

Tool output is strict-checkable. Tool `execute(args: any, ...)` signatures and metadata payloads are boundary-shaped because upstream tool invocations accept runtime JSON payloads. Node filesystem extern gaps still account for some weak host values and casts. The gate accepts this for now because the weak values are isolated to tool input validation and host seams, not stored as domain state.

TUI output is the cleanest typing surface in this review: the reviewed TSX files contain no `any`, no `unknown`, and no `Register.unsafeCast`. The original review found one readability issue in `TuiScaffold.renderView`: a 23-local `tmp`/`tmpN` cluster for JSX children before returning the root `<box>`. That compiler-owned issue is now fixed in `../genes` commit `9c129acf60db6bfef0dae2699d32f8b5e146b6fe`; the refreshed OpenCodeHX TUI snapshot emits tag-based `text` and `input` locals instead.

Public generated declarations still expose inheritance helper-base declarations typed as `any`, such as `declare const SyncEventStore_base: any;`. This is not blocking runtime parity, but it violates the public declaration surface standard and is tracked as compiler work.

## Follow-Ups

- `opencodehx-7rh` / `genes-3v7`: remove or type generated declaration helper-base `any`.
- `opencodehx-25r` / `genes-7tc`: improve generated TSX child temp readability. Closed by `../genes` commit `9c129acf60db6bfef0dae2699d32f8b5e146b6fe` and the refreshed TUI scaffold snapshot.

With those follow-ups filed, `opencodehx-046` establishes the review gate and records the current generated-output state without weakening the Haxe source to hide compiler-owned issues.
