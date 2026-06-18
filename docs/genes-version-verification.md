# Genes / genes-ts Version Verification

**Bead:** `opencodehx-002`  
**Recorded:** 2026-06-18T04:12:42Z
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
- Source files: 33 in each tree
- `diff -qr`: differs after OpenCodeHX-driven import-attribute support and dynamic import typing fixes landed in `../genes`
- Relative-path source manifest hash for canonical `../genes/src`: `22911def82cef35c20e785d8cbeb540ca88c969c6a114eea5f084f461b80d6d8`

## Pins

Canonical `../genes` checkout:

- Branch: `main`
- Commit: `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c`
- Origin: `git@github.com:fullofcaffeine/genes-ts.git`
- Upstream: `git@github.com:benmerckx/genes.git`
- Dirty state: no tracked changes; untracked repomix artifacts are present and ignored by this verification.
- OpenCodeHX-specific compiler fix: `f88d6fb18208b9a5f40031c978162e7fbf8178e7` (`Support TypeScript import attributes`), adding `genes.ts.Imports.defaultImportWith(...)` and JSON import-attribute fixture coverage.
- Dynamic import typing fix: `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c` (`Tighten dynamic import module typing`), emitting `unknown` callback parameters plus `typeof import(...)` casts and guarding the full fixture against regressing to `module: any`.

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
