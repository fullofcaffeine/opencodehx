# Project Runtime Parity

**Beads:** `opencodehx-who`, expanded by `opencodehx-hic` and `opencodehx-99y`

This slice adds Haxe-owned runtime evidence for upstream project, git, VCS, worktree, npm, installation-adjacent, and sync tests. The executable fixture is `src/opencodehx/smoke/ProjectRuntimeSmoke.hx`, which runs as part of `npm run smoke`.

## Covered

- Git discovery and command facade:
  - default OpenCode-style git arguments,
  - current branch,
  - default branch,
  - NUL-safe status parsing,
  - diff parsing,
  - stat parsing.
- VCS runtime:
  - branch refresh,
  - typed branch-update events,
  - typed bus propagation for `vcs.branch.updated`,
  - HEAD `file.updated` events refresh the cached branch,
  - working-tree diff mode for tracked and untracked changes,
  - branch diff mode against the default branch merge base.
- Project discovery:
  - no-commit git repositories remain the global project and do not write `.git/opencode`,
  - non-git directories can be promoted with `initGit`,
  - committed repositories derive a stable project ID from the root commit,
  - cloned repositories preserve the cached project ID,
  - bare-repository worktrees cache the project ID in the common git directory,
  - project metadata updates preserve stable fields,
  - project update events carry the updated project payload,
  - initialization timestamps are recorded,
  - favicon discovery emits data URLs for known image extensions and ignores non-image favicon names,
  - missing sandbox directories are pruned from project state,
  - storage-backed global sessions are migrated to the real project ID when a committed project is discovered,
  - empty-directory and unrelated global sessions remain under the global project,
  - host paths are canonicalized through real filesystem paths when they exist.
- Worktrees:
  - friendly names are slugged into stable branch/directory names,
  - repeated names avoid existing directories and branch names,
  - created worktrees share the parent project ID,
  - sandbox paths are tracked,
  - instance bootstrap runs before `worktree.ready` and successful contexts are cached,
  - bootstrap refusal emits `worktree.failed` without caching an instance,
  - instance disposal emits `server.instance.disposed`,
  - ready and failed events are emitted,
  - configured project start commands and explicit start commands run in the created worktree,
  - reset hard-resets to the default branch, cleans untracked files, and verifies a clean status,
  - removal handles missing directories, deletes the worktree branch, and untracks the sandbox.
- NPM/install-adjacent behavior:
  - package spec sanitizing matches the upstream Windows-safe path rule while staying a no-op on POSIX.
  - package cache paths are derived from sanitized package specs,
  - package `add` uses an existing cache when present and otherwise delegates to an Arborist-shaped reify seam,
  - package `install` skips non-writable directories, reifies missing `node_modules`, and reifies dirty package-lock roots,
  - package `which` covers bin selection, scoped package bin names, stale cache lock removal, and absent-cache installation,
  - package `outdated` covers registry failure, exact-version comparison, and semver range satisfaction,
  - installation method detection follows upstream manager priority and installed-name checks,
  - latest-version lookup covers GitHub releases, npm registry, bun/pnpm registry behavior, Homebrew core/tap, Scoop, and Chocolatey response shapes,
  - upgrade command planning covers curl, npm, pnpm, bun, Homebrew tap refresh/upgrade, Scoop, and Chocolatey elevated-shell failure messaging,
  - uninstall package-manager command planning covers npm, pnpm, bun, yarn, Homebrew, Chocolatey, Scoop, and the curl no-op package-manager case.
- Sync:
  - typed event sequencing,
  - custom aggregate fields,
  - aggregate history,
  - history after a caller's last-known aggregate sequence,
  - typed persistence hooks,
  - restart-style reload from persisted rows,
  - aggregate event removal from the in-memory store and persistence hook,
  - run publish defaults,
  - replay publish opt-in,
  - replay,
  - unknown event type errors,
  - sequence-gap errors,
  - guarded `/sync/start`, `/sync/replay`, and `/sync/history` server routes.

## Deferred

- Full installation side effects against real package managers.
- Full project service behavior: integration with config/service layers and any future automatic start-command inference beyond the stored `commands.start` field.
- Native VCS file watching bindings beyond typed HEAD-event bus refresh.
- Full upstream worktree bootstrap service graph and upstream's broader failure matrix.
- Full SyncEvent service graph: definition reset/init/freeze, projector registration and diagnostics, SQLite EventSequence/EventTable-backed persistence, old-version run rejection, ProjectBus/GlobalBus payload conversion, payload schema registry output, and live cross-process workspace sync.

## Boundary Notes

`opencodehx.host.node.NodeProcess` keeps raw Node `spawnSync` overload complexity at the host seam. App-facing callers receive typed stdout/stderr/status through the narrow `SpawnSyncResult` extern instead of broad `Dynamic`.

`ProjectRuntime` stores canonical realpaths when the path exists. This avoids macOS `/var` versus `/private/var` drift and gives project/worktree comparisons one stable host spelling.

When a `SessionStore` is supplied, `ProjectRuntime.fromDirectory` persists the discovered project and migrates legacy sessions from `global` only when their stored directory exactly matches the real project worktree. This matches upstream's project migration rule without making the default in-memory discovery path depend on SQLite.
