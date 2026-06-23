# Agent Instructions

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`. The goal is not a loose rewrite: preserve OpenCode behavior and UX first, while using Haxe to make the source stronger, more deterministic, and easier to retarget later.

This project uses **bd** (Beads) as the task source of truth. Run `bd onboard` if you need local workflow help.

## Work Surface

- `../opencode` is the upstream OpenCode oracle. Inspect it for behavior, tests, structure, schemas, CLI/TUI UX, and fixtures. Do not edit it from this project unless explicitly asked.
- `../genes` is the sibling Genes checkout and contains the `genes-ts` compiler mode, sources, and tests.
- `../genes-vanilla` is the read-only reference for the original upstream Genes implementation. Use it to compare original ES/JS behavior and architecture, especially for performance-oriented ES6 output, but do not patch it from OpenCodeHX work. The source of truth for compiler changes is `../genes`.
- OpenCodeHX and `genes-ts` are developed together. Compiler limitations discovered here should be fixed as generic `genes-ts` improvements, not worked around with OpenCode-specific hacks.
- **Hard boundary: never couple `genes-ts` to OpenCodeHX.** OpenCodeHX is allowed, and expected, to drive compiler fixes, but `../genes` must never gain special knowledge of OpenCodeHX paths, names, schemas, runtime conventions, or product behavior. Reduce issues to general Haxe/JS/TS/compiler cases and fix those so every Genes user benefits.
- Keep the `../genes` repo itself project-neutral. Do not add OpenCode/OpenCodeHX-specific wording to genes source, docs, fixtures, labels, or Beads; describe discoveries there as generic downstream compiler cases.
- Keep any future Caf/Cafex work out of the Phase 1 core. Caf/Cafex is later adapter/preflight work after OpenCode parity exists; see `docs/no-caf-integration-guardrail.md`.

## Core Product Rules

1. **OpenCode parity first.** CLI, headless mode, server/API, sessions, providers, tools, storage, permissions, and TUI behavior should match upstream evidence.
2. **Haxe source is authoritative.** Generated TypeScript is a build artifact, but it is also a product surface: readable, strict-checkable, reviewable, and idiomatic enough to debug.
3. **Use `genes-ts` as the primary target.** Idiomatic strict TypeScript output is the default product surface. Regular Genes' existing ES6 path is a promising secondary, performance-oriented output profile, using `../genes-vanilla` as read-only reference and implementing any OpenCodeHX-needed compiler work in `../genes`.
4. **Node-first, Bun-aware.** Start with NodeNext ESM TypeScript and OpenCode's Node adapters. Preserve Bun seams for later packaging, but do not let Bun-only assumptions block early parity.
5. **Classify seams before abstracting.** Mark runtime classes such as `portable`, `node-host`, `bun-host`, `tsx`, `browser`, `resource`, or `generated-ts-only`. Add abstractions only when they reduce real coupling.
6. **Parity is empirical.** Prefer upstream tests, golden transcripts, API fixtures, terminal replays, generated TS snapshots, and smoke commands over intuition.
7. **No "it compiles" success.** A slice is done only when behavior, generated output quality, and the relevant gates are proven.
8. **Upstream tests are standing oracles.** Every upstream OpenCode test should eventually pass against OpenCodeHX directly or through an adapted Haxe-owned/differential harness. Until then, each test must stay represented in the port matrix with current evidence, missing scope, and an owning Bead.
9. **Docs move with the port.** Keep `README.md`, `docs/README.md`, relevant subsystem docs, and `AGENTS.md` current as behavior, workflows, gates, or architecture change. A public reader should be able to understand the repo state without replaying chat history.

## Haxe Design Direction

This is a Haxe port, not TypeScript written with Haxe syntax.

- Prefer Haxe-native modeling where it preserves or strengthens OpenCode semantics: typed enums, enum abstracts, abstracts/newtypes, typedef records, pattern matching, null-safety, constrained generics, and small functional transformations.
- Target compatibility is the floor, not the Haxe API design ceiling. Target-shaped Haxe APIs are fine, and sometimes the right canonical surface, when that shape is intentional: migration ergonomics, interop, differential testing, generated-output inspection, predictable target behavior, or preserving a widely understood host API. When there is no strong target-shaped reason, canonical APIs should default to Haxe strengths: types, macros, generated references, properties, editor completion, and compile-time diagnostics. Keep 1:1 target facades available at npm/runtime boundaries and as escape hatches, then build semantic Haxe wrappers over them when that improves readability or safety without changing target behavior. Do not hide upstream behavior behind abstractions that make parity harder to verify; the generated TypeScript should still reveal the real target calls at the boundary.
- Use GADT-style typed enum patterns where they make illegal states harder to represent, especially for protocol messages, tool parts, provider stream events, permission outcomes, and state transitions.
- Use macros when they materially improve the system: deriving schema/codec glue, keeping DTOs and fixtures in sync, generating extern boilerplate, enforcing invariants, or emulating useful TypeScript features in a cleaner Haxe-native way.
- Do not use macros for cleverness alone. Macro output must remain understandable, deterministic, typed, and covered by tests or snapshots.
- When a string parameter represents a checkable artifact rather than arbitrary user text, prefer a typed wrapper or macro-checked constructor. Route names, keybind IDs, tool IDs, config keys, schema names, resource names, event discriminants, provider/model IDs, fixture names, and generated file targets should fail at Haxe compile time whenever a catalog, enum, manifest, or local artifact can prove validity.
- Avoid long positional constructors for DTOs and protocol records. Use typed field records, named factories, or builders when call sites would otherwise lose meaning.
- Prefer Haxe extension-style APIs with `using` for common helper modules such as `StringTools` when it makes code read as a domain transformation (`text.trim()`, `path.startsWith(...)`) instead of a utility detour. Keep static calls when the helper is rare, ambiguous, or clearer as a namespaced operation.
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
- When a target/runtime concept is weakly typed but has a narrower semantic role, model that role with a Haxe type instead of passing around `Dynamic` or bare `Unknown`. Prefer opaque abstracts/newtypes such as identity keys, branded IDs, validated handles, decoded records, and capability tokens. These types should expose only the operations that are actually sound for the value, such as strict identity comparison for an opaque JS object key, and should hide raw target access behind named factories or methods with comments explaining the runtime contract. If the concept is portable but the current implementation is target-specific, document both: the semantic contract that product code may rely on and the target mechanism used today. Do not make a generic "object" helper when the real invariant is narrower.
- **Hard rule: no unjustified untyped values.** Avoid `Dynamic`, `untyped`, generated `any`, broad `unknown`, and equivalent weak types. Use them only as a last resort after confirming there is no practical typed alternative. If one is genuinely required at a runtime/test/compiler boundary, add a nearby comment explaining why the value cannot be typed yet, what contains the unsafety, and what evidence or future owner can narrow it.
- **Hard rule: casts are last-resort boundaries.** Avoid `cast`, especially casts to or from `Dynamic`, unless a typed Haxe API cannot express the runtime operation. When a cast is necessary, keep its scope tiny, guard every operation performed through it, return typed values immediately, and add a nearby comment explaining the API limitation and containment.
- **Hard rule: no casual `Syntax.code`.** Treat `js.Syntax.code` like `untyped`: use it only when Haxe externs, typed facades, standard library APIs, or a generic `genes-ts` improvement cannot express the runtime operation yet. Keep the snippet tiny and local, add a nearby comment explaining why it is necessary and how the unsafety is contained, and create a Bead if a larger raw block or repeated pattern appears. Prefer narrow externs/facades over embedding JavaScript lifecycle logic in strings.
- Do not copy upstream `any` casually. Inspect the original TypeScript first: if upstream uses `any`/`unknown`, treat that as behavior evidence, not as permission to weaken OpenCodeHX. If Haxe can recover structure from schemas, local usage, upstream tests, protocol docs, or a narrow facade, use the stronger Haxe type and generate narrower TypeScript while preserving runtime compatibility.
- Mirror upstream `any`/`unknown` only when the value is genuinely open at that boundary, such as schema passthrough, TUI control payloads before their owner schema lands, proxy forwarding, or third-party callbacks. Document the seam and narrow it as soon as the owning model exists.
- Treat `unknown` as a safer boundary marker, not a final model. When usage, schema, or upstream behavior tells us more, improve the Haxe type to a domain typedef, enum, abstract, or validated decoder and let generated TS narrow accordingly.
- Generated TypeScript must be idiomatic enough to look close to careful handwritten TS. If good Haxe source produces noisy, weakly typed, duplicated, or inefficient TS, reduce the case and improve `../genes` instead of contorting OpenCodeHX source or accepting broad `Dynamic`.
- **Hard rule: fix compiler-owned problems at the compiler, generically.** Do not add OpenCodeHX bandaids for generated TS/typecheck/codegen problems when a generic `genes-ts` fix can solve the root cause. The compiler fix must be generalized from a minimal Haxe/JS/TS repro and must not contain OpenCodeHX paths, names, schemas, or product knowledge. A temporary source workaround is allowed only to keep a slice moving while a paired `../genes` Bead/repro exists; remove the workaround once the compiler fix lands and prove it with OpenCodeHX gates.
- **Hard rule: escalate tricky compiler design instead of guessing.** If a `genes-ts` compiler, macro, type-system, interop, or output-architecture issue becomes ambiguous, risky, or tempting to solve with a clever workaround, stop and generate a detailed GPT 5.5 Pro prompt. Include the relevant repositories, files, reduced repro, current hypotheses, failed approaches, desired output, and non-negotiable rules, then use the response to guide an elegant generic fix.

## genes-ts Improvement Loop

When OpenCodeHX exposes a compiler limitation:

1. Reduce it to the smallest generic Haxe/`genes-ts` repro.
2. Add or update a `genes-ts` test fixture in `../genes`.
3. Fix `genes-ts` generically; do not bake in OpenCode paths, names, or assumptions.
4. Verify generated TS snapshots, `tsc`, and runtime smoke behavior where relevant.
5. Run and pass the full `../genes` CI gate before relying on the compiler fix here. If `../genes` CI is failing, stop OpenCodeHX/codex-hxrust-style port work and fix or explicitly resolve the compiler repo CI first; focused compiler tests are useful evidence but not enough to keep building on a broken compiler.
6. Return to OpenCodeHX, update the pin/manifest or notes, and unblock the port slice.
7. Record the limitation and fix status in Beads or `docs/genes-ts-limitation-ledger.md` until Beads fully represents it.

Before changing `../genes`, read `../genes/AGENTS.md` and follow that repository's local workflow, test, commit, push, and Beads conventions in addition to this repo's compiler-improvement loop. Treat `../genes` as an independent project with its own rules, even when compiler work is discovered from OpenCodeHX. Once work moves into `../genes`, scope Beads there too: create, claim, update, close, and sync the relevant `genes` issues from the `../genes` checkout rather than tracking compiler implementation only in OpenCodeHX.

Generated TS quality problems are compiler work, not source contortion work, when the Haxe source is otherwise a good model.

The high-level goal is deliberately twofold: build the best Haxe-native, future-portable OpenCodeHX, and build the best Haxe-to-JS/TS compiler in `genes-ts`. These goals reinforce each other only when compiler improvements remain project-agnostic. If an OpenCodeHX case tempts a special-case compiler patch, stop and extract the underlying generic language/codegen rule instead.

Treat generated TypeScript readability as a product gate: strict-checkable is necessary but not sufficient. The output should preserve useful names, avoid gratuitous temporaries and casts, emit narrow imports/types, and remain efficient enough that an OpenCode maintainer could debug it directly.

Source-authored fixed tool references should use `ToolIDs.known("...")` or `KnownToolID` rather than naked strings. Keep model-emitted, plugin, config, unknown-tool, and permission-policy strings at the runtime boundary unless a local catalog proves them.

Current checked artifact constructors are documented in `docs/checked-artifact-constructors.md`. In addition to TUI routes/keybinds and tool IDs, built-in provider IDs should use `ProviderIDs.known("...")` or `KnownProviderID`, TUI dialog fixture provider IDs should use `TuiProviderIDs.known("...")`, source-authored server/SSE events should use `ServerEventTypes.known("...")`, and Haxe-owned copied-resource reads should use `ResourcePaths.known("...")`. Do not force config keys, plugin-defined provider IDs, `models.dev` model IDs, typo-suggestion fixtures, or JS harness generated-output paths into Haxe macros; keep them as boundary data or use the owning follow-up Bead.

When OpenCodeHX uses `genes.ts` helper abstractions such as `Unknown`, `Undefinable<T>`, JSX/TSX helpers, import-type helpers, or future TS-only type shims, make sure they are target-polymorphic. They may emit richer TypeScript in `genes-ts` mode, but they must erase/degrade to equivalent runnable ES6 through classic Genes unless a documented target guard says otherwise. ES6 compatibility must not lower TypeScript output quality; if the two targets pull against each other, fix the architecture generically in `../genes` with shared semantic models and target-specific emitters instead of weakening generated TS or contorting OpenCodeHX source.

Treat `@:ts.type("...")` as a raw TypeScript override and a last-resort escape hatch, not a normal interop design tool. Prefer ordinary Haxe typedefs/enums/abstracts, `DynamicAccess<T>` for string-keyed maps, narrow externs/facades for libraries, and typed decoders for runtime data. If a reusable TS-only primitive is needed, add a named generic helper in `../genes` such as `genes.ts.Unknown` or `genes.ts.Undefinable<T>` rather than scattering raw strings through OpenCodeHX. Any remaining raw override must live at a boundary, be named and documented, and be tracked for eventual replacement or audit.

Keep `reference/raw-ts-type-overrides.md` synchronized with every surviving `@:ts.type("...")` use. New raw overrides require a boundary justification and a replacement direction in that manifest in the same change.

When a macro-generated TypeScript boundary needs a TS-only shape, prefer a small named Haxe abstraction in `genes-ts` over weakening OpenCodeHX source types. The `Genes.dynamicImport` fix uses Haxe-compatible abstracts that emit `unknown`/`unknown[]` and casts module reads to `typeof import(...)`, keeping user TS free of `module: any` while preserving Haxe typing.

When Haxe std reflection or extern aliases expose generated TS type leaks, fix the alias lowering in `genes-ts` rather than avoiding the Haxe API. The config port exposed `Reflect.fields` emitting `unsafeCast<Rest<any>>`; `../genes` now normalizes `haxe.extern.Rest<T>` aliases to `T[]` and guards the full fixture against unresolved `Rest` casts.

For untrusted JSON/JS values, use the generic `genes.ts.Unknown`, `UnknownNarrow`, `UnknownRecord`, and read-only `UnknownArray` primitives rather than project-local raw narrowing helpers. OpenCodeHX owns domain decoders, defaults, and error policy; `genes.ts` owns reusable boundary mechanics. Decoders should combine guard + conversion, avoid public `isX/asX` pairs, prove own-property access before reads, distinguish `null` from `undefined` when the boundary cares, and copy validated arrays/records into precise domain types before storing them.

For provider registry work, model stable provider facts in Haxe first: provider/model IDs as abstracts, capabilities/costs/limits/headers as typed records, and upstream unions such as `interleaved` as Haxe union-friendly types. Keep provider `options` and `variants` open only because upstream treats them as provider-SDK passthrough `Record<string, any>` data, and narrow provider-specific options through facades when a runtime path owns them.

For resource imports under NodeNext, keep the explicit `opencodehx.resource.Resources` adapter as the plain-Node fallback for copied `.txt`, file-path, and `.wasm` assets. `../genes` commit `c1b0d8e` adds generic `genes.ts.Imports.text`, `file`, `dynamicWith`, and `dynamicWasm` helpers for hosts that own a loader or bundler contract, and JSON import attributes are covered by `genes.ts.Imports.defaultImportWith(...)`. Do not replace copied runtime helpers with direct resource imports unless the target runtime path proves how those assets load outside a bundler.

For markdown-backed config discovery, treat frontmatter parsing as an `unknown` boundary only at the parser. Command, agent, and mode loaders must immediately narrow owned fields into typed Haxe records, preserve only documented passthrough keys such as agent `options`, and avoid leaking broad `Dynamic`/`any` into app-facing config.

For skills, keep filesystem and remote discovery in typed registries (`SkillInfo`, dirs, sorted formatting). `SkillRegistry.available` should filter with `permission.skill` rules using the skill name as the pattern, preserving last-match wildcard semantics through `PermissionRules`. Remote `skills.urls` must go through an explicit discovery/cache seam: fetch `index.json`, require `SKILL.md`, cache listed files under a contained root, and do not let remote file paths escape the cache. The current remote download seam writes text files; add a typed `ArrayBuffer`/`Uint8Array` fs path before claiming arbitrary binary skill resources.

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
- Before starting a subsystem Bead, filter `reference/opencode-test-port-matrix.csv` by `next_bead` and promote the relevant upstream rows into Haxe-owned fixtures, differential harnesses, or explicitly deferred evidence.
- Port in dependency order: scaffold, utilities, config, message/session DTOs, storage seam, file/tool primitives, fake provider, headless run, session processor, providers, server, plugin/MCP/ACP/LSP, TUI, packaging.
- Keep golden evidence for high-risk UX and behavior: help/version output, config errors, fake-provider transcripts, tool edits, permission prompts, server events, provider streams, and TUI replays.
- Treat upstream OpenCode tests as oracle inputs. Adapt them into Haxe-owned fixtures or differential harnesses rather than copying blindly.
- Use `docs/ts2hx-opencode-audit.md` as the current ts2hx evidence. ts2hx is useful for inventory, dependency ordering, and small repros, but broad OpenCode conversion should be Haxe-native and parity-led rather than a blind generated rewrite.

## Haxe-Authored Testing Strategy

Use `../haxe.ruby` as the local precedent for typed source tests that generate native target tests. The goal is not to replace the host ecosystem's runners; it is to author more of the durable test intent in Haxe while still emitting idiomatic Jest/Vitest/Playwright specs that OpenCode maintainers can read and run normally.

- Native target tests remain first-class. Upstream OpenCode tests, generated TypeScript tests, Jest/Vitest-compatible specs, Playwright specs, shell smokes, and transcript fixtures are all valid oracle evidence.
- Haxe-authored tests are a portability asset. When OpenCodeHX retargets beyond TypeScript, typed test intent should retarget too, instead of leaving the next runtime with only TypeScript/Bun/Jest/Playwright-specific tests to translate by hand.
- Use Haxe to improve test ergonomics where it can: typed builders, enums for expected events, pattern matching for transcripts, composable fixtures, precise assertion helpers, and macro-generated boilerplate are welcome when they make tests clearer and safer.
- Haxe-authored test layers should add value through types: typed fixtures, API routes, event names, provider/model IDs, permission outcomes, selector contracts, tool input/output records, and generated golden helpers.
- Prefer explicit declaration hosts and metadata over magic discovery. A future test facade should make the generated file path, runner kind, and target shape obvious at the Haxe call site.
- Generate normal target-runner files. Jest/Vitest output should look like careful handwritten TypeScript tests; Playwright output should import from `@playwright/test` and use standard `test`, `expect`, fixtures, and `Page` typing.
- In Haxe-authored async tests, prefer `@:await expr` for simple Promise operands because it reads close to TypeScript and retargets through `genes-ts`; keep `await(expr)` for complex grouping or when explicit call-style syntax is clearer.
- Keep tests thin at host seams. Browser/TUI tests should assert visible behavior and stable events, while pure transformations and DTO invariants should stay in fast Haxe/TS unit fixtures.
- Use Haxe facades to reduce drift, not hide behavior. Selectors, server paths, event discriminants, config keys, and transcript step kinds should be typed where practical, but the generated spec should still reveal the user-facing action being tested.
- Any compiler feature needed for test generation, such as async fixtures, TSX, import typing, erased declaration hosts, or snapshot-friendly output, belongs in `../genes` with a minimal generic fixture before depending on it broadly here.

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

For Hono/server work, model the library seam with narrow externs before writing route logic. Route handlers should receive a typed context, preserve real JavaScript boundary shapes such as `string | undefined` in generated TS when needed, then normalize into Haxe `Null<T>` or domain DTOs at the app boundary. Avoid `Dynamic` for stable adapter values like WebSocket runtimes or server listeners.

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
- Prefer genes-ts default inline markup (`<box>...</box>`) for Haxe-authored TUI components. String-based `jsx("...")` remains an escape for parser gaps such as fragment roots, but normal handwritten UI should prove the HHX path and keep Haxe expression splices typed.
- Prefer macro-checked TUI artifact constructors over naked strings for known routes, keybind action IDs, component slots, test fixture names, and snapshot paths. The built-in plugin route path uses `TuiRoutes.plugin("themes")`, and built-in keybind action references use `TuiKeybindActions.action("theme_list")`, so typos fail during Haxe compilation instead of becoming missing runtime artifacts.
- Keep the first TUI gate small and reproducible: a Haxe-authored TSX scaffold, OpenTUI's test renderer contract, generated TSX snapshot, strict `tsc`, and an explicitly tracked runtime smoke before moving to the full terminal renderer.
- Run OpenTUI/Solid runtime gates with the repo-pinned Bun binary, not Node or a developer's global Bun. The current scaffold uses `scripts/harness/opentui-solid-preload.mjs` so Babel accepts `genes-ts` support-module `declare` fields while preserving OpenTUI's Solid transform behavior.
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
bd export -o .beads/issues.jsonl
bd dolt push
```

