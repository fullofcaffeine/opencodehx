# Resource Imports

**Bead:** `opencodehx-6pq`

## Upstream Shapes

OpenCode uses three resource patterns that matter for early ports:

- Plain text imports for prompts and tool descriptions, such as `import PROMPT from "./prompt/default.txt"`.
- JSON imports with import attributes for TUI themes.
- File-path imports with `with { type: "file" }` for WAV assets and dynamic WASM imports for tree-sitter parsers.

`opencodehx-010` already proved JSON import attributes through `genes.ts.Imports.defaultImportWith(...)`. This slice adds the Node-first runtime plan for text, file, and WASM-style assets.

## OpenCodeHX Adapter

`opencodehx.resource.Resources` resolves assets copied from `fixtures/resources` into `dist/resources`:

- `Resources.text(path)` returns UTF-8 text.
- `Resources.file(path)` returns a filesystem path string, matching the useful runtime shape of Bun's `type: "file"` imports.
- `Resources.wasm(path)` returns the resolved path plus a small byte summary through the typed `NodeBuffer` facade. The build now copies `web-tree-sitter/tree-sitter.wasm`, `tree-sitter-bash.wasm`, and `tree-sitter-powershell.wasm` from npm packages so the bash permission scanner can load real parser assets under NodeNext.
- `Resources.worker(path)` returns a filesystem path for module-worker style assets. The current worker resources are parser/TUI packaging fixtures, not the final live terminal worker runtime.
- `Resources.manifest()` decodes the generated `manifest.json` into typed Haxe records. The manifest records resource path, kind, byte count, and SHA-256 for prompt text, JSON, file, WASM, and worker assets.

Paths are normalized and cannot be absolute or parent-directory escapes. The adapter is intentionally explicit because NodeNext does not natively load arbitrary `.txt`, `.wav`, or `.wasm` imports without a loader or bundler contract.

Haxe-owned resource reads use `ResourcePaths.known("...")` against the copied-resource catalog so prompt, worker, WAV, and WASM path typos fail at compile time. The generated manifest remains runtime-decoded JSON because it is build output, not source-authored Haxe.

The build script mirrors resources into both `src-gen/resources` for TypeScript-side package import metadata and `dist/resources` for runtime path reads after `tsc` emits JavaScript. `scripts/build/copy-resources.mjs` writes the same manifest into both trees after copying fixture resources and npm parser WASM files.

## Evidence

Run:

```bash
npm run build
npm run smoke
```

`ResourceSmoke` checks prompt text, JSON manifest classification, file-path resolution, copied WAV fixture existence, byte access for fixture and npm WASM assets, and parser/TUI worker file resolution. `ToolSmoke` exercises the real tree-sitter WASM assets through `BashCommandScanner.preload()`. `npm run package:smoke` packs and globally installs the package, then verifies the installed resource manifest and worker entries.

## Deferred

This is not yet a generic `genes-ts` resource import compiler feature. Follow-up `opencodehx-5lx` / `genes-cbr` tracks direct text/file/WASM import helpers. Preserve this adapter as the Node runtime fallback even if compiler syntax improves.

The current worker resources prove copy/package resolution only. Full parser-worker and TUI-worker behavior still needs the owning parser/TUI runtime slices to define worker entrypoints, lifecycle, messages, and bundling constraints.
