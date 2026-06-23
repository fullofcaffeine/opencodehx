# Cafex Seam Inventory

**Bead:** `opencodehx-041`

This document maps Cafex/Cafetera-style harness responsibilities to OpenCodeHX extension points without adding Caf-specific behavior to the core port.

The concrete source material available in this workspace is Cafetera, not a separate standalone Cafex repo. The relevant evidence is:

- `../cafetera/integrations/opencode/README.md`
- `../cafetera/integrations/opencode/plugin.ts`
- `../cafetera/README.md`
- `../cafetera/docs/Concepts.md`
- `../cafetera/docs/plans/active/graph-contract-and-client-protocol.md`
- `../cafetera/docs/plans/active/execution-model.md`
- `../codex-hxrust/codex-hxrust-port-prd.md` section 20, which names Caf receipt fidelity, goal/effort/wake parity, and Cafex seam conformance as future compatibility gates.

## Boundary

This is an M9 preflight inventory. It does not change OpenCodeHX runtime behavior.

The active rule remains [no-caf-integration-guardrail.md](no-caf-integration-guardrail.md):

- no Caf/Cafex code paths in `src/opencodehx`
- no Caf/Cafex fixtures as required Phase 1 gates
- no Caf-specific `genes-ts` behavior
- no replacement claims until OpenCode parity evidence is stronger

## Current Cafetera Responsibilities

The current Cafetera OpenCode plugin describes these useful responsibilities:

| Responsibility | Cafetera evidence | OpenCodeHX owner today | Gap before M9 adapter work |
| --- | --- | --- | --- |
| Project detection | Plugin detects Cafetera projects by `bin/caf`. | `ProjectRuntime` already discovers project/worktree state and installed package smokes prove `--dir`. | Need an adapter-owned detector interface so Caf projects can be recognized without changing core project semantics. |
| Task continuity | Plugin injects `bd ready --json` during session compaction. Cafetera Brew uses a Beads-compatible `.beads/issues.jsonl` store. | OpenCodeHX already uses Beads operationally; session processor and storage can persist transcript state. | Need a read-only task-context provider that can summarize Beads/Brew state as context without making OpenCodeHX depend on Brew. |
| Context injection | Plugin calls `caf context resume --inject-context` and `caf context inject --tool=... --path=...`. | `SkillRegistry`, config loaders, resource adapters, and plugin metadata surfaces already provide controlled context inputs. | Need a generic plugin/context hook surface after upstream plugin parity, with file-pattern provenance and size limits. |
| Session compaction | Plugin hooks `experimental.session.compacting`. | OpenCodeHX has session retry/compaction fixtures and store-backed export evidence. | Need full upstream session compaction hook parity before Caf-specific restore blocks can be accepted. |
| Guide loading | Cafetera AgentSpec emits guide discovery and loads guides on demand. | `SkillRegistry` supports local/remote skill discovery and permission-filtered availability. | Need a neutral “context provider” model that can feed guides into prompts without requiring Cafetera guide formats. |
| Work trail capture | Plugin marks tool usage logging for crystallization as planned. | `SessionProcessor`, `ToolRegistry`, server events, PTY events, and `SyncEventStore` already expose typed event points. | Need a durable receipt/event export contract with redaction and stable IDs before Caf receipts can be claimed. |

## Broader Cafetera Concepts

Cafetera’s docs describe a typed meta-framework where CML/CIR, graph contracts, AgentSpec output, Brew tasks, and contract/golden/e2e tests form a deterministic layer driven by external agents. Those concepts map cleanly to OpenCodeHX only as adapter-facing consumers:

| Cafetera/Cafex concept | OpenCodeHX capability to reuse | Missing seam |
| --- | --- | --- |
| CML/CIR validation | OpenCodeHX can run CLI commands, read files, and surface diagnostics. | A generic external-command tool/adapter contract for `caf compile`, `caf validate`, and structured diagnostics. |
| Graph Contract export/watch/query | Server SSE, `SyncEventStore`, session export, and resource manifests provide first event/export patterns. | Graph snapshot/watch protocol adapter, including deterministic IDs, provenance, delete events, and query paging. |
| AgentSpec multi-platform guide emission | `SkillRegistry`, checked artifacts, and TUI route/keybind macros show source-authored artifact discipline. | Agent guide import must stay data-driven and bounded; OpenCodeHX should not emit or own AgentSpec. |
| Brew task loop | Beads workflow is already the project source of truth. | Optional Brew/Beads bridge that reads tasks and writes comments/close events only under explicit user permission. |
| Deterministic/golden/contract testing | OpenCodeHX has smoke, transcript, package, benchmark, macro-diagnostics, and generated TS gates. | Caf adapter conformance fixtures should be optional M9 gates, not part of M1-M8 CI. |
| Crystallization/pattern promotion | OpenCodeHX has transcripts, tool outcomes, and plugin hooks as future surfaces. | Receipt format, redaction, consent, and promotion API are missing. |
| Capability abstraction for agents | Provider/model capabilities and tool permissions are typed in Haxe. | A neutral capability advertisement format for host capabilities, tools, context providers, and adapters. |

