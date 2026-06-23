# Genes / genes-ts Version Verification

**Bead:** `opencodehx-002`  
**Recorded:** 2026-06-23T17:39:16Z
**Decision:** use `../genes` as the canonical compiler checkout for OpenCodeHX.

## Summary

The active sibling compiler checkout is `../genes`, not `../genes-ts`. It contains the `genes-ts` compiler mode, tests, and haxelib metadata.

The active compiler checkout reports `1.12.0`; the older Cafetera vendored reference still reports `1.11.0`:

| Copy | Path | package.json | haxelib.json |
| --- | --- | --- | --- |
| Canonical checkout | `../genes` | `1.12.0` | `genes-ts` `1.12.0` |
| Cafetera vendor | `../fullofcaffeine/tools/cafetera/vendor/genes-ts` | `1.11.0` | `genes-ts` `1.11.0` |

The canonical compiler checkout is now ahead of the Cafetera vendored reference for OpenCodeHX work:

- Compared paths: `../genes/src` and `../fullofcaffeine/tools/cafetera/vendor/genes-ts/src`
- Source files: 38 in the canonical tree
- `diff -qr`: differs after OpenCodeHX-driven import-attribute support, dynamic import typing, Rest alias type-emission, async/await metadata, TS raw-type helper, TSX inline-markup, enum abstract literal-union follow-up, Undefinable object-field codegen, target-polymorphic helper docs, optional-field branch narrowing, Undefinable assignment output fixes, null-guarded local cast elision, `@:native` anonymous-field emission fixes, array element expected-type propagation fixes, ternary branch expected-type propagation fixes, abstract-underlying anonymous-field context fixes, call-argument/EitherType object context fixes, raw syntax-template native-field fixes, optional-field nullable-parameter fixes, raw placeholder call-context fixes, narrowed call-argument cast elision, Promise.resolve(null) thenable-cast elision, raw syntax-template receiver parenthesization, dependency/security gate refresh, closed enum abstract declaration/field/local literal-union preservation, inline local-name collision handling, nullish null-comparison parenthesization, nullable branch local cast elision, typed catch temp lowering, map facade non-inlining, exiting null-guard flow, map presence/key-iteration narrowing, object-construction temp naming, callback null/bind output polish, and TSX child temp naming fixes landed in `../genes`
- Relative-path source manifest hash for canonical `../genes/src`: `a08448ea28e049fb2e32cf44dc3568f178d67184ed584f8b9958b5ca62331440`

## Pins

Canonical `../genes` checkout:

