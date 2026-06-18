# genes-ts Limitation Ledger

**Bead:** `opencodehx-045`  
**Purpose:** Track every `genes-ts` limitation discovered while porting OpenCodeHX and make each one actionable in the sibling `../genes` compiler checkout.

## Current Status

No open `genes-ts` compiler limitations are known from the initial NodeNext scaffold.

The first smoke (`opencodehx-005`) did expose one project-configuration requirement: `package.json` must include `"type": "module"` for TypeScript NodeNext plus `verbatimModuleSyntax` to treat generated `.ts` files as ESM. That is recorded in `docs/node-next-smoke.md` and is not currently a compiler bug.

## Entry Format

Use one table row per discovered compiler limitation:

| ID | Discovered from | OpenCodeHX blocker | genes task/repro | Status | Notes |
| --- | --- | --- | --- | --- | --- |
| _none_ | | | | | |

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
