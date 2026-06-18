# PRD: OpenCodeHX — Haxe port of OpenCode via genes-ts

**Status:** Draft plan / experiment with replacement intent  
**Date:** 2026-06-17  
**Primary tracker:** Beads (`bd`)  
**Primary compiler path:** Haxe → TypeScript via `genes-ts` → `tsc`/Node runtime  
**Near-term runtime target:** Node-first ESM TypeScript, while preserving OpenCode's Bun seams for later packaging  
**Future runtime targets:** Rust/Go through Haxe backends only after TS parity is proven

---

## 1. Executive summary

OpenCodeHX is a staged port of upstream OpenCode to Haxe, compiled to idiomatic TypeScript through `genes-ts`. The immediate product is not a Cafex integration and not a generic cross-target agent runtime. The immediate product is: **OpenCode, functionally and UX-identical, but authored in Haxe and emitted as maintainable TypeScript.**

The experiment has two deliberate outputs:

1. **`opencodehx`**: a full Haxe port of `packages/opencode` with CLI, headless run mode, server, tools, sessions, provider streaming, config, storage, and TUI behavior matching OpenCode.
2. **`genes-ts` hardening**: fixes and features discovered while compiling a real, large TypeScript application with TSX, async streams, Node/Bun interop, dynamic imports, and strict TypeScript output.

The recommended path is **genes-ts first**, with regular Genes and the standard Haxe JavaScript target retained as diagnostic or fallback profiles only. This best matches the stated goal: prove Haxe-authored code can emit readable, idiomatic TypeScript and remain close enough to the OpenCode ecosystem to verify behavior against upstream.

---

## 2. Source snapshot findings

### 2.1 OpenCode upstream snapshot

The attached OpenCode bundle contains an OpenCode monorepo with `packages/opencode` as the main package.

Observed package characteristics:

- `packages/opencode/package.json` reports OpenCode version `1.14.20`.
- Package manager is Bun-oriented at the repo level.
- Runtime/package code uses TypeScript ESM, TSX, conditional Bun/Node adapters, and extensive npm dependencies.
- Main binary entry is `packages/opencode/bin/opencode`.
- Important conditional imports:
  - `#db`: `src/storage/db.bun.ts` or `src/storage/db.node.ts`
  - `#pty`: `src/pty/pty.bun.ts` or `src/pty/pty.node.ts`
  - `#hono`: `src/server/adapter.bun.ts` or `src/server/adapter.node.ts`
- Build script builds web/TUI assets and produces multi-platform single binaries through Bun.

Approximate source inventory under `packages/opencode/src`:

| Area | Files | Approx LOC | Port difficulty | Notes |
|---|---:|---:|---|---|
| CLI + TUI | 181 | 34k | Very high | TSX/Solid/OpenTUI, terminal UX, keyboard, dialogs, worker split |
| Session | 33 | 8.2k | Very high | message model, processor, compaction, LLM streaming, tool lifecycle |
| Provider | 33 | 8.0k | High | dynamic provider imports, AI SDK, auth/env/model config |
| Server | 38 | 5.9k | Medium/high | Hono routes, SSE, WebSocket, SDK compatibility |
| Tool system | 42 | 4.5k | High | shell, grep, glob, edit/apply_patch, LSP, web tools, permission gates |
| LSP | 7 | 2.9k | High | process + JSON-RPC lifecycle |
| Plugin | 9 | 2.7k | Medium/high | plugin discovery/load/install/invocation |
| ACP/MCP | 8 | 3.7k | Medium/high | protocol surfaces and agent/client interop |
| Config | 23 | 2.1k | Medium | JSONC, zod/effect schema, path/env resolution |
| Storage | 8 | 1.0k | Medium | SQLite/drizzle seam; already has Bun/Node adapters |
| Utilities | 36 | 1.9k | Low/medium | good early port candidate |

OpenCode test inventory is large enough to be used as the main oracle: `packages/opencode/test` contains broad tests for config, tools, files, session behavior, plugins, server behavior, providers, MCP, storage, and CLI behavior.

### 2.2 genes-ts version verification

There are two genes-ts copies in the uploaded material:

1. Standalone bundle: `repomix-output-genes-ts.xml`
2. Cafetera vendored copy: `tools/cafetera/vendor/genes-ts` inside `repomix-output-fullofcaffeine-cafetera.xml`

