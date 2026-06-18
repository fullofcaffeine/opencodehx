# M3 Replacement Decision Checkpoint

**Bead:** `opencodehx-044`  
**Date:** 2026-06-18  
**Decision:** Continue the OpenCodeHX port. Do not claim replacement readiness yet. Keep the next phase Node-first and parity-driven, with server/API and persisted session behavior before real provider breadth or TUI depth.

## Decision

OpenCodeHX has passed the M3 headless fake-provider checkpoint. The project should continue rather than pivot or narrow to a compiler-only experiment.

This is still not enough evidence to recommend replacing upstream OpenCode or Cafex. The useful conclusion is narrower: Haxe-authored OpenCode slices can compile through `genes-ts` into strict NodeNext TypeScript, run under Node, preserve a credential-free transcript oracle, execute core tools through a permission-aware one-turn session processor, and expose real `genes-ts` issues as actionable compiler work.

## Evidence

| Area | Evidence |
| --- | --- |
| Upstream oracle | `reference/upstream-opencode.pin.json` pins `../opencode` at `69b7f3b8db82c3ab9dacd72d715a57d375de18e4`, OpenCode `1.14.20`, with 523 source files and 187 test files inventoried. |
| Compiler target | `reference/genes.pin.json` records `../genes` as the canonical `genes-ts` checkout. Current checkpoint gates used `b2038692df2e5e98df37caa51b8cb8ce9a1bd5e6`. |
| Build/runtime | `npm run build` compiles Haxe through `genes-ts`, copies resources, and strict-checks generated TypeScript with `tsc`. |
| NodeNext smoke | `npm run smoke` runs generated ESM under Node and covers utilities, config, files, message DTOs, permissions, storage, tools, provider, and session processor smoke. |
| Transcript parity | `npm run transcript:parity` compares the upstream-shaped fake provider oracle, the Haxe transcript fixture, and `opencodehx run --format json` against `fixtures/transcripts/one-turn.golden.json`. |
| CLI smoke | `npm run cli:smoke` covers help/version/run surfaces for the headless scaffold. |
| Public-readiness hygiene | `npm run public:precommit` runs Haxe formatting checks and gitleaks. |

## Completed Slices Behind M3

- M0/M1 foundation: Beads setup, source/test parity matrices, OpenCode and `genes-ts` pins, NodeNext `genes-ts` scaffold, repo hygiene, and compiler limitation ledger.
- M2 platform slices: Node extern policy, host seam map, Effect facade strategy, import-attribute/dynamic import/resource smoke, TS/TSX audit, utilities, config parser/loader, and Message V2 DTOs.
- Tool/session foundation: SQLite session store, file/search primitives, tool registry, read/write/edit/apply_patch, bash seam, permission runtime, fake provider transcript harness, headless `run`, and one-turn session processor.

The current executable surface is small but real: a Node-first generated TypeScript app can produce a stable fake-provider transcript, persist session messages/parts, execute a permission-approved file tool, and keep generated output strict-checkable.

## genes-ts Status

The port has already improved `genes-ts`:

- Import attributes and JSON resource imports landed for OpenCodeHX resource smoke.
- Dynamic import callback typing was tightened from user-visible `any`.
- `haxe.extern.Rest<T>` alias emission was fixed so Reflect/config code strict-checks.

Known open compiler debts are tracked in `docs/genes-ts-limitation-ledger.md` and Beads. They are not replacement blockers yet, but they are a warning that broad porting will keep exposing codegen hygiene issues:

- enum switch temporary name hygiene,
- `Map.get` nullability under strict TypeScript,
- CJS constructor extern typing,
- array helper temporary collisions,
- optional array narrowing,
- secondary extern return imports,
- local `map` temporary collision with a surrounding `result` binding.

Current assessment: `genes-ts` is viable as the primary target, but generated TS quality needs a dedicated review gate before high-churn server/provider/TUI work scales up.

## Generated TS Quality

The generated TypeScript passes strict `tsc` for all current slices. Readability is acceptable for DTOs, tools, storage, and session smoke debugging, but the port has had to avoid or reshape some otherwise idiomatic Haxe source to work around temporary naming and nullability codegen issues.

Policy implication: continue to treat source contortions as compiler follow-up work. Use explicit loops or narrow host-boundary `Dynamic` only to unblock a slice, then record the compiler debt in Beads or the ledger.

## Replacement Readiness

OpenCodeHX is not replacement-ready.

Missing major surfaces include:

- server routes, events, SSE/WebSocket, and SDK compatibility,
- real provider registry, auth/env resolution, and AI SDK streaming,
- session resume, compaction, retry, overflow, abort, and recovery behavior,
- MCP/ACP, plugin, LSP, and web/tool surfaces,
- TUI TSX/OpenTUI rendering, dialogs, routes, key input, and terminal replay evidence,
- packaging and upstream drift procedure,
- broad upstream test mapping and error UX parity.

The correct stance is continue-with-gates: preserve the Haxe/`genes-ts` direction, but require empirical parity evidence before any replacement recommendation.

## Recommended Next Milestone

Proceed to M5 Node-first server/API parity over the fake-provider/session core.

Recommended order:

1. `opencodehx-039` - finish the OpenCode test port matrix so server/provider/TUI work has explicit oracle mapping.
2. `opencodehx-026` - port a minimal Hono-compatible Node server surface with selected route/event fixtures.
3. `opencodehx-027` - run an SDK/client smoke against that server.
4. `opencodehx-048` - add session list/resume/export-style persistence flows needed by server clients.
5. `opencodehx-046` - apply generated TS readability review to config/session/tool/server before expanding provider and TUI scope.

Provider M6 and TUI M7 should remain active but not outrun the server/session evidence. Real provider streaming should come after the fake-provider server event path is stable, and TSX/OpenTUI work should start with small compiler fixtures before broad screen ports.

## Decision Review Trigger

Revisit the replacement decision after M5 if all of the following are true:

- server starts/stops under Node,
- selected routes return upstream-compatible payloads,
- fake-provider session events stream to a client,
- persisted session list/resume works,
- generated TS remains strict-checkable and reviewable,
- open `genes-ts` issues are either fixed, accepted as isolated boundary debt, or non-blocking with documented source patterns.
