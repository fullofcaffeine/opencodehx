# genes-ts Limitation Ledger

**Bead:** `opencodehx-045`  
**Purpose:** Track every `genes-ts` limitation discovered while porting OpenCodeHX and make each one actionable in the sibling `../genes` compiler checkout.

## Current Status

OpenCodeHX remains unblocked, but several open `genes-ts` compiler limitations have been discovered during config, message, storage, tool, and session work. Each open limitation has a workaround in OpenCodeHX and should be fixed generically in `../genes` before similar patterns spread into server/provider/TUI code.

The first smoke (`opencodehx-005`) also exposed one project-configuration requirement: `package.json` must include `"type": "module"` for TypeScript NodeNext plus `verbatimModuleSyntax` to treat generated `.ts` files as ESM. That is recorded in `docs/node-next-smoke.md` and is not currently a compiler bug.

## Entry Format

Use one table row per discovered compiler limitation:

| ID | Discovered from | OpenCodeHX blocker | genes task/repro | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| `effect-dynamic-001` | `opencodehx-009` | Future config/session/provider Effect facades | none yet | `accepted-boundary-debt` | `opencodehx.fx.Task` stores the raw Effect runtime value as `Dynamic` while the exact Effect subset is discovered. Keep this isolated to `opencodehx.fx`/extern modules and tighten during config/session work. |
| `dynamic-import-any-001` | `opencodehx-010` | Generated user TS for dynamic imports contained `(module: any)` | `genes-h65`; OpenCodeHX follow-up `opencodehx-c0j` | `closed` | Fixed in `../genes` commit `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c`: `Genes.dynamicImport` now emits `unknown` callback parameters and `typeof import(...)` casts; `yarn test:genes-ts:full` guards against `module: any` regressions. |
| `rest-alias-cast-001` | `opencodehx-011` | Config schema work used `Reflect.fields`, exposing generated `unsafeCast<Rest<any>>` in `Reflect.ts` without a usable `Rest` import | `genes-lb1` | `closed` | Fixed in `../genes` commit `7ccc162886aa35e925fdc06fa995058d870f45a6`: `haxe.extern.Rest<T>` `TType` aliases now emit as `T[]`; `tests/TestType.hx` covers `Reflect.fields`; `scripts/test-genes-ts-full.ts` rejects `unsafeCast<Rest<...>>` regressions. |
| `enum-switch-temp-001` | `opencodehx-013` | Message V2 enum encoders initially generated duplicate TS declarations for repeated pattern names and multiple enum switches in one function | `genes-5j4` | `open` | OpenCodeHX is unblocked by using unique pattern variable names and one-purpose smoke helpers. `genes-ts` should still emit scoped or unique TS locals for enum switch pattern temps generically. |
| `map-get-nullability-001` | `opencodehx-014` | Storage hydration assigned `Map.get` results to `Null<Array<Part>>`, but generated strict TS saw `Part[] \| undefined` | `genes-byf` | `open` | OpenCodeHX is unblocked with a narrow `Syntax.code("{0}.inst.get({1}) ?? null", map, key)` helper. `genes-ts` should align Haxe `Map.get` nullability with strict TypeScript generically. |
| `cjs-extern-type-001` | `opencodehx-014` | `@:jsRequire("better-sqlite3")` extern constructor used as a field type emitted TS2709 against export-equals declarations | `genes-6za` | `open` | OpenCodeHX is unblocked by keeping the driver field `Dynamic` inside the host seam. `genes-ts` should support or document a generic CJS constructor extern pattern for NodeNext strict output. |
| `array-temp-collision-001` | `opencodehx-015` | Ripgrep file listing used a local `result` followed by generated `filter(...).map(...)`, causing duplicate TS local declarations | `genes-zjj` | `open` | OpenCodeHX is unblocked by replacing the combinator chain with an explicit loop. `genes-ts` should generate unique locals for array helper temporaries. |
| `optional-array-narrowing-001` | `opencodehx-015` | Iterating optional array fields after null guards still emitted `string[] \| null` temporaries under strict TS | `genes-6rs` | `open` | OpenCodeHX is unblocked with small `Dynamic` normalization helpers for optional arrays. `genes-ts` should preserve Haxe null-guard narrowing or emit non-null temporaries. |
| `secondary-extern-return-001` | `opencodehx-016` | Node fs extern `statSync():FsStats` returned a secondary extern class that generated TS referenced without an import | `genes-ast` | `open` | OpenCodeHX is unblocked by loosening `statSync` to `Dynamic` inside the Node seam. `genes-ts` should import or qualify secondary extern return types correctly. |
| `map-temp-collision-002` | `opencodehx-022` | `SessionProcessor.toTranscript(result)` using `result.messages.map(...)` emitted a local array named `result`, colliding with the function parameter under strict TS | OpenCodeHX `opencodehx-y71` | `open` | OpenCodeHX is unblocked with an explicit loop. `genes-ts` should generate unique array helper temporaries even when enclosing bindings use common names such as `result`. |
| `provider-output-polish-001` | `opencodehx-024` | Provider registry generated TS is strict-checkable but visibly less handwritten: repeated temps, `tmpN` object-literal locals, `unsafeCast` noise, and `StringMap.inst` access leak into user modules | OpenCodeHX `opencodehx-8n0`; genes `genes-oih` | `open` | OpenCodeHX is unblocked. Reduce these provider-registry shapes into generic `../genes` fixtures and improve output without weakening the Haxe provider model. |
| `optional-object-narrowing-002` | `opencodehx-nrh` | Provider schema sanitizer generated `Register.unsafeCast<ProviderJsonSchema>` after explicit null checks on optional object fields and `DynamicAccess.get` values | none yet | `open` | OpenCodeHX is unblocked and strict-checkable. `genes-ts` should emit TypeScript that relies on local null guards/control-flow narrowing instead of helper casts for optional object fields. |
| `enum-abstract-field-001` | `opencodehx-nrh` | Provider message and interleaved DTO fields typed as Haxe enum abstracts emit as plain `string` in TS typedef/object fields, while some helper positions still preserve literal unions and can produce strict TS mismatches | genes `genes-w74` | `open` | OpenCodeHX is unblocked by keeping the Haxe model typed and treating the interleaved transform helper as a string object-key after the typed model boundary. `genes-ts` should preserve enum abstract literal unions in typedef members, class fields, array element fields, and nested object fields generically. |
| `class-base-any-001` | `opencodehx-who` | Generated `.d.ts` for Haxe classes declares helper bases as `any`, for example `declare const SyncEventStore_base: any;` | OpenCodeHX `opencodehx-046` | `open` | This is a pre-existing `genes-ts` declaration-emission pattern also visible in older generated classes. OpenCodeHX is unblocked, but generated public declarations should replace helper-base `any` with a typed/unknown-safe compiler pattern or hide it from user modules. |

