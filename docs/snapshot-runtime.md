# Snapshot Runtime

**Bead:** `opencodehx-gruz`  
**Upstream oracle:** `../opencode/packages/opencode/src/snapshot/index.ts` and `../opencode/packages/opencode/test/snapshot/snapshot.test.ts`

## Slice

This slice replaces the placeholder snapshot ID helper with a focused Haxe runtime:

- `SnapshotRuntime.trackDirectory(directory)` records a typed process-local snapshot of Git-visible files and returns a deterministic SHA-1 content hash.
- `SnapshotRuntime.patch(directory, hash)` compares the current file state with a stored snapshot and returns absolute changed file paths.
- `SnapshotRuntime.revert(directory, patches)` restores modified/deleted files from the stored snapshot and removes files that were added after the snapshot.
- `SnapshotRuntime.diff(directory, hash)` returns a simple changed-file diff summary.
- `SnapshotRuntime.diffFull(directory, from, to)` returns typed file diff summaries for stored snapshots.
- `SnapshotRuntime.track(context)` keeps the server/instance entry point and verifies the snapshot service is attached.

`SnapshotSmoke` covers representative upstream behavior:

- Track, patch, diff, and revert across added, modified, and deleted files.
- Empty directories do not create patch entries.
- Invalid hashes return an empty patch without throwing.
- Empty revert patch lists are no-ops.
- Added files larger than the upstream 2 MiB limit are skipped and keep the snapshot hash stable.
- `.gitignore` and `git check-ignore --no-index` filtering exclude ignored files while keeping `.gitignore` itself and normal files.
- `diffFull` reports changed tracked files and excludes ignored files.

## Deliberate Boundaries

This is not the full upstream snapshot service yet. Upstream stores snapshots in a separate Git index and uses Effect services, scoped locks, cleanup, persistent snapshot directories, full restore semantics, worktree isolation, concurrent operation behavior, and structured patch parsing.

OpenCodeHX currently uses Git for candidate discovery and ignore semantics, then stores typed content snapshots in process memory. That is enough to prove the first user-visible file-state semantics without mutating a source repo index. Full persistent Git-dir parity, `restore`, rich `diffFull` patch metadata, worktree/concurrency cases, symlink/binary edge cases, and cleanup/prune behavior remain deferred.

The runtime intentionally does not add broad JSON, `Dynamic`, or raw TypeScript boundaries. If later snapshot work needs lower-level Git plumbing that `genes-ts` cannot express cleanly, reduce it into a generic compiler/runtime helper before weakening the product source.
