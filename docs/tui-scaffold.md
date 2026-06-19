# TUI Scaffold

`opencodehx-031` starts the TUI port with the smallest useful OpenTUI/Solid path: Haxe-authored TSX compiled by `genes-ts`, checked by TypeScript, and compared against a generated TSX snapshot using OpenTUI's test-renderer contract.

Run it with:

```bash
npm run tui:scaffold
```

The harness rebuilds `src-gen/tui`, type-checks with `tsconfig.tui.json`, and compares `src-gen/tui/opencodehx/tui/TuiScaffold.tsx` with `reference/tui-scaffold.TuiScaffold.tsx`.

Dependency pins:

- `@opentui/core@0.1.99`
- `@opentui/solid@0.1.99`
- `solid-js@1.9.11`

Upstream OpenCode's root catalog currently pins `solid-js` at `1.9.10`, but `@opentui/solid@0.1.99` declares a peer dependency on `solid-js@1.9.11`. OpenCodeHX uses the peer-compatible version here instead of relying on npm peer override behavior.

Runtime status:

- Node 20 cannot execute OpenTUI core directly because `@opentui/core` imports `bun:ffi`.
- `@opentui/solid@0.1.99` documents Bun preload/build usage and exposes `./jsx-runtime` as a types-only subpath.
- The local Bun 1.0.11 runtime rejects OpenTUI's current import attribute form (`type: "file"`), so the live render/key-input smoke is tracked separately by `opencodehx-nc7`.

This is not the final terminal worker path. It is currently a compiler confidence gate for TSX, OpenTUI intrinsic elements, and readable generated TypeScript. The runtime gate must be enabled once the supported OpenTUI/Solid Bun path is available locally and in CI.
