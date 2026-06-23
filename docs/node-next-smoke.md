# genes-ts NodeNext Smoke

**Bead:** `opencodehx-005`  
**Recorded:** 2026-06-18T03:26:00Z

## Scaffold

The first executable scaffold is intentionally small:

- Haxe entry: `src/opencodehx/Main.hx`
- Haxe support module: `src/opencodehx/BuildInfo.hx`
- Haxe compile profile: `hxml/opencodehx.node.genes-ts.hxml`
- Generated TypeScript: `src-gen/`
- TypeScript output: `dist/`
- TypeScript config: `tsconfig.json`

The Haxe library shim in `haxe_libraries/genes-ts.hxml` points at the sibling `../genes` checkout recorded in `reference/genes.pin.json`.

## Gate

Command:

```sh
npm run build && npm run smoke
```

Observed result:

```text
opencodehx 0.0.0 opencodehx/smoke
```

This proves:

- Haxe 4.3.7 can compile the scaffold through `genes-ts`.
- `src-gen/**/*.ts` is emitted.
- `tsc -p tsconfig.json` passes under NodeNext.
- `node --enable-source-maps dist/index.js` runs the generated output.
- Generated import specifiers use explicit `.js` suffixes, for example `./opencodehx/Main.js` and `./BuildInfo.js`.
- The first Node built-in extern imports `node:path` and runs through the host facade.
- The first Effect facade imports `effect` and constructs a `Task.succeed(...)` value.
- The import/resource fixture imports `#opencodehx/smoke-resource` with `with { type: "json" }`, copies resources from `fixtures/resources` into `src-gen/resources` and `dist/resources`, and executes it through Node's package `imports` map.
- Text, file-path, and WASM-named assets are resolved through `opencodehx.resource.Resources` instead of relying on a Node loader for arbitrary `.txt`, `.wav`, or `.wasm` imports. Generic `genes.ts.Imports.text`, `file`, `dynamicWith`, and `dynamicWasm` helpers exist for hosts with a loader/bundler contract, but this smoke intentionally proves the plain-Node fallback.
- The dynamic import fixture emits and executes a `genes.Genes.dynamicImport(...)` import of `opencodehx.fixtures.DynamicFixture`.
- The utility smoke runs Haxe ports of `formatDuration`, `lazy`, and `decodeDataUrl`, including a Node `Buffer` facade for base64 data URLs.
- `npm run build` starts by cleaning `src-gen` and `dist`, preventing stale generated TypeScript from failed experiments from entering `tsc`.

## Notes

`package.json` must set `"type": "module"` for TypeScript NodeNext to treat generated `.ts` files as ESM while `verbatimModuleSyntax` is enabled.
