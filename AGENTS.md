# Agent Instructions

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`. The goal is not a loose rewrite: preserve OpenCode behavior and UX first, while using Haxe to make the source stronger, more deterministic, and easier to retarget later.

This project uses **bd** (Beads) as the task source of truth. Run `bd onboard` if you need local workflow help.

## Work Surface

- `../opencode` is the upstream OpenCode oracle. Inspect it for behavior, tests, structure, schemas, CLI/TUI UX, and fixtures. Do not edit it from this project unless explicitly asked.
- `../genes` is the sibling Genes checkout and contains the `genes-ts` compiler mode, sources, and tests.
- OpenCodeHX and `genes-ts` are developed together. Compiler limitations discovered here should be fixed as generic `genes-ts` improvements, not worked around with OpenCode-specific hacks.
- Keep any future Caf/Cafex work out of the Phase 1 core. Caf/Cafex is later adapter/preflight work after OpenCode parity exists; see `docs/no-caf-integration-guardrail.md`.

## Core Product Rules

1. **OpenCode parity first.** CLI, headless mode, server/API, sessions, providers, tools, storage, permissions, and TUI behavior should match upstream evidence.
2. **Haxe source is authoritative.** Generated TypeScript is a build artifact, but it is also a product surface: readable, strict-checkable, reviewable, and idiomatic enough to debug.
3. **Use `genes-ts` as the primary target.** Regular Genes and Haxe JS are diagnostic/fallback profiles only unless a task explicitly changes that.
4. **Node-first, Bun-aware.** Start with NodeNext ESM TypeScript and OpenCode's Node adapters. Preserve Bun seams for later packaging, but do not let Bun-only assumptions block early parity.
5. **Classify seams before abstracting.** Mark runtime classes such as `portable`, `node-host`, `bun-host`, `tsx`, `browser`, `resource`, or `generated-ts-only`. Add abstractions only when they reduce real coupling.
6. **Parity is empirical.** Prefer upstream tests, golden transcripts, API fixtures, terminal replays, generated TS snapshots, and smoke commands over intuition.
7. **No "it compiles" success.** A slice is done only when behavior, generated output quality, and the relevant gates are proven.

## Haxe Design Direction

This is a Haxe port, not TypeScript written with Haxe syntax.

- Prefer Haxe-native modeling where it preserves or strengthens OpenCode semantics: typed enums, enum abstracts, abstracts/newtypes, typedef records, pattern matching, null-safety, constrained generics, and small functional transformations.
- Use GADT-style typed enum patterns where they make illegal states harder to represent, especially for protocol messages, tool parts, provider stream events, permission outcomes, and state transitions.
- Use macros when they materially improve the system: deriving schema/codec glue, keeping DTOs and fixtures in sync, generating extern boilerplate, enforcing invariants, or emulating useful TypeScript features in a cleaner Haxe-native way.
- Do not use macros for cleverness alone. Macro output must remain understandable, deterministic, typed, and covered by tests or snapshots.
- Avoid long positional constructors for DTOs and protocol records. Use typed field records, named factories, or builders when call sites would otherwise lose meaning.
- Keep strings at the boundary: JSON, CLI, filesystem paths, environment variables, npm APIs, and upstream compatibility. Convert to typed values as soon as practical.
- Prefer a more functional style for pure transformations, but do not force functional purity across host seams where OpenCode behavior depends on effects.
- Keep early session-processing helpers deterministic and typed around the message/part model; promote only provider/tool/permission edges when async behavior is needed.
- For stored protocol DTOs such as Message V2, decode JSON objects into Haxe discriminated enums at the boundary, then encode back to upstream discriminant strings. Keep free-form provider metadata, errors, and tool payloads as documented boundary debt until their owning schemas are ported.
- For tools, model the registry and failure modes explicitly in Haxe first. Zod/plugin/Effect compatibility belongs at the boundary; core tool definitions should expose typed schemas, typed failures, and deterministic smoke fixtures.

## TypeScript Feature Emulation

If OpenCode relies on TypeScript features that Haxe lacks directly, try to model them deliberately rather than weakening types.

- For discriminated unions, prefer Haxe enums or enum abstracts with generated TS union output when possible.
- For structural object APIs, prefer precise typedefs, externs, abstracts, or generated facades before falling back to broad `Dynamic`.
- For overloaded npm APIs, create narrow extern/facade surfaces around the actual OpenCode usage.
- For TSX/Solid/OpenTUI patterns, add minimal `genes-ts` fixtures before porting broad TUI code.
- Track every broad `Dynamic`, `untyped`, `any`, or `unknown` as boundary debt unless it is isolated in a documented runtime interop layer.

## genes-ts Improvement Loop

When OpenCodeHX exposes a compiler limitation:

1. Reduce it to the smallest generic Haxe/`genes-ts` repro.
2. Add or update a `genes-ts` test fixture in `../genes`.
3. Fix `genes-ts` generically; do not bake in OpenCode paths, names, or assumptions.
4. Verify generated TS snapshots, `tsc`, and runtime smoke behavior where relevant.
5. Return to OpenCodeHX, update the pin/manifest or notes, and unblock the port slice.
6. Record the limitation and fix status in Beads or `docs/genes-ts-limitation-ledger.md` until Beads fully represents it.

Generated TS quality problems are compiler work, not source contortion work, when the Haxe source is otherwise a good model.

When a macro-generated TypeScript boundary needs a TS-only shape, prefer a small `@:ts.type` Haxe abstract in `genes-ts` over weakening OpenCodeHX source types. The `Genes.dynamicImport` fix uses Haxe-compatible abstracts that emit `unknown`/`unknown[]` and casts module reads to `typeof import(...)`, keeping user TS free of `module: any` while preserving Haxe typing.

When Haxe std reflection or extern aliases expose generated TS type leaks, fix the alias lowering in `genes-ts` rather than avoiding the Haxe API. The config port exposed `Reflect.fields` emitting `unsafeCast<Rest<any>>`; `../genes` now normalizes `haxe.extern.Rest<T>` aliases to `T[]` and guards the full fixture against unresolved `Rest` casts.

## Repository Layout Policy

Follow the `codex-hxrust` precedent: keep this repo as the owner of the port, not a mirror of sibling projects.

Preferred top-level shape:

```text
opencodehx/
  AGENTS.md
  docs/
  reference/
  vendor/
  hxml/
  src/opencodehx/
  src-gen/
  dist/
  test/
  fixtures/
  harness/
  scripts/
  tools/
