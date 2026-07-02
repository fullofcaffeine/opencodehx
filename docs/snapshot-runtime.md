# Snapshot Runtime

**Beads:** `opencodehx-gruz`, `opencodehx-loib`, `opencodehx-tj90`, `opencodehx-l5rw`, `opencodehx-zrcz`, `opencodehx-otuy`, `opencodehx-ro54`, `opencodehx-z1yc`, `opencodehx-103u`, `opencodehx-iuru`, `opencodehx-h2vc`, `opencodehx-4e5p`, `opencodehx-dp26`, `opencodehx-wsjv`, `opencodehx-mwf5`, `opencodehx-4zx6`, `opencodehx-c7xj`, `opencodehx-mnse`, `opencodehx-1qmk`, `opencodehx-3cgk`, `opencodehx-0z0m`, `opencodehx-2uwe`, `opencodehx-fbe7`, `opencodehx-i11n`, `opencodehx-7s01`, `opencodehx-51y6`, `opencodehx-o8tp`, `opencodehx-ce6t`, `opencodehx-i4fy`, `opencodehx-a9tt`, `opencodehx-7fj3`, `opencodehx-b3tj`, `opencodehx-f5rq`, `opencodehx-5l53`, `opencodehx-ul8r`, `opencodehx-vbdl`, `opencodehx-e602`, `opencodehx-i8md`, `opencodehx-gelg`, `opencodehx-56a4`, `opencodehx-hpsx`, `opencodehx-9drl`
**Upstream oracle:** `../opencode/packages/opencode/src/snapshot/index.ts` and `../opencode/packages/opencode/test/snapshot/snapshot.test.ts`

## Slice

This slice replaces the placeholder snapshot ID helper with a focused Haxe runtime:

- `SnapshotRuntime.trackDirectory(directory)` records a typed process-local snapshot of Git-visible files and returns a deterministic SHA-1 content hash.
- `SnapshotRuntime.patch(directory, hash)` compares the current file state with a stored snapshot and returns absolute changed file paths.
- `SnapshotRuntime.revert(directory, patches)` restores modified/deleted files from the stored snapshot and removes files that were added after the snapshot.
- `SnapshotRuntime.restore(directory, hash)` restores files tracked in a stored snapshot while leaving files created after the snapshot in place.
- `SnapshotRuntime.diff(directory, hash)` returns a simple changed-file diff summary.
- `SnapshotRuntime.diffFull(directory, from, to)` returns typed file diff summaries for stored snapshots.
- `SnapshotRuntime.track(context)` keeps the server/instance entry point and verifies the snapshot service is attached.
- `SnapshotFileDiff` is a pure DTO module, separate from the Node-backed runtime, so session/server types can reference stored diff summaries without importing host seams.

`SnapshotSmoke` covers representative upstream behavior:

- Track, patch, diff, and revert across added, modified, and deleted files.
- Focused restore restores deleted/modified snapshot files, replaces file/directory path blockers, and preserves new files.
- Revert handles recreated files according to the snapshot: recreated deleted files are removed, while recreated existing files restore original content.
- Revert removes newly added files in nested directories.
- Revert removes added files while preserving now-empty parent directories.
- Revert preserves first-patch behavior for overlapping files across patch lists.
- Revert preserves ordered patch-list behavior when the same snapshot hash appears again and file/directory paths overlap.
- Large mixed revert patches restore many changed files and remove many fresh files in one patch list.
- Repeated no-change tracking returns the same snapshot hash.
- Empty directories do not create patch entries.
- Invalid hashes return an empty patch without throwing.
- Empty revert patch lists are no-ops.
- Revert ignores patch entries for files that do not exist in the snapshot or current worktree.
- Added files under the upstream 2 MiB limit are tracked.
- Added filenames with spaces, dashes, and underscores are detected.
- Added Unicode filenames, nested Unicode paths, and very long filenames are detected and removed on revert.
- Added hidden files are detected, including `.gitignore` and dot config files.
- Chmod-only permission changes on existing tracked files do not create patch entries.
- Added files larger than the upstream 2 MiB limit are skipped and keep the snapshot hash stable.
- Preexisting and newly added `.gitignore` rules exclude ignored files while keeping tracked and normal files.
- Patch output filters files that were snapshotted before a later `.gitignore` rule excluded them.
- `.git/info/exclude` rules filter ignored files from patch and `diffFull` output.
- A local `GIT_CONFIG_GLOBAL` `core.excludesFile` continues to filter global excludes alongside `.git/info/exclude`.
- Snapshot state stays isolated between separate project directories.
- Patch detects files added inside a secondary Git worktree.
- Revert in a secondary Git worktree removes only the invoking worktree's added file and preserves a same-named primary-checkout file.
- `diff` in a secondary Git worktree reports worktree-only/shared edits and ignores primary-only edits.
- `diffFull` reports changed tracked files and excludes ignored files.
- `diffFull` returns an empty list for unchanged snapshots.
- `diffFull` reports added, modified, deleted, and multi-line added text-file patch content with upstream-shaped addition/deletion counts.
- `diffFull` reports mixed added/deleted text-file entries in one result, including multiple added/deleted files and a large interleaved text/binary batch.
- `diffFull` reports whitespace-only text edits as modified entries with positive additions.
- `diffFull` preserves deterministic Git-style file order across a 140-file ordered batch.
- `diffFull` reports upstream-shaped `added`, `deleted`, and `modified` statuses, including grow-only and trim-only text churn counts.
- Binary `diffFull` entries preserve upstream's empty patch and zero text-churn shape.
- Binary revert removes newly added binary files and restores modified binary contents byte-for-byte.
- File and nested directory symlink patch detection are covered on hosts that permit symlink creation.
- Symlink revert restores existing symlinks, removes newly added symlinks, and replaces symlinks with original regular files without mutating the link target.
- Circular symlink patch scanning does not crash on hosts that permit symlink creation.

## Deliberate Boundaries

This is not the full upstream snapshot service yet. Upstream stores snapshots in a separate Git index and uses Effect services, scoped locks, cleanup, persistent snapshot directories, full restore semantics, worktree isolation, concurrent operation behavior, and structured patch parsing.

OpenCodeHX currently uses Git for candidate discovery and ignore semantics, then stores typed content snapshots in process memory. That is enough to prove the first user-visible file-state semantics without mutating a source repo index. Full persistent Git-dir parity, restore cleanup/removal semantics, richer text `diffFull` patch metadata, concurrency cases, broader symlink edge cases, and cleanup/prune behavior remain deferred.

The runtime intentionally does not add broad JSON, `Dynamic`, or raw TypeScript boundaries. If later snapshot work needs lower-level Git plumbing that `genes-ts` cannot express cleanly, reduce it into a generic compiler/runtime helper before weakening the product source.
