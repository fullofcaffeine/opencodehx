# Core File Tools Port

**Bead:** `opencodehx-017`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/{read,write,edit,apply_patch,glob,grep}.ts` and `../opencode/packages/opencode/src/patch/index.ts`

## Slice

This slice extends the Haxe-owned tool registry with the first mutating filesystem tools:

- `read` for file previews, line offsets/limits, directory listings with pagination, out-of-range offset errors, external-directory permission requests, missing-file suggestions, and binary-file rejection.
- `write` for file creation/replacement with parent directory creation, overwrite metadata, UTF-8 BOM preservation, diff metadata, edit permission requests, and external-directory permission requests.
- `edit` for exact replacement, tolerant upstream-style fallback matching, `replaceAll`, empty-`oldString` file creation, line-ending and UTF-8 BOM preservation, duplicate-match rejection, diff metadata, and external-directory permission requests.
- `apply_patch` for OpenAI-style patch envelopes with add, update, delete, move planning, UTF-8 BOM preservation, EOF/context anchors, heredoc-wrapped patches, Unicode-normalized matching, project-boundary checks, permission aggregation, and summary output.
- Shared `ToolPermission`, `ToolPaths`, `ToolSearchPath`, `ToolExternalDirectory`, and `TextDiff` helpers so later session/tool lifecycle work has one narrow place to connect the real permission UX, typed search roots, external-directory prompts, and richer diff rendering.

## Evidence

`ToolSmoke` now covers registry surface, unknown/disabled/invalid failures, read file and directory output, directory offset/limit pagination, read offset out-of-range errors, read permission denial, read external-directory request and denial shape, read/bash truncation metadata, glob/grep parity smoke cases, glob/grep permission request and denial shape, glob/grep external-directory request and denial shape, write creation and overwrite metadata, write BOM preservation, write external-directory request and denial shape, edit exact/replace-all/multiple-match failures, tolerant edit fallbacks for line-trimmed, block-anchor, whitespace, indentation, and escape-normalized matches, edit BOM preservation for existing and incoming content, edit external-directory request and denial shape, plus permissioned apply_patch add/update/delete/move execution, BOM preservation, EOF anchors, heredoc parsing, Unicode-normalized matching, malformed headers, and no-side-effect verification failures.

`PatchSmoke` covers the standalone upstream `Patch` namespace through `opencodehx.patch.PatchRuntime`; see `patch-runtime.md` for parser, command-detection, direct apply, and verified-planning evidence.

Full upstream `Truncate` service behavior, including file-spill, cleanup, direction, byte/line defaults, and Task-tool hints, remains deferred.

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Deliberate Boundaries

This is still a parity scaffold, not the final OpenCode tool runtime:

- LSP diagnostics, formatting hooks, file watcher/bus publication, snapshots, and Effect integration remain deferred to their owning beads.
- `edit` now ports the upstream tolerant replacement ladder shape, but broad differential coverage against every upstream edit test remains future work once the Haxe-authored test facade grows beyond smoke fixtures.
- The standalone upstream `patch/index.ts` helper surface is now a public typed Haxe runtime in `opencodehx.patch.PatchRuntime`; the tool wrapper remains responsible for project-boundary checks, permission aggregation, and tool-shaped metadata.

## genes-ts Notes

The patch implementation intentionally avoids `Array.map` and switch-expression summaries in the hottest generated function because current `genes-ts` can collide generated temporary names inside one scope. This is a compiler quality issue already tracked in `../genes`; keep Haxe source clear, but prefer simple loops in shared tool code until that temp hygiene improves.

Optional callbacks also need local binding before invocation (`final ask = ctx.ask`) so emitted TypeScript narrows cleanly under `strictNullChecks`.