## Required Fields

- **ID:** stable local identifier, for example `genes-ts-limit-001`.
- **Discovered from:** OpenCodeHX Bead or source slice that exposed the issue.
- **OpenCodeHX blocker:** the task or gate blocked by the limitation.
- **genes task/repro:** the paired `../genes` Bead, test fixture, or repro path.
- **Status:** `open`, `repro-added`, `fix-in-progress`, `fixed-pending-pin`, `accepted-boundary-debt`, or `closed`.
- **Notes:** expected TS output, runtime symptom, generated snapshot concern, or accepted rationale.

## Fix Loop

When a limitation appears:

1. Reduce it to the smallest generic Haxe reproduction.
2. Add or update a `genes-ts` fixture in `../genes`.
3. Fix `genes-ts` generically, with no OpenCode-specific paths or assumptions.
4. Run the relevant `../genes` tests and the blocked OpenCodeHX gate.
5. Update `reference/genes.pin.json` after the fix is accepted.
6. Close or update the ledger row and any paired Beads.

## Boundary Debt

Broad `Dynamic`, `untyped`, generated `any`, generated `unknown`, poor NodeNext import output, TSX/HXX gaps, resource import gaps, source map regressions, or strict-null/type-narrowing holes must be tracked here unless they are clearly isolated to a documented runtime interop boundary.
