# Genes / genes-ts Version Verification

**Bead:** `opencodehx-002`  
**Recorded:** 2026-06-19T21:21:53Z
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
- `diff -qr`: differs after OpenCodeHX-driven import-attribute support, dynamic import typing, Rest alias type-emission, async/await metadata, TS raw-type helper, TSX inline-markup, enum abstract literal-union follow-up, Undefinable object-field codegen, target-polymorphic helper docs, optional-field branch narrowing, Undefinable assignment output fixes, null-guarded local cast elision, `@:native` anonymous-field emission fixes, array element expected-type propagation fixes, ternary branch expected-type propagation fixes, abstract-underlying anonymous-field context fixes, call-argument/EitherType object context fixes, raw syntax-template native-field fixes, optional-field nullable-parameter fixes, raw placeholder call-context fixes, narrowed call-argument cast elision, Promise.resolve(null) thenable-cast elision, raw syntax-template receiver parenthesization, and dependency/security gate refresh landed in `../genes`
- Relative-path source manifest hash for canonical `../genes/src`: `291c0b6c5dc0508b171039598e2231d3b4bcbe880ed55911e332bfcf03e9b74e`

## Pins

Canonical `../genes` checkout:

- Branch: `main`
- Commit: `5254f9fc4b405824b8cf406b0201687e0c21e7cd`
- Origin: `git@github.com:fullofcaffeine/genes-ts.git`
- Upstream: `git@github.com:benmerckx/genes.git`
- Dirty state: no tracked changes; untracked repomix artifacts are present and ignored by this verification.
- OpenCodeHX-specific compiler fix: `f88d6fb18208b9a5f40031c978162e7fbf8178e7` (`Support TypeScript import attributes`), adding `genes.ts.Imports.defaultImportWith(...)` and JSON import-attribute fixture coverage.
- Dynamic import typing fix: `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c` (`Tighten dynamic import module typing`), emitting `unknown` callback parameters plus `typeof import(...)` casts and guarding the full fixture against regressing to `module: any`.
- Rest alias type-emission fix: `7ccc162886aa35e925fdc06fa995058d870f45a6` (`Normalize Rest type aliases in TS output`), normalizing `haxe.extern.Rest<T>` aliases to `T[]` in generated TS type positions and guarding the full fixture against `unsafeCast<Rest<...>>` leaks from `Reflect.fields`.
- Undefinable object-field fix: `81d622d5e260d084f288e38cdbc345d41cbebb81` (`fix(ts): preserve undefinable object fields`), preserving `genes.ts.Undefinable<T>` as real `undefined` in object-literal fields while keeping normal Haxe nullable values on the `null` path.
- Target-polymorphic helper docs: `a3e2dc78aa8d88587b32d38dd36f9f28072e169f`, `f06b12ab66d2c85634d0c2110079a7c9a2c1b847`, and `2e0d17260161612c97a3a4c4059dece50252d81a` document the north star that `genes.ts` helpers should emit rich TypeScript without sacrificing classic ES6 output.
- Optional-field boolean narrowing fix: `bed806092d198f075a62d7da52f1d90b53feb860` (`fix(ts): narrow optional fields through boolean conditions`), carrying optional-field non-null facts through boolean `&&` and `||` branches so strict TypeScript accepts dominated field reads without source workarounds.
- Undefinable assignment output fix: `dacd5f8572adad6c0f194549795ac5be04ffa4b5` (`fix(ts): preserve undefinable assignment output`), preserving `undefined` for `genes.ts.Undefinable<T>` assignments, returns, ternaries, array elements, and variable initializers.
- Null-guarded local cast elision: `b96af41741e6ea2b0e36c5a50005e38af4aebeb3` (`fix(ts): elide null-guarded local casts`), removing unnecessary generated `Register.unsafeCast<T>(value)` after stable nullable local null guards while preserving conservative casts for unproven paths.
- Native anonymous-field emission: `72fe8de0ced809cc07f5f9954bae2185697a7c68` (`fix(ts): honor native anonymous fields`), honoring `@:native("...")` on anonymous/typedef fields in generated TS type members, object literal keys, field access, and classic JS runtime object keys.
- Array element expected-type propagation: `0e722e4ad5cf86a35e81813d8d92eddd20932ad3` (`fix(ts): propagate array element context`), carrying expected `Array<T>` element types into array literal object members so nested `@:native` fields and helper abstractions emit the same idiomatic TS as direct object fields.
- Ternary branch expected-type propagation: `e6a9d8c23b3ed3e415b924aef96173acbc413e61` (`fix(ts): propagate ternary expected types`), carrying object-field and destination types into conditional-expression branches so `genes.ts.Undefinable<T>` emits `undefined` instead of `null` inside typed ternary object fields.
- Abstract anonymous-field context: `5c4adb14cb397e43eec5eeeba650a94d01ae73fa` (`fix(ts): use abstract object field context`), looking through Haxe abstracts over anonymous shapes during contextual object-field emission so raw TS bridge abstracts still preserve field metadata such as `Undefinable<T>`.
- Call-argument and EitherType object context: `5b93d285bbf3325c5647c16863af02c7e7fd1c45` (`fix(ts): propagate call argument object context`), carrying typed function-parameter context into call arguments and looking through `haxe.extern.EitherType` object arms so `@:native` anonymous fields emit correctly inside `Array<T>.push(...)` and TS-style union object returns.
- Raw syntax-template native fields: `909b9cfae0c8bf917cd93e5644d22c48718a3c51` (`fix(ts): preserve native fields in syntax templates`), emitting `js.Syntax.code("...", args...)` placeholder values through Genes' raw JS value path so helper templates such as `Undefinable.orNull()` preserve `@:native` anonymous field names without injecting TS-only casts into raw runtime snippets.
- Optional fields passed to nullable params: `a5b4802b3f81c06d2cb6ebc560f8ec8d8522d5d4` (`fix(ts): normalize optional fields for nullable params`), normalizing optional field reads to `?? null` when Haxe expects `Null<T>` so strict TS accepts direct calls to nullable-parameter helpers.
- Nested optional nullable-param reads: `e93a7fa303bf6ca2fca41135ff7a55603d901881` (`fix(ts): preserve nested optional field emission`), preserving TS-specific nested optional-field/null-normalization behavior through receiver chains.
- Raw placeholder call context: `230bbecbdd9717e509bc91984bd6b21d179f6ff1` (`fix(ts): preserve raw placeholder call context`), letting `js.Syntax.code`/`@:await` placeholders emit call arguments with TS expected-type context instead of bypassing nullable normalization.
- Narrowed call arguments: `3b5850e1fe0faf7af9c5fef2ce792b4a3b3f232c` (`fix(ts): trust narrowed call arguments`), honoring existing null-narrowing facts when nullable locals or optional fields are passed directly to non-nullable function parameters inside guarded branches.
- Full CI gate restoration: `5236989aa6f5acaa6a6d879a2aa1d01f37245ae8` (`fix(ci): restore full genes gate`), refreshing dependency/security pins and eliding the Haxe stdlib `ThenableStruct` overload cast for `Promise.resolve(null)` so full `genes-ts` output emits idiomatic `Promise.resolve(null)` instead of leaking unresolved target helper types.
- Raw syntax-template receiver parenthesization: `5254f9fc4b405824b8cf406b0201687e0c21e7cd` (`fix(genes-ts): parenthesize raw template receivers`), parenthesizing non-trivial `js.Syntax.code("...", args...)` placeholder templates before chained `[]`/`.` access so helpers such as `genes.ts.Undefinable<T>.orNull()` emit valid, handwritten-looking TypeScript in receiver position.

## Current Gate Evidence

- `../genes`: `yarn test:ci` passed on 2026-06-19 at `5254f9fc4b405824b8cf406b0201687e0c21e7cd`, covering security/dependency scanning, classic Genes JS runtime tests, `genes-ts` strict/snapshot/full acceptance, todoapp Playwright smoke tests, and ts2hx fixtures.

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
