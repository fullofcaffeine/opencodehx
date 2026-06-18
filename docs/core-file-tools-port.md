# Core File Tools Port

**Bead:** `opencodehx-017`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/{read,write,edit,apply_patch,glob,grep}.ts` and `../opencode/packages/opencode/src/patch/index.ts`

## Slice

This slice extends the Haxe-owned tool registry with the first mutating filesystem tools:

- `read` for file previews, line offsets/limits, directory listings, project-boundary checks, missing-file suggestions, and binary-file rejection.
- `write` for file creation/replacement with parent directory creation, diff metadata, and edit permission requests.
- `edit` for exact replacement, `replaceAll`, empty-`oldString` file creation, line-ending preservation, duplicate-match rejection, and diff metadata.
- `apply_patch` for OpenAI-style patch envelopes with add, update, delete, move planning, project-boundary checks, permission aggregation, and summary output.
- Shared `ToolPermission`, `ToolPaths`, and `TextDiff` helpers so later session/tool lifecycle work has one narrow place to connect the real permission UX and richer diff rendering.

## Evidence

`ToolSmoke` now covers registry surface, unknown/disabled/invalid failures, read file and directory output, path escape rejection, read permission denial, glob/grep parity smoke cases, write creation, edit exact/replace-all/multiple-match failures, and apply_patch add/update/delete execution.

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Deliberate Boundaries

This is still a parity scaffold, not the final OpenCode tool runtime:

- LSP diagnostics, formatting hooks, file watcher/bus publication, snapshots, and Effect integration remain deferred to their owning beads.
- `edit` currently implements exact matching and `replaceAll`. Upstream's tolerant replacement ladder (`LineTrimmedReplacer`, `BlockAnchorReplacer`, whitespace/indent/escape/context fallbacks) should be ported as a dedicated follow-up with fixture coverage.
- `apply_patch` implements the OpenAI patch envelope and core chunk matching. Richer verification fixtures for heredoc parsing, moves, EOF chunks, unicode-normalized matching, and malformed patch errors should be expanded before depending on it for broad automated edits.

## genes-ts Notes

The patch implementation intentionally avoids `Array.map` and switch-expression summaries in the hottest generated function because current `genes-ts` can collide generated temporary names inside one scope. This is a compiler quality issue already tracked in `../genes`; keep Haxe source clear, but prefer simple loops in shared tool code until that temp hygiene improves.

Optional callbacks also need local binding before invocation (`final ask = ctx.ask`) so emitted TypeScript narrows cleanly under `strictNullChecks`.