Result:

- Both report version **`1.11.0`** in `package.json` / `haxelib.json`.
- The common compiler source files are byte-for-byte identical across the standalone and Cafetera vendored copy.
- The Cafetera copy adds module metadata, examples, generated output, and integration packaging around the same compiler core.
- Latest visible changelog entry in the uploaded sources is `1.11.0` dated 2026-02-05.

Recommendation:

- Use the **standalone genes-ts repo as the canonical development dependency** for this experiment because it is smaller and cleaner for compiler work.
- Keep Cafetera's vendored copy as the **integration reference** for later Caf module packaging.
- Do not treat Cafetera's copy as a newer compiler unless a future diff shows source divergence.

### 2.3 Cafex / Cafetera snapshot

Cafex is present under Cafetera's Codex module and `deps/codex`. The relevant docs frame Cafex as a **Codex-specific Caf-native harness**, not the semantic authority for Caf itself. The semantic authority remains CML/Haxe/contracts/fixtures/Brew/receipts.

Implication for OpenCodeHX:

- Phase 1 must **not** integrate Cafex.
- OpenCodeHX should not inherit Cafex Rust internals.
- Later, if OpenCodeHX becomes a Cafex replacement candidate, it should consume Caf contracts rather than clone Codex/Cafex internals.

### 2.4 hxcodex reference snapshot

The hxcodex WIP is valuable as a planning pattern:

- Upstream-first compatibility experiment.
- Gate-driven plan.
- Caf adapter later.
- Small boundary slices.
- Fixtures and generated-runtime validation.
- Clear kill/pivot criteria.

OpenCodeHX should follow the same shape but with a stronger 1:1 product goal because OpenCode's TUI/CLI UX is itself the target.

### 2.5 haxe.rust / haxe.go snapshots

These are reference-only for now. They support a later portability audit, but they should not dictate the initial OpenCodeHX architecture. The useful lesson is to classify boundaries early, not abstract them early.

---

## 3. Problem statement

The current Cafex path is tied to a Codex fork and a Rust-native harness. OpenCode is a separate and active agent product with a richer terminal UX and a TypeScript/Node/Bun ecosystem. A Haxe-authored OpenCode port could become a better long-term agent substrate for Caf, but only if it first proves that:

1. A large, real TypeScript codebase can be ported to Haxe without UX or behavior drift.
2. `genes-ts` can emit TypeScript that remains readable, strict-type-checkable, and workable inside a modern Node/Bun package.
3. The Haxe source can stay close enough to upstream OpenCode for ongoing parity work.
4. The resulting architecture can later expose Caf integration seams without contaminating the initial port.

---

## 4. Goals

### 4.1 Product goals

- Produce a Haxe-authored `opencodehx` implementation that can replace `packages/opencode` behavior in a local checkout.
- Preserve upstream OpenCode CLI surface, command semantics, config behavior, session behavior, provider behavior, tool behavior, server/API behavior, and TUI UX.
- Keep generated TypeScript idiomatic enough for humans to inspect and for TypeScript tooling to validate.
- Use upstream OpenCode tests and golden fixtures as the parity oracle.
- Make every `genes-ts` limitation discovered during the port actionable as a small compiler bug/feature bead with a minimal reproduction.

### 4.2 Compiler/toolchain goals

- Validate `genes-ts` on a large Node/Bun/TSX codebase.
- Improve NodeNext ESM output, import specifier handling, externs, dynamic imports, TSX/HXX, async/await, stream/event typing, and strict TypeScript generation as needed.
- Establish a repeatable `haxe -> src-gen/*.ts -> tsc -> runtime tests` pipeline.
- Keep regular Genes and standard Haxe JS builds as optional comparison profiles.

### 4.3 Future goals, explicitly deferred

- Evaluate OpenCodeHX as a Cafex replacement candidate.
- Add Caf integration agentic layer.
- Port selected runtime slices through haxe.rust or haxe.go.
- Replace external npm dependencies with portable Haxe implementations where it is worth it.

---

## 5. Non-goals