- Import or manually create seed issues from `opencodehx-beads-backlog.seed.jsonl` in dependency order.
- Keep `external_key` values such as `opencodehx-021` visible in issue descriptions or labels until the import path is scripted.
- Avoid markdown TODO piles. Create Beads for discovered work.
- If compiler work blocks port work, create paired OpenCodeHX and `genes-ts` tasks with a clear discovered-from relationship.
- For bd `1.0.4`, there is no top-level `bd sync` command even though some generic help text may still mention it. Use `bd dolt pull` to pull Beads changes, `bd dolt push` to publish Beads changes, and `bd export -o .beads/issues.jsonl` to refresh this repo's git-tracked Beads snapshot.

## Documentation and Lessons

Keep this file current. When the port teaches a durable lesson about Haxe modeling, `genes-ts`, externs, OpenCode behavior, runtime seams, generated TS quality, or testing gates, update `AGENTS.md` or the relevant doc in the same change.

Keep README-level docs current too. New build/test commands, public-readiness steps, subsystem status, important generated artifacts, and cross-repo workflow changes should update `README.md` or `docs/README.md` in the same task that introduces them. Subsystem implementation details should land in the nearest focused doc, with the README linking only the durable orientation a newcomer needs.

Keep the ASCII progress bar in `README.md` synchronized with Beads. Treat it as an unweighted planning snapshot from non-epic `opencodehx-*` issues, and refresh it when closing meaningful port slices or adding/removing substantial backlog items.

