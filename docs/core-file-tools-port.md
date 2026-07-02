# Core File Tools Port

**Beads:** `opencodehx-017`, `opencodehx-nmox`, `opencodehx-6pcb`, `opencodehx-s0vk`, `opencodehx-uj41`
**Upstream oracle:** `../opencode/packages/opencode/src/tool/{read,write,edit,apply_patch,glob,grep}.ts` and `../opencode/packages/opencode/src/patch/index.ts`

## Slice

This slice extends the Haxe-owned tool registry with the first mutating filesystem tools:

- `read` for file previews, line offsets/limits, empty-file offsets, `.fbs` schema text handling, upstream-shaped truncation footers, long-line truncation suffixes, directory listings with pagination and symlinked-directory suffixes, image/PDF data-url attachments with content sniffing, nearby instruction reminders with per-message claim dedupe, out-of-range offset errors, external-directory permission requests, upstream-shaped missing-file suggestions, and null-byte/known-extension binary-file rejection.
- `write` for file creation/replacement with parent directory creation, overwrite metadata, JSON/binary-safe/empty/multiline/CRLF content preservation, relative title output, UTF-8 BOM preservation including formatter-strip restore, upstream-shaped file edit/watcher bus events, diff metadata, edit permission requests, and external-directory permission requests.
- `edit` for exact and multiline replacement, tolerant upstream-style fallback matching, `replaceAll`, empty-`oldString` file creation, CRLF/line-ending and UTF-8 BOM preservation including formatter-strip restore, upstream-shaped file edit/watcher bus events, identical-input and directory-path failures, duplicate-match rejection, diff metadata, and external-directory permission requests.
- `apply_patch` for OpenAI-style patch envelopes with add, update, delete, move planning, insert-only hunks, UTF-8 BOM preservation including formatter-strip restore, upstream-shaped file edit/watcher bus events for add/change/unlink, EOF/context anchors, heredoc-wrapped patches, whitespace/Unicode-normalized matching, external-directory permission requests, permission aggregation, and summary output.
- Shared `ToolPermission`, `ToolPaths`, `ToolSearchPath`, `ToolExternalDirectory`, and `TextDiff` helpers so later session/tool lifecycle work has one narrow place to connect the real permission UX, typed search roots, external-directory prompts, and richer diff rendering.

## Evidence

`ToolSmoke` now covers registry surface, unknown/disabled/invalid failures, standalone `Truncate` output/write/cleanup behavior, read file and directory output, empty-file success and offset failure, `.fbs` schema text output, byte-cap and line-count truncation footers, long-line truncation suffixes, symlinked-directory suffixes, nearby `AGENTS.md` reminder output plus `metadata.loaded`, same-message instruction reminder dedupe, different-message reload, clear-triggered reload, PDF attachment output with loaded-instruction metadata, content-sniffed JPEG attachment output, known binary extension rejection, directory offset/limit pagination, read offset out-of-range errors, read missing-file suggestions, read permission denial, read external-directory request and denial shape, read truncation metadata, bash byte/line truncation metadata plus saved full-output spill files, glob/grep parity smoke cases, glob/grep permission request and denial shape, glob/grep external-directory request and denial shape, write creation and overwrite metadata, write JSON/binary-safe/empty/multiline/CRLF content preservation, write relative title output, write BOM preservation including restore after a formatter strips it, write file.edited and file.watcher add/change publication, write external-directory request and denial shape, edit exact/multiline/replace-all/multiple-match behavior, identical-input and directory-path failures, edit filediff stats, tolerant edit fallbacks for line-trimmed, block-anchor, whitespace, indentation, and escape-normalized matches, edit BOM preservation for existing, incoming, and formatter-stripped content, edit file.edited and file.watcher add/change publication, edit external-directory request and denial shape, plus permissioned apply_patch add/update/delete/move execution, insert-only hunks, BOM preservation including formatter-stripped restore, apply_patch file.edited and file.watcher add/change/unlink publication, EOF anchors, context disambiguation, heredoc parsing with and without `cat`, whitespace and Unicode-normalized matching, external-directory hunk/move-target request and denial shape, malformed/delete-target failures, and no-side-effect verification failures.

`PatchSmoke` covers the standalone upstream `Patch` namespace through `opencodehx.patch.PatchRuntime`; see `patch-runtime.md` for parser, command-detection, direct apply, and verified-planning evidence.

`opencodehx.tool.Truncate` covers the standalone upstream truncation contract for unchanged content, default byte/line limits, head and tail previews, full-output spill files, retention cleanup, and Task-tool versus Grep/Read hints. `BashTool` now uses the same runtime to save full truncated byte/line output and report `metadata.outputPath`. Full Effect layer scheduling and wiring every tool caller through the shared service remain deferred.

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Deliberate Boundaries

This is still a parity scaffold, not the final OpenCode tool runtime:

- LSP diagnostics, full async `Format.Service` integration, snapshots, and Effect integration remain deferred to their owning beads.
- `edit` now ports the upstream tolerant replacement ladder shape, but broad differential coverage against every upstream edit test remains future work once the Haxe-authored test facade grows beyond smoke fixtures.
- The standalone upstream `patch/index.ts` helper surface is now a public typed Haxe runtime in `opencodehx.patch.PatchRuntime`; the tool wrapper remains responsible for project-boundary checks, permission aggregation, and tool-shaped metadata.

## genes-ts Notes

The patch implementation intentionally avoids `Array.map` and switch-expression summaries in the hottest generated function because current `genes-ts` can collide generated temporary names inside one scope. This is a compiler quality issue already tracked in `../genes`; keep Haxe source clear, but prefer simple loops in shared tool code until that temp hygiene improves.

Optional callbacks also need local binding before invocation (`final ask = ctx.ask`) so emitted TypeScript narrows cleanly under `strictNullChecks`.