- No Cafex integration in Phase 1.
- No claim that OpenCodeHX replaces Cafex until parity and Caf contract checks are passed.
- No immediate Rust/Go target.
- No broad portability abstraction layer before the TS target works.
- No rewrite of all npm dependencies into Haxe.
- No semantic redesign of OpenCode sessions, tools, or TUI.
- No acceptance of “it compiles” as success if user-visible behavior drifts.
- No file-by-file blind transliteration without tests.

---

## 6. Product principles

1. **OpenCode parity first.** Behavior and UX win over elegance.
2. **Haxe source is the product source.** Generated TypeScript is an artifact, but it must be readable and reviewable.
3. **Node-first, not portable-first.** Use Node/Bun realities where OpenCode requires them.
4. **Classify seams now; abstract later.** Mark host/runtime seams, but do not add indirection everywhere.
5. **Compiler work is first-class product work.** `genes-ts` improvements are expected, not incidental.
6. **Caf later, contracts first.** Future Caf integration should consume Caf contracts, not Cafex Rust implementation details.
7. **Parity is empirical.** Every meaningful subsystem needs tests, golden transcripts, or smoke evidence.

---

## 7. Recommendation: genes-ts vs regular Genes vs Haxe JS

| Option | What it gives | Strengths | Weaknesses | Recommendation |
|---|---|---|---|---|
| `genes-ts` | Haxe → split ESM TypeScript | Best fit for the experiment; readable TS artifact; strict `tsc` gate; closer to upstream OpenCode/npm ecosystem; exercises TSX/NodeNext/compiler capabilities | Less mature than standard Haxe JS; likely needs compiler fixes; interop edge cases will surface | **Use as primary target** |
| Regular Genes | Haxe → split ES modules + `.d.ts` | More established ESM JS generator; useful if TS emission is temporarily blocked; good diagnostic comparison | Does not emit TS source as the primary artifact; less aligned with testing genes-ts; less useful for TS-level migration review | Keep as fallback/diagnostic profile |
| Standard Haxe JS target | Haxe → JavaScript | Most mature; Tier-1 Haxe target; useful for sanity checks and Haxe semantic comparisons | Not TS output; less idiomatic for OpenCode's TS-first environment; ES5 default with ES6 option; not the experiment | Keep as emergency fallback only |

Decision: **Use genes-ts.** The whole point is to validate and improve Haxe→TypeScript for a real application. Falling back to regular Genes or Haxe JS too early would make the experiment easier but less meaningful.

---

## 8. Runtime stance

### 8.1 Start with Node-first TypeScript

The first `opencodehx` runtime should be Node-first ESM TypeScript because:

- OpenCode already has Node adapters for server, storage, and PTY paths.
- NodeNext ESM works well as a TypeScript validation target.
- It avoids relying on Bun-only APIs during the earliest compiler/porting stage.
- It still leaves room for Bun packaging later.

### 8.2 Keep Bun packaging as a later gate

OpenCode's current build uses Bun to produce single-file/multi-platform binaries. That should be reintroduced only after headless, server, provider, tool, and TUI parity are green under Node.

### 8.3 Future portability stance

Do **not** design the initial code as if Rust/Go parity were required now. Instead:

- Label files/classes by runtime class: `portable`, `node-host`, `bun-host`, `generated-ts-only`.
- Keep obvious host APIs behind narrow seams.
- Keep core DTOs and pure transformations free of raw Node/Bun calls where natural.
- Defer real `haxe.rust`/`haxe.go` work until a later portability gate.

---

## 9. Proposed architecture

```text
opencodehx/
  .beads/                         # Beads task graph
  upstream/opencode/              # pinned upstream snapshot or submodule/worktree
  reference/genes.pin.json        # records the sibling ../genes checkout used for genes-ts
  src/opencodehx/                 # Haxe source of the port
    cli/
    tui/
    session/
    provider/
    tool/
    server/
    storage/
    pty/
    config/
    plugin/
    mcp/
    acp/
    lsp/
    host/                         # Node/Bun host seams
    fx/                           # small facade over Effect-like runtime patterns
    externs/                      # Haxe externs for npm packages
  src-gen/                        # generated TypeScript from genes-ts; clean/rebuildable
  dist/                           # tsc output
  test/
    parity/                       # upstream-vs-hx golden tests
    fixtures/
    smoke/
  tools/
    import-upstream-tests/
    gen-externs/
    compare-transcripts/
  hxml/
    opencodehx.node.genes-ts.hxml
    opencodehx.node.genes-js.hxml # fallback profile
    opencodehx.node.haxe-js.hxml  # emergency profile
```