- Branch: `main`
- Commit: `9c129acf60db6bfef0dae2699d32f8b5e146b6fe`
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
- Closed enum abstract literal-union preservation: `ea54cb1251877e2f408a56cbfc9d2d4598e526ae` (`fix(ts): preserve closed enum abstract unions`), keeping closed enum abstract literal unions through typedef fields, class fields, and locals initialized from cached calls/fields while deliberately degrading open `from` abstracts to their backing type.
- Inline local-name collision handling: `8acd1061fb633ea99a2c78c0267cbec436bef6ff` (`fix(ts): avoid inline local name collisions`), allocating emitted local names by typed `TVar.id` within each function/lexical block so inline-expanded Haxe helpers such as `Map.set(key, value)` can generate `value`/`value_1` instead of duplicate function-scoped declarations with incompatible TS types.
- Nullish null-comparison parenthesization: `ab862272e1813d44393fa5e8bc059a8fb7d67298` (`fix(ts): parenthesize nullish null comparisons`), wrapping nullish-coalescing operands when they are emitted inside `== null` or `!= null` comparisons so helpers such as `genes.ts.Undefinable<T>.orNull()` generate `(value ?? null) != null` instead of TypeScript parsing `value ?? null != null` as `value ?? (null != null)`.
- Nullable branch local cast elision: `63d3a42575b222981cc6d1b028e597501d53ff17` (`fix(ts): preserve narrowed locals from nullable branches`), carrying non-null flow facts from a narrowed initializer to an immediately consumed local so nullable switch/branch pattern variables emit direct TypeScript assignments instead of identity `Register.unsafeCast<T>(value)` calls.
- Typed catch temp lowering: `e0a30ce6dbc519babf5236931b7e20faad86e6a0` (`fix: type lowered catch temps without any`), detecting Haxe's lowered `Exception.caught(raw).unwrap()` catch temp and emitting `{ } | null | undefined` in user modules so TypeScript `instanceof` / `typeof` guards narrow without a broad generated `any`.
- Map facade non-inlining: `57fa1e6ad6419423d905a6825fc2c91d3a37b6b6` (`ts: keep map facade calls in user output`), keeping `genes.util.EsMap` facade methods and Haxe map `copy()` helpers non-inline so generated user modules call stable map APIs instead of exposing the backing native `Map` field.
- Exiting null-guard flow: `0897b1a7af382ea5dcb887648eeaf0c99ce396d9` (`ts: preserve exiting null guard flow`), carrying non-null facts after exiting `if (value == null)` branches such as `continue`, `break`, `return`, and `throw`, while resetting those facts inside function expressions so captured mutable locals still emit conservative receiver assertions.
- Map presence/key-iteration narrowing: `c4cf03c7cb614cefe4b1bab169ca44a67a19c828` (`ts: narrow map gets from presence facts`), carrying stable `Map.exists(key)` and `Map.keys()` iteration facts into following `Map.get(key)` reads for maps with non-null value types, replacing broad generated `Register.unsafeCast` calls with direct reads or precise non-null TypeScript assertions where strict TS requires them.
- Object-construction temp naming: `84952a73b9978fa3d47ce213d992a6b2e65ec3d8` (`ts: name object construction temps`), giving Haxe-lowered same-prefix object-construction temporaries field-based names while preserving separate declarations and evaluation order, so provider-shaped generated TS uses names such as `family`, `status`, `capabilities`, `url`, and `npm` instead of `parsedN`/`baseN`.
- Callback null and bind output polish: `0ffe38943b9ed51225167b19a4c38b06fd5a30b1` (`ts: polish callback null and bind output`), emitting non-nullable locals intentionally initialized with `null` as `null!` instead of `Register.unsafeCast<T>(null)` and unwrapping no-op cast/meta receivers so method closures over stable locals emit `Register.bind(server, server.method)` instead of an IIFE wrapper. The generic fixture is `tests/genes-ts/snapshot/basic/src/foo/ServerCallbacks.hx`.
- TSX child temp naming: `9c129acf60db6bfef0dae2699d32f8b5e146b6fe` (`ts: name lowered TSX child locals`), recognizing Haxe-lowered TSX child-element temporaries in TSX mode and preferring tag-based local names such as `text`, `input`, `span`, and `strong` while preserving separate declarations and evaluation order. The generic fixture is `tests/genes-ts/snapshot/react/src/Main.hx`.

## Current Gate Evidence

- `../genes`: full local CI passed on 2026-06-23 at `9c129acf60db6bfef0dae2699d32f8b5e146b6fe`: `yarn test:ci`. Focused gates also passed: `yarn test:genes-ts:tsx`, `UPDATE_SNAPSHOTS=1 yarn test:genes-ts:snapshots`, `yarn test:genes-ts:snapshots`, `yarn test:genes-ts`, `yarn test:genes-ts:full`, `yarn test`, and `yarn test:acceptance`. OpenCodeHX downstream gates `npm run tui:scaffold` and `npm run build` passed against this compiler checkout.
- Previous full `../genes` and remote gates passed on 2026-06-23 at `84952a73b9978fa3d47ce213d992a6b2e65ec3d8`: local `yarn test:ci`; remote `genes-ts CI`, `CodeQL`, and `Release`.

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
