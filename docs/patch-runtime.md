# Patch Runtime

**Upstream oracle:** `../opencode/packages/opencode/src/patch/index.ts` and `../opencode/packages/opencode/test/patch/patch.test.ts`

## Slice

`opencodehx.patch.PatchRuntime` exposes the standalone upstream `Patch` namespace shape as typed Haxe source:

- `parsePatch` returns Haxe enum hunks for add, delete, and update/move operations.
- `maybeParseApplyPatch` detects direct `apply_patch`, `applypatch`, and `bash -lc` heredoc invocations.
- `applyPatch` applies parsed hunks to host files, including parent directory creation, add/update/delete/move, UTF-8 BOM preservation, empty files, files without trailing newlines, and multi-chunk updates.
- `maybeParseApplyPatchVerified` plans resolved file changes before execution and rejects implicit raw patch invocation.

## Evidence

`PatchSmoke` covers the upstream patch test buckets:

- parser behavior for simple adds, deletes, multiple hunks, moves, and invalid patch text;
- command detection for direct, alias, heredoc, and non-patch argv;
- filesystem apply behavior for add, delete, update, move, BOM-preserving updates, nested parent directories, empty files, no trailing newline, and multi-chunk updates;
- error paths for missing update/delete targets;
- verified planning for resolved change records and implicit invocation rejection.

The permissioned `apply_patch` tool still lives in `opencodehx.tool.ApplyPatchTool`. It keeps project-boundary checks, edit permission aggregation, no-side-effect verification before writes, and tool-shaped result metadata over the same patch format.

## Boundaries

This is a synchronous Node-host runtime slice. It does not yet claim upstream Effect service wiring, event publication, LSP diagnostics, formatting, or snapshot integration. Those remain owned by the broader side-effecting tool and runtime parity beads.
