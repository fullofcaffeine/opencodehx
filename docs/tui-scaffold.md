# TUI Scaffold

`opencodehx-031` starts the TUI port with the smallest useful OpenTUI/Solid path: Haxe-authored TSX compiled by `genes-ts`, checked by TypeScript, compared against a generated TSX snapshot, and executed through OpenTUI's test renderer.

Run it with:

```bash
npm run tui:scaffold
```

The harness rebuilds `src-gen/tui`, type-checks with `tsconfig.tui.json`, compares `src-gen/tui/opencodehx/tui/TuiScaffold.tsx` with `reference/tui-scaffold.TuiScaffold.tsx`, then runs the generated TSX with the repo-pinned Bun binary and `scripts/harness/opentui-solid-preload.mjs`.

`npm run package:smoke` now builds the same scaffold before packing, includes `src-gen/tui/index.tsx` plus `bin/opencodehx-opentui-solid-preload.mjs` in the tarball, installs the package into a temporary global prefix, and runs the installed scaffold through the package-local pinned Bun binary. That is installed-package evidence for the scaffold path only; it is not a claim that the final live terminal UI is packaged.

The scaffold also exercises a small typed TUI foundation: route state, theme state, host keybind parsing/printing, leader-key dispatch, a fake-provider transcript with user, tool, assistant, and metadata rows, and typed replay fixtures for model/provider/session/permission dialogs. The Haxe source uses genes-ts default inline markup (`<box>...</box>`) rather than string-based JSX escapes, keeping Haxe expression splices typed while still emitting ordinary TSX.

Dialog replay is intentionally pure at this stage. `TuiDialogReplay` models upstream-shaped rows and decisions for model selection, provider auth selection, session selection, and permission allow/reject choices without broad `Dynamic` payloads. The fixture uses TUI-local abstract IDs so this TSX target does not drag provider/session internals into a pure UI replay. Live Solid state, SDK calls, prompt focus management, and terminal-sized scroll behavior remain later TUI worker work.

Built-in plugin routes now go through `TuiRoutes.plugin("...")`, a macro-checked constructor. That keeps the literal authoring style close to upstream while failing the Haxe compile if the route is not in the typed catalog.

Dependency pins:

- `@opentui/core@0.1.99`
- `@opentui/solid@0.1.99`
- `solid-js@1.9.11`
- `bun@1.3.14` as a runtime dependency while the beta package needs a package-local Bun binary for installed TUI scaffold evidence

Upstream OpenCode's root catalog currently pins `solid-js` at `1.9.10`, but `@opentui/solid@0.1.99` declares a peer dependency on `solid-js@1.9.11`. OpenCodeHX uses the peer-compatible version here instead of relying on npm peer override behavior.

Runtime notes:

- Node 20 cannot execute OpenTUI core directly because `@opentui/core` imports `bun:ffi`.
- `@opentui/solid@0.1.99` documents Bun preload/build usage, so the harness uses local `node_modules/.bin/bun` rather than Node or a global Bun.
- OpenTUI's stock preload currently uses Babel's TypeScript transform without `allowDeclareFields`, while `genes-ts` emits `declare` class fields in generated support modules. The local preload mirrors the OpenTUI transform and enables that option explicitly.

This is not the final terminal worker path. It is a confidence gate for TSX, OpenTUI intrinsic elements, keyboard input, and readable generated TypeScript before the full TUI worker/terminal lifecycle lands.
