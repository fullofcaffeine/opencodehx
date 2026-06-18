# genes-ts Limitation Ledger

**Bead:** `opencodehx-045`  
**Purpose:** Track every `genes-ts` limitation discovered while porting OpenCodeHX and make each one actionable in the sibling `../genes` compiler checkout.

## Current Status

No open `genes-ts` compiler limitations are known from the initial NodeNext scaffold or import-resource smoke.

The first smoke (`opencodehx-005`) did expose one project-configuration requirement: `package.json` must include `"type": "module"` for TypeScript NodeNext plus `verbatimModuleSyntax` to treat generated `.ts` files as ESM. That is recorded in `docs/node-next-smoke.md` and is not currently a compiler bug.

## Entry Format

Use one table row per discovered compiler limitation:

| ID | Discovered from | OpenCodeHX blocker | genes task/repro | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| `effect-dynamic-001` | `opencodehx-009` | Future config/session/provider Effect facades | none yet | `accepted-boundary-debt` | `opencodehx.fx.Task` stores the raw Effect runtime value as `Dynamic` while the exact Effect subset is discovered. Keep this isolated to `opencodehx.fx`/extern modules and tighten during config/session work. |
| `dynamic-import-any-001` | `opencodehx-010` | Generated user TS for dynamic imports contained `(module: any)` | `genes-h65`; OpenCodeHX follow-up `opencodehx-c0j` | `closed` | Fixed in `../genes` commit `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c`: `Genes.dynamicImport` now emits `unknown` callback parameters and `typeof import(...)` casts; `yarn test:genes-ts:full` guards against `module: any` regressions. |
| `rest-alias-cast-001` | `opencodehx-011` | Config schema work used `Reflect.fields`, exposing generated `unsafeCast<Rest<any>>` in `Reflect.ts` without a usable `Rest` import | `genes-lb1` | `closed` | Fixed in `../genes` commit `7ccc162886aa35e925fdc06fa995058d870f45a6`: `haxe.extern.Rest<T>` `TType` aliases now emit as `T[]`; `tests/TestType.hx` covers `Reflect.fields`; `scripts/test-genes-ts-full.ts` rejects `unsafeCast<Rest<...>>` regressions. |

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
