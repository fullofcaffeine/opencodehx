# Haxe-Authored Testing Strategy

OpenCodeHX should eventually author most durable test intent in Haxe, but it should not invent a private test runtime. The target output should remain normal ecosystem tests: TypeScript specs for Jest or Vitest-style unit/integration lanes, Playwright specs for browser/TUI/e2e lanes, plus shell/transcript harnesses where those are the clearest oracle.

This follows the `../haxe.ruby` pattern: framework-native tests remain first-class, while Haxe adds typed contracts and generation ergonomics around the places where drift is expensive.

The deeper reason is future portability. If OpenCodeHX later targets another runtime, Haxe-authored tests can retarget with the product code. Target-native tests are still valuable evidence, but the durable test intent should not be trapped in TypeScript-only runner syntax when Haxe can preserve it.

The Haxe layer should also improve test ergonomics, not just port syntax. Typed builders, enum-backed expected events, transcript pattern matching, composable fixtures, precise assertion helpers, and macro-generated boilerplate are all good uses of Haxe when they make tests easier to write and harder to break accidentally.

## Goals

- Preserve upstream OpenCode tests as behavior oracles.
- Keep durable test intent retargetable with the Haxe port when future non-TypeScript runtimes are added.
- Improve test authoring ergonomics with Haxe-native modeling rather than copying TypeScript runner APIs one-for-one.
- Emit idiomatic target-runner files that look close to handwritten TypeScript.
- Let Haxe types protect stable contracts: routes, event discriminants, provider/model IDs, permission outcomes, selectors, transcript step kinds, and fixture records.
- Keep generated tests debuggable by maintainers who know OpenCode and TypeScript but not the Haxe generator.
- Expose missing `genes-ts` features early through small compiler fixtures.

## Test Lanes

### Haxe-authored unit/integration specs

These should generate Jest/Vitest-compatible TypeScript specs. The exact runner can stay flexible until the upstream package and OpenCodeHX harness settle, but the generated shape should be ordinary:

```ts
import { describe, expect, test } from "vitest";
```

or:

```ts
import { describe, expect, test } from "@jest/globals";
```

Haxe should own typed fixture construction and expected DTO shapes. Generated code should keep clear test names, direct assertions, and narrow imports.

### Haxe-authored Playwright specs

Browser, web server, and later TUI replay lanes should generate Playwright-compatible specs:

```ts
import { expect, test, type Page } from "@playwright/test";
```

The Haxe layer should type stable selectors, visible states, server route contracts, and transcript operations. It should not hide the user journey behind opaque helper calls.

### Existing oracle lanes

Shell smokes, generated TS snapshots, upstream transcript fixtures, API payload comparisons, and differential harnesses remain necessary. Haxe-authored tests should complement these lanes, not crowd them out.

## Proposed Haxe Shape

The preferred shape is explicit metadata plus a declaration host, inspired by `../haxe.ruby`:

```haxe
@:opencodeTest("server/session_create_test")
class SessionCreateTest {
  @:opencodeTests
  static function define():Void {
    test("creates a session and emits the expected event", () -> {
      final session = ApiSessions.create({ provider: ProviderId.fake() });
      expect(session.id).toMatch(SessionId.pattern());
      expect(BusEvents.last()).toEqual(SessionCreated(session.id));
    });
  }
}
```

For Playwright:

```haxe
@:playwrightTest("tui/session_picker.spec")
class SessionPickerSpec {
  static function opensExistingSession(page:Page):Promise<Void> {
    page.goto(TestServer.url("/"));
    page.keyboard.press("Control+O");
    expect(SessionPicker.visible(page)).toBeTruthy();
  }
}
```

The exact APIs should be designed in a Bead before implementation. The important constraints are explicit generated paths, typed inputs, and clear generated TypeScript.

## First Prototype

The first checked-in prototype is intentionally small:

- Haxe spec source: `test/opencodehx/test/spec/FormatSpec.hx`
- Unit facade: `test/opencodehx/test/UnitSpec.hx`
- Compile target: `hxml/opencodehx.tests.bun.genes-ts.hxml`
- Harness command: `npm run test:haxe:unit`

It generates `test/generated/unit/index.ts`, writes a tiny runner-friendly `test/generated/unit/format.generated.test.ts` entry, strict-checks both with `tsconfig.test.json`, and runs the entry with `bun test`. Bun is the first unit target because upstream OpenCode uses `bun:test` heavily. The facade name stays generic because Jest/Vitest-compatible import targets should be added without rewriting Haxe-authored test intent.

Async test callbacks should prefer `@:await expr` when the operand is simple because it reads close to TypeScript while still lowering through `genes.js.Async.await(...)`. Keep `await(expr)` available for complex grouping or when the call-style macro is clearer.

## Compiler Risks To Retire Early

- Runner callback shapes that use existing `genes.js.Async` support: `@:async` functions, `await(...)`, and Promise-returning test bodies should stay covered by generated spec fixtures.
- Typed imports that preserve `type` imports in generated TypeScript.
- Erased declaration hosts or metadata-driven codegen that does not leave noisy runtime shells.
- Playwright `Page`, `Locator`, fixtures, and `test.extend` extern typing.
- Snapshot-friendly output with stable names and minimal helper churn.
- TSX/HXX support for later Solid/OpenTUI component tests.

Each compiler issue should become a small generic `../genes` fixture before broad OpenCodeHX use.

## Acceptance Model

A reliable port slice should pass the narrowest relevant gate:

- Haxe compile through `genes-ts`.
- Generated TypeScript strict check.
- Native runner execution for generated Jest/Vitest/Playwright specs.
- Upstream oracle comparison when the slice maps to an existing OpenCode test.
- Generated snapshot review for high-risk test DSL/codegen constructs.

The Bead tracking this direction is `opencodehx-jh0`.