Keep public-readiness scaffolding current with the codebase. Changes to release/versioning, CI, hooks, secret scanning, package metadata, `genes-ts` checkout assumptions, or public docs must update `scripts/ci/*`, `.github/workflows/*`, `README.md`, and `CHANGELOG.md` expectations together. OpenCodeHX stays on `0.x` beta semver until parity and packaging evidence justify stable release claims.

Current generated-TS hygiene lesson: avoid dense `Array.map` plus switch-expression summaries in large tool functions until `genes-ts` temp-name hygiene is fixed. Simple typed loops are clearer here and emit strict-checkable TypeScript.

Current `genes-ts` temp-local lesson: Haxe compiler temps such as `_g`, `_g1`, catch locals, and array-helper locals can collide in TypeScript because TS is stricter about block/function scopes and catch parameters. Fix these in `../genes` with stable typed-local emission and generic fixtures; do not contort OpenCodeHX source just to avoid compiler-generated temp names.

For provider/session parity, keep transcript fixtures deterministic and credential-free. Early harnesses may use upstream-shaped oracle scripts, but each one must document when it should be replaced by a real upstream command runner.

For CLI parity, keep the command dispatcher pure enough to smoke test without spawning Node; use separate harness scripts for generated-binary behavior such as stdout, stderr, and exit codes.