## Codex/Cafex Compatibility Signals

The `codex-hxrust` precedent calls out several compatibility gates that also matter here:

| Signal | OpenCodeHX status | Required before claiming compatibility |
| --- | --- | --- |
| Receipt fidelity | Partial event evidence exists through session, tool, server, and PTY-style events, but no Caf receipt schema exists here. | Define a neutral receipt envelope with event ID, time, source, tool/session IDs, redaction state, and replay order. |
| Goal parity | OpenCodeHX sessions have titles, prompts, messages, and server routes; no thread-goal API is ported. | Decide whether goals belong to upstream OpenCode parity, a plugin adapter, or a future external protocol bridge. |
| Effort parity | Provider options and model metadata exist; no user-facing reasoning-effort override is modeled as a stable OpenCodeHX contract. | Add only if upstream OpenCode or provider parity requires it; otherwise keep it adapter metadata. |
| Wake parity | No background wake/daemon scheduler is part of current OpenCodeHX. | Treat as future host/runtime work outside core unless upstream OpenCode gains equivalent behavior. |
| Sandbox/process safety | Tool permission, shell selection, external directory denial, PTY lifecycle, and package smokes exist. | Adapter must honor OpenCodeHX permission decisions and must not bypass tool policy through raw `caf` shell calls. |

## Candidate Adapter Shape

Future Caf/Cafex work should live outside the core, for example under an adapter package or project-local plugin. The app-facing shape should be generic enough for non-Caf users:

```text
ContextProvider
  detect(project): DetectionResult
  summarize(session): ContextBlock[]
  afterTool(toolEvent): ContextBlock[]

ReceiptSink
  record(event): void
  flush(): ReceiptBatch

ExternalTaskProvider
  ready(): TaskSummary[]
  update(event): TaskUpdateResult

GraphBridge
  exportSnapshot(): GraphSnapshot
  watch(): GraphDeltaStream
  query(request): GraphQueryResult
```

OpenCodeHX already has plausible owners for these interfaces:

- plugin/context hook surface: `plugin-runtime-minimum.md`
- session and transcript state: `session-processor-one-turn.md`
- server events and sync replay: `server-hono-seam.md` and `project-runtime-parity.md`
- task workflow: Beads plus `.beads/issues.jsonl`
- packaging and installed runtime: `npm-global-packaging.md`

## Missing Seams

Before M9 adapter implementation, these seams need explicit Beads or decision records:

| Missing seam | Why it matters | Suggested owner |
| --- | --- | --- |
| Generic plugin hook parity | Cafetera’s current OpenCode plugin depends on compaction and tool hooks. | Upstream plugin parity slice. |
| Bounded context provider API | Prevents guide/context injection from becoming unreviewable prompt stuffing. | Session/plugin slice. |
| Receipt/event export contract | Required for Caf receipt fidelity and crystallization. | Session/server/sync slice. |
| External task provider bridge | Keeps Brew/Beads integration optional and permissioned. | Adapter/preflight slice. |
| Graph snapshot/watch/query adapter | Needed for Cafetera Graph Contract clients. | M9 adapter/preflight slice. |
| Redaction and secret policy for adapter output | Cafetera context can include project/task metadata and command output. | Security/public-readiness slice. |
| Adapter packaging convention | Keeps Caf-specific code out of OpenCodeHX core and npm package claims honest. | Packaging/plugin slice. |

## Decision

OpenCodeHX should not integrate Caf/Cafex in Phase 1. The useful result of this inventory is narrower:

1. Preserve upstream OpenCode plugin, session, tool, server, and TUI behavior first.
2. Keep existing host seams generic enough that a Caf adapter can consume them later.
3. Treat Caf receipt, goal, effort, wake, graph, and Brew compatibility as M9 adapter/preflight gates.
4. Do not add Caf-specific generated TypeScript, compiler behavior, fixtures, or runtime branches to the core port.