```

- `reference/` is for small provenance artifacts: pins, manifests, fixture indexes, upstream drift reports, and selected source/test inventories.
- `vendor/` should stay empty except for documentation unless a Bead explicitly decides to vendor a narrow artifact.
- Do not vendor `../opencode` or `../genes` by default. Use sibling checkouts plus pinned commits/manifests.
- `src-gen/` and `dist/` are rebuildable generated output. Do not manually edit generated files.
- If generated snapshots are checked in for review, record the `genes-ts` pin, Haxe version, TypeScript/Node versions, hxml, and generation command.
- Keep storage access behind narrow host seams. Upstream may use `node:sqlite`, Bun SQLite, or Drizzle, but OpenCodeHX session logic should depend on Haxe store interfaces so driver swaps do not rewrite product behavior.
- Keep process-backed file search behind a narrow seam. Early slices may shell out to local `rg`; pinned ripgrep download/bootstrap is packaging work unless a tool parity fixture requires it sooner.

## Upstream Oracle Policy

Use upstream OpenCode as the behavioral authority:

- Produce a parity matrix before broad translation. Track source path, owner area, runtime class, dependencies, tests, required externs, `genes-ts` risks, and acceptance evidence.
- Port in dependency order: scaffold, utilities, config, message/session DTOs, storage seam, file/tool primitives, fake provider, headless run, session processor, providers, server, plugin/MCP/ACP/LSP, TUI, packaging.
- Keep golden evidence for high-risk UX and behavior: help/version output, config errors, fake-provider transcripts, tool edits, permission prompts, server events, provider streams, and TUI replays.
- Treat upstream OpenCode tests as oracle inputs. Adapt them into Haxe-owned fixtures or differential harnesses rather than copying blindly.
- Use `docs/ts2hx-opencode-audit.md` as the current ts2hx evidence. ts2hx is useful for inventory, dependency ordering, and small repros, but broad OpenCode conversion should be Haxe-native and parity-led rather than a blind generated rewrite.

## Extern and Interop Policy

Do not port external npm libraries wholesale early. Start with narrow externs/facades for used APIs:

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
- PTY, Node built-ins, and Bun-specific references at seams only

Prefer small typed externs. Allow `Dynamic` only where the upstream API is truly dynamic or the boundary is explicitly temporary and tracked.

Keep tool permission flow typed at the boundary. Tool code should emit `ToolPermissionRequest` records and let the session/runtime layer decide; do not inline permission policy into individual tools.

## Host Seam Policy

The initial host seam map is in `docs/host-seam-map.md`. Keep OpenCodeHX app-facing modules portable by routing Node, Bun, browser, filesystem, process, PTY, clock, crypto, terminal, and resource behavior through narrow host facades. When a port slice discovers a durable runtime quirk, update the seam map in the same change.

## Effect Strategy

Do not reimplement Effect up front.

1. Begin with extern/facade compatibility for enough `Effect`, `Layer`, `Context`, and `Stream` APIs to preserve OpenCode control flow.
2. Introduce a narrow `opencodehx.fx` facade as repeated patterns become clear.
3. Consider native Haxe replacements only after parity evidence exists and the replacement improves readability, testing, or future portability.

## Config Strategy

The initial config port is documented in `docs/config-port.md`. Keep config parsing Haxe-native at the boundary: JSON/JSONC and environment/file templates stay as strings until parsed, then closed domains should become enums or enum abstracts. Keep broad `Dynamic` only for nested schemas whose owner modules have not been ported yet, and replace those with precise typedefs/enums when provider, agent, MCP, formatter, LSP, and permission slices land.

## TUI Strategy

The TUI is the most sensitive UX surface.

- First compile one minimal Solid/OpenTUI TSX/HXX component through `genes-ts`.
- Add compiler fixtures for props, children, signals/memos, imports, components, and generated TSX accepted by TypeScript.
- Port static screens and shared theme/keybinding context before live transcript rendering.
- Use terminal snapshot/replay tests for meaningful TUI changes.

## Beads Workflow

Recommended bootstrap:

```bash
bd init --quiet
bd setup codex
bd prime
```

Recommended agent flow:

```bash
bd ready --json
bd show <id> --json
bd update <id> --claim --json
# work, test, document evidence
bd close <id> --reason "accepted: ..." --json
bd sync
```

- Import or manually create seed issues from `opencodehx-beads-backlog.seed.jsonl` in dependency order.
- Keep `external_key` values such as `opencodehx-021` visible in issue descriptions or labels until the import path is scripted.
- Avoid markdown TODO piles. Create Beads for discovered work.
- If compiler work blocks port work, create paired OpenCodeHX and `genes-ts` tasks with a clear discovered-from relationship.

## Documentation and Lessons

Keep this file current. When the port teaches a durable lesson about Haxe modeling, `genes-ts`, externs, OpenCode behavior, runtime seams, generated TS quality, or testing gates, update `AGENTS.md` or the relevant doc in the same change.

Current generated-TS hygiene lesson: avoid dense `Array.map` plus switch-expression summaries in large tool functions until `genes-ts` temp-name hygiene is fixed. Simple typed loops are clearer here and emit strict-checkable TypeScript.

For provider/session parity, keep transcript fixtures deterministic and credential-free. Early harnesses may use upstream-shaped oracle scripts, but each one must document when it should be replaced by a real upstream command runner.

For CLI parity, keep the command dispatcher pure enough to smoke test without spawning Node; use separate harness scripts for generated-binary behavior such as stdout, stderr, and exit codes.

For overload-heavy Node APIs such as `spawnSync`, keep raw extern calls dynamic at the host boundary and expose typed Haxe facades to app/tool code. This keeps generated TypeScript strict-checkable without weakening the app-facing model.

For permission work, preserve upstream's last-match wildcard rule semantics. Config-derived wildcard permission keys should sort before specific keys so specific rules override fallback rules regardless of JSON key order.

Document non-obvious advanced Haxe features with concise hxdoc:

- why the feature is used,
- what contract it enforces or generates,
- how it affects typing/codegen,
- pitfalls or boundary assumptions.

## Quality Gates

Use the narrowest relevant gate for the slice, then broaden when touching shared behavior.

- Haxe compile through `genes-ts`.
- Generated TS strict check.
- Runtime import smoke under NodeNext.
- Generated TS snapshots for high-risk constructs.
- Upstream parity fixtures or differential harnesses.
- `genes-ts` compiler tests for every compiler fix.

Before ending a substantial work session, file follow-up Beads for remaining work, run applicable gates, update issue status, sync Beads, and leave the repo in a handoff-ready state.

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