For plugin config discovery, scan only the upstream-shaped immediate `plugin/*.{ts,js}` and `plugins/*.{ts,js}` roots, normalize discovered local files to file URL specs, and attach provenance before dedupe. For file-backed config entries, resolve path-like plugin specs (`file://`, relative `.` specs, absolute POSIX paths, and Windows-drive paths) relative to the declaring config file before merge/dedupe, including package-directory and index-file target handling. Loading plugin modules and npm dependency installation remain separate runtime slices.

For remote well-known config, keep network fetching in an explicit async loader path. Fetch `/.well-known/opencode` from normalized base URLs, inject advertised auth tokens into the substitution env before parsing, merge remote config before local project config, and avoid letting default-only local fields override remote-provided fields.

For remote account/org config, preserve the upstream order: load active account config after project/config-dir/content sources, inject `OPENCODE_CONSOLE_TOKEN` into the substitution env before parsing, and treat the real account repo/service as a separate runtime slice. Until that service exists, use explicit typed remote source records rather than hidden globals or broad `Dynamic`.

For managed config, keep MDM/mobileconfig parsing pure and explicit: strip platform metadata keys before normal config parsing, merge the managed source after user/remote sources and before final normalization, and leave OS-specific managed preference discovery to a host seam slice.

For overload-heavy Node APIs such as `spawnSync`, keep raw extern calls dynamic at the host boundary and expose typed Haxe facades to app/tool code. This keeps generated TypeScript strict-checkable without weakening the app-facing model.