### 9.1 Host seams to define early

These are not portability abstractions yet. They are containment boundaries for target-specific APIs.

| Seam | Why it matters | Initial implementation |
|---|---|---|
| Storage/SQLite | OpenCode has Bun/Node database adapters | Port existing Node adapter first; preserve adapter shape |
| Server/listen/WebSocket/SSE | Hono adapter differs by runtime | Port Node Hono adapter first |
| PTY/process/shell | shell tools and TUI workers depend on host behavior | Port Node PTY seam first |
| Filesystem/path/watch/glob/ripgrep | core tools and config rely on OS/files | Node APIs first; pure helpers where easy |
| Fetch/stream/SSE | provider streaming and server events | Use web streams/Node fetch wrappers |
| LSP process/JSON-RPC | language-server tools | Node child process + JSON-RPC seam |
| Terminal/TUI renderer | most sensitive UX surface | TSX/OpenTUI externs first |
| Plugin/package loading | dynamic imports and npm install | Node dynamic import seam |
| Env/clock/os/clipboard/editor | cross-platform behavior | small host facade, no heavy abstraction |

### 9.2 Extern strategy

Do not port external npm libraries wholesale. Use externs/facades first.

High-priority extern/facade groups:

- `effect`
- `ai` and `@ai-sdk/*`
- `hono`
- `solid-js`
- `@opentui/core` and `@opentui/solid`
- `drizzle-orm`
- `zod`
- `@modelcontextprotocol/sdk`
- `@agentclientprotocol/sdk`
- `vscode-jsonrpc`
- `tree-sitter`
- `@lydell/node-pty` / PTY adapter
- Node built-ins and Bun-specific references at seams only

Extern quality bar:

- Prefer small, typed externs around used APIs.
- Allow `Dynamic` only where upstream APIs are truly dynamic or temporarily unknown.
- Track every broad `Dynamic` as either accepted boundary debt or a later tightening bead.

### 9.3 Effect strategy

OpenCode uses `effect` heavily. Reimplementing Effect in Haxe up front would be a trap.

Recommended approach:

1. **Phase A: extern/facade compatibility.** Represent enough of `Effect`, `Layer`, `Context`, `Stream`, and related APIs to compile and preserve control flow.
2. **Phase B: narrow `opencodehx.fx` facade.** Gradually wrap effect patterns used by OpenCode into Haxe-friendly types such as `Task<T>`, `Stream<T>`, `Service<T>`, and `Layer<T>`.
3. **Phase C: optional replacement.** Only after parity, consider replacing selected effect usage with native Haxe constructs where this improves readability or future portability.

### 9.4 TSX/TUI strategy

The TUI is the highest-risk UX area. Do not begin with the full TUI.

Order:

1. Compile one minimal `@opentui/solid` TSX/HXX component through genes-ts.
2. Port theme/context/keybinding primitives.
3. Port static screens/dialog shells.
4. Port live session transcript rendering.
5. Port input composer, tool part rendering, permission dialogs, model/provider/session dialogs.
6. Add terminal snapshot and interaction replay tests.

### 9.5 Assets/resources strategy

OpenCode includes text prompts, JSON files, embedded web assets, parser workers, and TUI workers. Early strategy:

- Preserve resources as files in `src/opencodehx/resources` or copied from upstream.
- Add a generated resource manifest.
- Do not embed everything until packaging gate.
- Create a genes-ts import/resource fixture for JSON/text/worker imports.

---

## 10. Functional scope

### 10.1 In scope for first full parity line

- CLI entry and command routing
- Headless `run`
- Session creation/resume/share/import/export where upstream supports it
- Config discovery/parsing/validation
- Provider registry/model discovery/auth resolution
- Fake provider and real AI SDK provider streaming
- Tool registry and core tools:
  - read/write/edit/apply_patch
  - glob/grep
  - bash/shell/PTY
  - webfetch/websearch where upstream supports it
  - LSP tool path
  - todo/plan/task/question/skill surfaces
- Permission model
- Server/API/SSE/WebSocket behavior
- Storage schema/migrations through existing adapter shape
- Plugin loader enough for upstream tests
- TUI with keyboard/input/transcript/dialog parity
- Packaging as npm/global bin

