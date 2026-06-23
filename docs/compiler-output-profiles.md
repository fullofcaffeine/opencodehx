# Compiler Output Profiles

**Bead:** `opencodehx-brn`

OpenCodeHX uses `genes-ts` TypeScript output as its default and product-facing generated artifact.

## Default: Strict TypeScript

The default OpenCodeHX build compiles Haxe through `../genes` with `-D genes.ts`, then strict-checks the generated TypeScript with `tsc`.

This is the only supported port surface today because:

- generated TypeScript is reviewable parity evidence against upstream OpenCode;
- public declarations are part of the package contract;
- compiler quality work should improve readable TS instead of bypassing it;
- current CI and package smoke evidence are built around NodeNext TypeScript output.

The current default gates remain:

```sh
npm run build
npm run package:smoke
```

## Secondary: Performance-Oriented ES6

Classic Genes ES6 output is a future secondary profile, not a replacement for the default TypeScript surface. It is useful only when runtime simplicity, compile latency, or a later packaging target matters more than reviewing generated TS.

The paired compiler task is `../genes` Bead `genes-cn4`. Its design direction is:

- omit `-D genes.ts` for the ES6 profile;
- keep `-D genes.ts` as the default for OpenCodeHX;
- use `../genes-vanilla` only as a read-only reference for regular Genes behavior;
- land any compiler work in `../genes`, generically and without OpenCodeHX knowledge;
- keep TS helper abstractions target-polymorphic so ES6 compatibility does not weaken TypeScript output.

OpenCodeHX should not add an ES6 build to the default CI gate until the compiler repo has a side-by-side fixture proving one Haxe source through both TS-default and ES6-profile output. When that lands, add a separate opt-in OpenCodeHX smoke such as `npm run build:es6-profile`; do not fold it into `npm run build` until parity evidence justifies it.