For parser-backed bash permissions, preload `web-tree-sitter` and grammar WASM assets through `BashCommandScanner.preload()` before executing bash tools. Keep parser-owned `Tree`/`Node` values behind narrow extern abstracts and return typed scanner DTOs to application code; string scanners are fallback/debt only when the parser is not initialized.

For PTY work, keep `@lydell/node-pty` and future `bun-pty` details behind `PtyService`/host externs. App-facing code should consume typed `PtyInfo`, lifecycle events, and operations instead of raw process handles or package-specific objects.

For PTY WebSocket work, keep output buffering, cursor metadata frames, write/resize control flow, and subscriber identity inside `PtyService` plus the narrow server adapter. Hono/Bun may recycle or mutate WebSocket wrapper objects; mirror upstream by keying subscribers on `ws.data` object identity when present and never let reused socket wrappers leak output between PTY sessions. Any `unknown` used for socket identity must stay at this host boundary and be compared only by strict JS identity.

For npm package-cache parity, keep registry fetches, Arborist-style reify, and package-manager side effects behind typed seams. Haxe smoke fixtures should assert cache paths, package-lock dirtiness, bin selection, and semver/outdated behavior deterministically without invoking live package managers; real npm/bun/pnpm/Homebrew/Scoop/Chocolatey side effects belong in explicit side-effect harnesses.

