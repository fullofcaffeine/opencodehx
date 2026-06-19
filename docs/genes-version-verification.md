# Genes / genes-ts Version Verification

**Bead:** `opencodehx-002`  
**Recorded:** 2026-06-19T16:57:14Z
**Decision:** use `../genes` as the canonical compiler checkout for OpenCodeHX.

## Summary

The active sibling compiler checkout is `../genes`, not `../genes-ts`. It contains the `genes-ts` compiler mode, tests, and haxelib metadata.

Both inspected compiler copies report version `1.11.0`:

| Copy | Path | package.json | haxelib.json |
| --- | --- | --- | --- |
| Canonical checkout | `../genes` | `1.11.0` | `genes-ts` `1.11.0` |
| Cafetera vendor | `../fullofcaffeine/tools/cafetera/vendor/genes-ts` | `1.11.0` | `genes-ts` `1.11.0` |

The canonical compiler checkout is now ahead of the Cafetera vendored reference for OpenCodeHX work:

- Compared paths: `../genes/src` and `../fullofcaffeine/tools/cafetera/vendor/genes-ts/src`
- Source files: 35 in the canonical tree
- `diff -qr`: differs after OpenCodeHX-driven import-attribute support, dynamic import typing, Rest alias type-emission, async/await metadata, TS raw-type helper, TSX inline-markup, enum abstract literal-union follow-up, Undefinable object-field codegen, target-polymorphic helper docs, and optional-field branch narrowing landed in `../genes`
- Relative-path source manifest hash for canonical `../genes/src`: `3da340866271f936416844f820230bd3e08951f17306dbee12fe64121f9cf8e7`

## Pins

Canonical `../genes` checkout:

- Branch: `main`
- Commit: `bed806092d198f075a62d7da52f1d90b53feb860`
- Origin: `git@github.com:fullofcaffeine/genes-ts.git`
- Upstream: `git@github.com:benmerckx/genes.git`
- Dirty state: no tracked changes; untracked repomix artifacts are present and ignored by this verification.
- OpenCodeHX-specific compiler fix: `f88d6fb18208b9a5f40031c978162e7fbf8178e7` (`Support TypeScript import attributes`), adding `genes.ts.Imports.defaultImportWith(...)` and JSON import-attribute fixture coverage.
- Dynamic import typing fix: `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c` (`Tighten dynamic import module typing`), emitting `unknown` callback parameters plus `typeof import(...)` casts and guarding the full fixture against regressing to `module: any`.
- Rest alias type-emission fix: `7ccc162886aa35e925fdc06fa995058d870f45a6` (`Normalize Rest type aliases in TS output`), normalizing `haxe.extern.Rest<T>` aliases to `T[]` in generated TS type positions and guarding the full fixture against `unsafeCast<Rest<...>>` leaks from `Reflect.fields`.
- Undefinable object-field fix: `81d622d5e260d084f288e38cdbc345d41cbebb81` (`fix(ts): preserve undefinable object fields`), preserving `genes.ts.Undefinable<T>` as real `undefined` in object-literal fields while keeping normal Haxe nullable values on the `null` path.
- Target-polymorphic helper docs: `a3e2dc78aa8d88587b32d38dd36f9f28072e169f`, `f06b12ab66d2c85634d0c2110079a7c9a2c1b847`, and `2e0d17260161612c97a3a4c4059dece50252d81a` document the north star that `genes.ts` helpers should emit rich TypeScript without sacrificing classic ES6 output.
- Optional-field boolean narrowing fix: `bed806092d198f075a62d7da52f1d90b53feb860` (`fix(ts): narrow optional fields through boolean conditions`), carrying optional-field non-null facts through boolean `&&` and `||` branches so strict TypeScript accepts dominated field reads without source workarounds.

Cafetera vendored reference:

- Path: `../fullofcaffeine/tools/cafetera/vendor/genes-ts`
- Branch: `master`
- Commit: `d9d936ca4140fe9907476e1f0c5e18a060ad2a55`
- Role: integration reference only.

## Policy

OpenCodeHX compiler work should happen in `../genes` as generic Genes / `genes-ts` work. Do not vendor Genes into this repository by default. When a compiler limitation blocks OpenCodeHX:

1. Minimize a generic Haxe reproduction.
2. Add or update a `genes-ts` fixture in `../genes`.
3. Fix the compiler without OpenCode-specific assumptions.
4. Re-run the relevant `../genes` checks and the blocked OpenCodeHX gate.
5. Update `reference/genes.pin.json` after the fix is accepted.
