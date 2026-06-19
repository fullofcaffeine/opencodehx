# TUI Scaffold

`opencodehx-031` starts the TUI port with the smallest useful OpenTUI/Solid path: Haxe-authored TSX compiled by `genes-ts`, checked by TypeScript, compared against a generated TSX snapshot, and executed through OpenTUI's test renderer.

Run it with:

```bash
npm run tui:scaffold
```

The harness rebuilds `src-gen/tui`, type-checks with `tsconfig.tui.json`, compares `src-gen/tui/opencodehx/tui/TuiScaffold.tsx` with `reference/tui-scaffold.TuiScaffold.tsx`, then runs the generated TSX with the repo-pinned Bun binary and `scripts/harness/opentui-solid-preload.mjs`.

The scaffold also exercises a small typed TUI foundation: route state, theme state, host keybind parsing/printing, and leader-key dispatch. The Haxe source uses genes-ts default inline markup (`<box>...</box>`) rather than string-based JSX escapes, keeping Haxe expression splices typed while still emitting ordinary TSX.

Dependency pins:

- `@opentui/core@0.1.99`
- `@opentui/solid@0.1.99`
- `solid-js@1.9.11`
- `bun@1.3.14` as a local dev dependency

Upstream OpenCode's root catalog currently pins `solid-js` at `1.9.10`, but `@opentui/solid@0.1.99` declares a peer dependency on `solid-js@1.9.11`. OpenCodeHX uses the peer-compatible version here instead of relying on npm peer override behavior.

Runtime notes:

- Node 20 cannot execute OpenTUI core directly because `@opentui/core` imports `bun:ffi`.
- `@opentui/solid@0.1.99` documents Bun preload/build usage, so the harness uses local `node_modules/.bin/bun` rather than Node or a global Bun.
- OpenTUI's stock preload currently uses Babel's TypeScript transform without `allowDeclareFields`, while `genes-ts` emits `declare` class fields in generated support modules. The local preload mirrors the OpenTUI transform and enables that option explicitly.

This is not the final terminal worker path. It is a confidence gate for TSX, OpenTUI intrinsic elements, keyboard input, and readable generated TypeScript before the full TUI worker/terminal lifecycle lands.