For permission work, preserve upstream's last-match wildcard rule semantics. Config-derived wildcard permission keys should sort before specific keys so specific rules override fallback rules regardless of JSON key order.

For legacy top-level config `tools`, keep the input typed as `tool -> Bool` and normalize it after config sources merge. Map `write`, `edit`, and `patch` to the `edit` permission, convert booleans to `allow`/`deny`, and let explicit `permission` config override migrated tool permissions.

For final config normalization, preserve upstream order: merge all config sources first, then apply `OPENCODE_PERMISSION`, migrate legacy `tools`, apply `autoshare: true` to `share: "auto"` only when `share` is absent, and finally apply compaction disable flags.

For legacy config migrations, keep old-format parsing at a narrow documented boundary, immediately normalize into `ConfigInfo`, then write modern JSON/JSONC output. Prefer a `tink_json`-style typed decoder for known closed shapes, but preserve unknown rest fields explicitly when upstream migration semantics require round-tripping or merging data outside the known fields. Migration failure should be best-effort when upstream swallows it, but generated TS should still use `unknown`/typed records rather than broad `any`.

Document non-obvious advanced Haxe features with concise hxdoc:

- why the feature is used,
- what contract it enforces or generates,
- how it affects typing/codegen,
- pitfalls or boundary assumptions.

