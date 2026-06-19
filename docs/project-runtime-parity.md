# Project Runtime Parity

**Beads:** `opencodehx-who`, expanded by `opencodehx-hic`

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
  - typed branch-update events.
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
  - host paths are canonicalized through real filesystem paths when they exist.
- Worktrees:
  - friendly names are slugged into stable branch/directory names,
  - repeated names avoid existing directories and branch names,
  - created worktrees share the parent project ID,
  - sandbox paths are tracked,
  - ready and failed events are emitted,
  - configured project start commands and explicit start commands run in the created worktree,
  - reset hard-resets to the default branch, cleans untracked files, and verifies a clean status,
  - removal handles missing directories, deletes the worktree branch, and untracks the sandbox.
- NPM/install-adjacent behavior:
  - package spec sanitizing matches the upstream Windows-safe path rule while staying a no-op on POSIX.
- Sync:
  - typed event sequencing,
  - aggregate history,
  - replay,
  - unknown event type errors,
  - sequence-gap errors.

## Deferred

- Full installation side effects: package-manager detection, install/uninstall/outdated flows, and dependency bootstrap command behavior.
- Full project service behavior: automatic start-command discovery, persisted project store migration, and integration with config/service layers.
- Native VCS file watching and service-bus integration beyond explicit branch refresh.
- Worktree bootstrap/instance integration and upstream's broader failure matrix.
- Sync persistence, bus wiring, server routes, and cross-process behavior.

## Boundary Notes

`opencodehx.host.node.NodeProcess` keeps raw Node `spawnSync` overload complexity at the host seam. App-facing callers receive typed stdout/stderr/status through the narrow `SpawnSyncResult` extern instead of broad `Dynamic`.

`ProjectRuntime` stores canonical realpaths when the path exists. This avoids macOS `/var` versus `/private/var` drift and gives project/worktree comparisons one stable host spelling.