### 10.2 Out of scope until after parity

- Caf integration layer
- Brew conversion
- Cafex replacement assertion
- Rust/Go codegen target
- Full dependency replacement
- Major UI redesign
- New agent semantics

---

## 11. Porting strategy

### 11.1 Inventory and classification first

Before translating code, produce a parity matrix for every OpenCode source module:

- source path
- ownership area
- dependencies
- runtime class: pure / Node host / Bun host / browser / TSX / generated asset
- test coverage
- port difficulty
- required externs
- `genes-ts` risks
- acceptance test

### 11.2 Use ts2hx as an accelerator, not an authority

Use the experimental `ts2hx` tooling in genes-ts to produce first-pass Haxe for mechanical modules, especially utilities and DTO-like files. Treat output as a draft.

Good candidates:

- small utilities
- path/string/json helpers
- message/config DTOs after schema decisions
- simple tool helpers
- test fixture conversion

Bad candidates for blind conversion:

- Effect-heavy session processor code
- TSX/TUI components
- dynamic provider imports
- code with overloaded/dynamic npm APIs
- advanced stream/event code

### 11.3 Port in dependency order

Recommended module order:

1. Build scaffold and externs.
2. Utilities, logger, path/env/platform helpers.
3. Config schema and config load path.
4. Message/session data model.
5. Storage seam.
6. File/tool primitives.
7. Tool registry and core file tools.
8. Fake provider + transcript parity harness.
9. Headless `run` command.
10. Session processor and tool lifecycle.
11. Provider registry and AI SDK streaming.
12. Server/API/SSE/WS.
13. Plugin/MCP/ACP/LSP.
14. TUI.
15. Packaging.

### 11.4 Keep upstream OpenCode as oracle

Every important behavior should be compared to upstream OpenCode through at least one of:

- ported unit test
- golden transcript
- CLI smoke output
- API response fixture
- terminal interaction replay
- provider stream replay
- tool filesystem fixture

---

## 12. Milestones and gates

### M0 — Repo/task bootstrap

**Objective:** Create the OpenCodeHX project skeleton and Beads graph.

Acceptance:

- `bd init` / `bd setup codex` completed in the working repo.
- Upstream OpenCode snapshot pinned.
- Standalone genes-ts dependency pinned.
- PRD and Beads seed tasks committed.
- CI or local script has named targets for compile, tsc, test, smoke.

### M1 — genes-ts NodeNext scaffold

**Objective:** Prove Haxe → TypeScript → Node works for the project structure.

Acceptance:

- `haxe hxml/opencodehx.node.genes-ts.hxml` emits split TS into `src-gen`.
- `tsc --noEmit` or equivalent passes on generated TS for minimal app.
- Generated import specifiers work under NodeNext.
- `node dist/index.js --version` or equivalent prints a scaffold version.
- Any compiler issues have minimized repros in genes-ts tests.

### M2 — Inventory, externs, and pure modules

**Objective:** Establish translation map and compile pure/support code.

Acceptance:

- Full source parity matrix exists.
- Extern policy exists for each high-priority npm dependency.
- Utilities/config/message DTO slices compile.
- First upstream tests are either ported or mapped to fixtures.
- Broad `Dynamic` usage is tracked.

### M3 — Headless credential-free one-turn flow

**Objective:** Run a one-turn session with fake provider and at least one safe tool path.

Acceptance:

- `opencodehx run` works with fake provider.
- Session creation, message append, fake model response, tool decision, and final output are recorded.
- Transcript output matches an upstream OpenCode golden fixture for the chosen scenario.
- No external credentials required.
- This is the first major go/no-go checkpoint.

### M4 — Tool and storage parity

**Objective:** Make core tools and persistence behave like OpenCode.

Acceptance:

- read/write/edit/apply_patch/glob/grep tools pass fixture tests.
- bash/PTY tool has safe smoke coverage.
- Permission model is enforced in tests.
- Storage adapter persists and reloads sessions.
- Config + storage + tool errors match upstream shape.

### M5 — Server/API parity

**Objective:** Serve the OpenCode-compatible API and event stream.

Acceptance:

- Hono routes compile and run from generated TS.
- SSE/WebSocket events match fixtures.
- SDK compatibility smoke tests pass.
- Start/stop lifecycle is reliable.