For non-obvious port changes, especially extern/facade boundaries, decoder boundaries, compiler-driven source choices, and generated-TS hygiene fixes, add nearby comments or hxdoc with the same why/what/how context. The comment should explain the upstream or runtime fact being preserved, the typing/codegen invariant, and what evidence or follow-up can remove the special handling later. Do not leave future agents to rediscover subtle reasoning from a passing test alone.

## Quality Gates

Use the narrowest relevant gate for the slice, then broaden when touching shared behavior.

- Haxe compile through `genes-ts`.
- Generated TS strict check.
- Runtime import smoke under NodeNext.
- Generated TS snapshots for high-risk constructs.
- Upstream parity fixtures or differential harnesses.
- `genes-ts` compiler tests for every compiler fix.

Before ending a substantial work session, file follow-up Beads for remaining work, run applicable gates, update issue status, refresh `.beads/issues.jsonl` with `bd export -o .beads/issues.jsonl`, push Beads with `bd dolt push` when a Dolt remote is configured, and leave the repo in a handoff-ready state.

## Landing the Plane (Session Completion)

**After each completed task**, commit and push the relevant repo before moving on to the next task. If work spans OpenCodeHX and `../genes`, each repo gets its own focused commit and successful push. Do not batch completed tasks into a later session-level push.

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt pull
   bd export -o .beads/issues.jsonl
   bd dolt push
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
