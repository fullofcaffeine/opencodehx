# ts2hx OpenCode Audit

**Bead:** `opencodehx-006`  
**Source:** `../opencode/packages/opencode/src`  
**Machine report:** `reference/ts2hx-opencode-audit.json`

## Summary

The direct ts2hx project probe currently fails before emit because upstream OpenCode extends Bun's shared config:

```text
File '@tsconfig/bun/tsconfig.json' not found.
```

That is not a port blocker, but it means broad ts2hx conversion should start from a synthetic audit tsconfig or a curated source subset rather than the upstream package tsconfig verbatim.

The AST audit scanned 446 `.ts`/`.tsx` files. It confirms that ts2hx can be useful for mechanical inventory and simple module skeletons, but OpenCodeHX should not expect a full automatic TS to Haxe conversion. The Haxe port should use upstream TS as an oracle, then hand-model core DTOs, protocol states, config, and host seams in Haxe-native forms.

## Import Surface

| Import kind | Count | Notes |
| --- | ---: | --- |
| relative imports | 1152 | Mostly portable module structure; useful for dependency-order planning. |
| npm imports | 1056 | Requires extern/facade policy, especially Effect, Zod, AI SDK, Hono, OpenTUI, drizzle, MCP/ACP. |
| `@/*` aliases | 838 | Needs alias policy; prefer Haxe package paths in source and package/import mapping only at generated TS boundaries. |
| `@tui/*` aliases | 163 | TUI-specific alias surface; defer until TSX/HXX fixture path is ready. |
| `#*` package aliases | 3 | Mirrors the package-import style proven by `#opencodehx/smoke-resource`. |
| Node built-ins | 27 | Route through host facades. |
| type-only imports | 228 | Often map to typedefs/externs; useful mechanical signal. |
| dynamic imports | 59 | `genes.Genes.dynamicImport` now avoids generated `module: any` via `../genes` commit `899e7732b15a1ff0d46cb53e9169faf9a8e3ca3c`; future work should focus on port coverage and runtime semantics. |
| dynamic import attributes | 4 | Mostly config and tree-sitter WASM; covered by follow-up `opencodehx-6pq`. |
| import attributes | 37 | JSON theme and WAV file assets; JSON is proven, file assets remain follow-up work. |

## Syntax Surface

| Feature | Count | Recommendation |
| --- | ---: | --- |
| TSX files | 77 | Do not mass-convert. Build TSX/HXX compiler fixtures first, then port TUI components deliberately. |
| JSX nodes | 1099 | Same as TSX; OpenTUI/Solid semantics matter more than syntax conversion. |
| type aliases | 518 | Good candidates for Haxe typedefs, enums, enum abstracts, and generated schemas. |
| interfaces | 148 | Good candidates for typedef records or extern interfaces at boundaries. |
| classes | 153 | Convert selectively; many upstream classes are Effect services or extern-adjacent wrappers. |
| `as` casts | 520 | Audit manually; many are boundary debt or schema narrowing. |
| optional chaining | 1070 | Mechanical in simple expressions, but should become null-safe Haxe modeling in core code. |
| nullish coalescing | 907 | Mechanical in simple expressions. |
| spread | 783 | Object spread needs care around record updates and optional fields. |
| `satisfies` | 60 | Manual/type-directed Haxe modeling; often schema/config/provider registry surfaces. |
| conditional/mapped/template literal types | 34 total | Prefer externs, generated facades, or simpler Haxe types. Do not blindly lower. |

## Unsupported Or Manual Areas

- `tsx-jsx-requires-hxx-or-tsx-compiler-fixtures`: 1099 JSX nodes across TUI files.
- `satisfies-needs-type-directed-haxe-modeling`: 60 sites, often registries and typed constants.
- `advanced-type-level-ts-manual-or-extern`: 34 sites covering conditional, mapped, and template literal types.
- `resource-txt-needs-copy-or-loader`: 34 prompt/description imports. OpenCodeHX now has a Node runtime adapter for copied text resources; direct import syntax remains manual.
- `resource-wav-needs-copy-or-loader`: 4 TUI sound imports. OpenCodeHX now has a Node runtime adapter for copied file-path resources; direct `type:file` import syntax remains manual.

## Conversion Guidance

Use ts2hx for:

- source inventory and feature counts,
- first-pass module dependency ordering,
- simple utility functions with low host coupling,
- spotting import alias and extern needs,
- creating tiny repros for `genes-ts` or ts2hx improvements.

Avoid ts2hx as the primary path for:

- config/schema semantics,
- session/message/tool protocol DTOs,
- provider stream events,
- Effect service/layer control flow,
- host seams,
- TSX/OpenTUI components,
- advanced type-level TypeScript.

For those areas, write Haxe source intentionally and use ts2hx output only as a comparison aid. Prefer Haxe enums, enum abstracts, abstracts/newtypes, typed records, and macros where they make illegal states harder to represent or generate deterministic schema/codec glue.

## Next Actions

1. Add a synthetic ts2hx audit tsconfig only if broad mechanical emission becomes useful.
2. Keep `opencodehx-6pq` for text/file/WASM resource loader work.
3. Use the closed `opencodehx-c0j` / `genes-h65` dynamic import fix as the baseline for future dynamic import ports.
4. Start config work from Haxe-native schema/config modeling, not a direct ts2hx conversion.