### M6 — Provider streaming parity

**Objective:** Use real provider integration through AI SDK externs/facades.

Acceptance:

- At least one real provider path streams tokens/tool calls through generated TS.
- Provider registry/model/auth/env behavior matches upstream tests.
- Stream errors, aborts, retries, and overflow/compaction paths have fixtures.

### M7 — TUI parity line

**Objective:** Port enough TUI for real use.

Acceptance:

- OpenTUI/Solid components compile through genes-ts.
- TUI boots, renders, accepts input, displays streaming transcript, handles tool parts and permission dialogs.
- Keybindings and major dialogs match upstream behavior.
- Terminal replay/snapshot tests cover the main session path.

### M8 — Packaging and release candidate

**Objective:** Ship a usable npm/global binary candidate.

Acceptance:

- `npm install -g` or local equivalent exposes `opencodehx`.
- Cross-platform Node smoke passes on supported OSes.
- Bun binary packaging feasibility report is complete.
- Generated TS, sourcemaps, assets, and resources are packaged correctly.

### M9 — Cafex replacement preflight

**Objective:** Decide whether OpenCodeHX is a credible future Cafex replacement substrate.

Acceptance:

- Cafex seam ledger is mapped to OpenCodeHX capabilities.
- Caf contract consumption points are identified.
- No Caf integration has leaked into the core port.
- Replacement candidate decision is documented with evidence.

### M10 — Portability audit

**Objective:** Determine whether Rust/Go follow-up work is realistic.

Acceptance:

- Source files are classified as portable/host/generator-specific.
- haxe.rust and haxe.go blockers are listed.
- No actual Rust/Go port is required for this milestone.

---

## 13. Test and parity plan

### 13.1 Compiler gates

- Haxe compile for genes-ts target.
- Generated TS snapshot checks for high-risk constructs.
- TypeScript strict check.
- Runtime import smoke under NodeNext.
- genes-ts minimal repro tests for every compiler bug found.

### 13.2 Unit and fixture gates

Port upstream OpenCode tests in priority order:

1. Config tests
2. File/path tests
3. Tool tests
4. Storage tests
5. Fake provider/session tests
6. Server/API tests
7. Plugin tests
8. MCP/ACP/LSP tests
9. TUI tests

### 13.3 Golden parity gates

Create upstream-vs-HX comparisons for:

- `--version` / `--help`
- config discovery and validation errors
- fake provider one-turn run
- file edit/apply_patch scenarios
- permission denial/approval
- session resume
- server event stream
- provider stream replay
- TUI interaction replay

### 13.4 Performance gates

Initial thresholds should be pragmatic, not strict:

- CLI cold start: target ≤ 1.5x upstream during early parity; tighten later.
- First token through fake provider: target ≤ 1.25x upstream.
- Tool execution overhead: target ≤ 1.25x upstream for local filesystem tools.
- TUI render/input latency: no obvious UX regression in replay harness.

---

## 14. genes-ts development loop

Every compiler limitation found during OpenCodeHX work should create two beads:

1. An `opencodehx` bead that documents the failing port scenario.
2. A `genes-ts` bead that contains the minimized compiler repro and expected output.

Definition of done for a compiler fix:

- Minimal Haxe repro added under genes-ts tests.
- Generated TS snapshot reviewed.
- `tsc` passes.
- Runtime smoke passes when relevant.
- OpenCodeHX blocked slice is unblocked.

Likely genes-ts improvement areas:

- NodeNext `.js` import specifier stability.
- Dynamic `import()` typing and codegen.
- Import attributes / resource imports.
- TSX/HXX emission for Solid/OpenTUI.
- Better extern ergonomics for npm packages.
- Async iterable / stream typing.
- Structural object typing for zod/effect-style APIs.
- Type narrowing and union output quality.
- Strict null/undefined interop.
- Sourcemap quality for generated TS.

---

## 15. Beads workflow

Use Beads as the single task source of truth.

Project setup:

```sh
bd init --quiet
bd setup codex
bd prime
```

Agent workflow:

```sh
bd ready --json
bd show <id> --json
bd update <id> --claim --json
# work, test, commit
bd close <id> --reason "accepted: ..." --json
```

Dependency policy:

- Epics own milestones.
- Tasks block downstream parity work until acceptance evidence exists.
- Compiler bugs discovered from a port task use `discovered-from` or equivalent relationship back to the port task.
- Avoid markdown TODO lists; create beads for discovered work.
- Use labels consistently:
  - `area:cli`, `area:tui`, `area:session`, `area:tool`, `area:provider`, `area:server`, `area:storage`, `area:compiler`, `area:cafex`, `area:portability`
  - `kind:parity`, `kind:extern`, `kind:compiler-repro`, `kind:fixture`, `kind:smoke`, `kind:docs`
  - `runtime:node`, `runtime:bun`, `runtime:portable`, `runtime:tsx`

A seed JSONL backlog is provided separately as `opencodehx-beads-backlog.seed.jsonl`.

---

## 16. Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Effect API complexity | Session/provider port stalls | Start with externs; add narrow `opencodehx.fx`; avoid full Effect rewrite |
| TSX/OpenTUI codegen gaps | TUI parity stalls | Build minimal fixtures first; fix genes-ts before porting full TUI |
| Dynamic imports/provider registry | Provider behavior drifts | Wrap imports in explicit host/provider seam; add generated TS snapshots |
| Bun-specific build/runtime APIs | Node scaffold breaks | Use Node adapters first; defer Bun binary packaging |
| SQLite/drizzle mismatch | Session persistence unreliable | Preserve existing adapter seam; use storage fixtures early |
| Tool side effects | Unsafe or incorrect file/shell behavior | Fake workspace fixtures; permission tests; no broad abstractions |
| Generated TS unreadable | Maintenance cost too high | Snapshot generated TS; improve genes-ts output quality as acceptance criterion |
| Upstream drift | Port lags OpenCode | Pin snapshot; periodic rebase bead; maintain parity matrix |
| Over-portability | Performance/UX degradation | Node-first policy; classify seams instead of abstracting everything |
| Cafex coupling too early | Replacement experiment becomes biased | Explicit guardrail bead and no-Caf-integration milestone |

---

## 17. Go / no-go criteria

### Continue aggressively if

- M3 headless fake-provider flow passes.
- Generated TS remains understandable and strict-checkable.
- Compiler issues are fixable with small genes-ts patches.
- Core tool/session behavior can be proven with upstream fixtures.

### Pivot to helper-only or fallback target if

- genes-ts cannot handle core NodeNext/TSX/async patterns after minimized repro work.
- Generated TS becomes too opaque to maintain.
- The Effect/session processor cannot be represented without a large semantic rewrite.
- TUI parity requires unacceptable compiler/runtime contortions.

### Consider Cafex replacement evaluation only if

- Headless + tools + provider + server + TUI parity are green enough for daily use.
- Caf contract consumption can be added without changing OpenCodeHX core semantics.
- Cafex seam ledger maps cleanly to OpenCodeHX extension points.

---

## 18. Immediate next steps

1. Create the `opencodehx` repo/workspace and initialize Beads.
2. Pin standalone `genes-ts` version `1.11.0` as a path dependency.
3. Pin the uploaded OpenCode snapshot as the upstream oracle.
4. Import or manually create the seed Beads tasks.
5. Build the M1 minimal genes-ts NodeNext scaffold.
6. Produce the full parity matrix from OpenCode source inventory.
7. Start with config/util/message DTO slices and minimal externs.
8. Create the fake-provider golden transcript harness before real provider work.
9. Keep a visible `genes-ts-limitation-ledger.md` until Beads has all compiler bugs represented.
10. Reassess after M3, not before.

---

## 19. Opinionated answer to the portability question

Your instinct is right: **do not make this portable now.** A portability-first rewrite would add abstraction pressure before we know whether the Haxe→TS port can preserve OpenCode behavior and UX. It would also make a 1:1 parity check harder because every upstream concept would be mediated through new abstractions.

The practical compromise:

- Write Haxe that is close to Node/OpenCode today.
- Isolate only obvious host seams.
- Keep pure data/transformation code naturally portable.
- Record portability classification as metadata.
- After the Haxe/TS port works, decide which slices deserve haxe.rust/haxe.go experiments.

This preserves the most important property: **OpenCodeHX should feel like OpenCode first.** Portability can be earned later from a working Haxe codebase.
