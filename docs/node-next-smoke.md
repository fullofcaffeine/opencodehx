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
- The import/resource fixture imports `#opencodehx/smoke-resource` with `with { type: "json" }`, copies it from `fixtures/resources` into `src-gen/resources`, and executes it through Node's package `imports` map.
- The dynamic import fixture emits and executes a `genes.Genes.dynamicImport(...)` import of `opencodehx.fixtures.DynamicFixture`.

## Notes

`package.json` must set `"type": "module"` for TypeScript NodeNext to treat generated `.ts` files as ESM while `verbatimModuleSyntax` is enabled.
