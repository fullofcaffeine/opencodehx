# Compiler Output Profiles

**Bead:** `opencodehx-brn`

OpenCodeHX uses `genes-ts` TypeScript output as its default and product-facing generated artifact.

## Default: Strict TypeScript

The default OpenCodeHX build compiles Haxe through `../genes` with `-D genes.ts`, then strict-checks the generated TypeScript with `tsc`.

This remains the primary, package-facing port surface because:

- generated TypeScript is reviewable parity evidence against upstream OpenCode;
- public declarations are part of the package contract;
- compiler quality work should improve readable TS instead of bypassing it;
- generated package and install smoke evidence is built around NodeNext TypeScript output.

The current default gates remain:

```sh
npm run build
npm run package:smoke
```

## Secondary: Classic ESM

Classic Genes ESM is a supported secondary application profile, not a replacement for the default TypeScript surface. The same `src/opencodehx` Haxe tree emits final modern JavaScript directly into `classic-dist/`; TypeScript-only annotations erase while the `genes.ts` boundary helpers retain their runtime behavior.

Run the paired profile with:

```sh
npm run test:classic-profile
```

That command builds classic ESM, stages the same resource catalog, runs a TypeScript Compiler API declaration audit with `skipLibCheck: false`, and executes the complete local smoke workflow. Every diagnostic owned by `classic-dist`, checked-in boundary declarations, or global/config space is blocking. Diagnostics physically owned by transitive npm packages are reported separately instead of being misclassified as OpenCodeHX/Genes failures. It is also part of `npm run ci:full` so helper degradation cannot silently regress.

The profile contract is:

- omit `-D genes.ts` for the ES6 profile;
- keep `-D genes.ts` as the default for OpenCodeHX;
- isolate final JavaScript and declarations under `classic-dist/`;
- preserve explicit ESM import attributes such as JSON loader contracts;
- keep generated declarations self-contained and internally valid under application DCE;
- use `../genes-vanilla` only as a read-only reference for regular Genes behavior;
- land any compiler work in `../genes`, generically and without OpenCodeHX knowledge;
- keep TS helper abstractions target-polymorphic so ES6 compatibility does not weaken TypeScript output.

This proves the current local runtime and project-owned declaration contract, not complete upstream OpenCode parity, byte-identical output, or the quality of arbitrary third-party declaration packages. The default TypeScript profile remains the primary full-application strict surface. The compiler-side same-source corpus and fullstack todoapp own broader Haxe-to-TS/classic differentials; OpenCodeHX remains a downstream real-world pressure test.
