# Project Runtime Parity

**Bead:** `opencodehx-who`

This slice adds the first Haxe-owned runtime evidence for upstream project, git, worktree, npm, installation-adjacent, and sync tests. The executable fixture is `src/opencodehx/smoke/ProjectRuntimeSmoke.hx`, which runs as part of `npm run smoke`.

## Covered

- Git discovery and command facade:
  - default OpenCode-style git arguments,
  - current branch,
  - default branch,
  - NUL-safe status parsing,
  - diff parsing,
  - stat parsing.
- Project discovery:
  - no-commit git repositories remain the global project and do not write `.git/opencode`,
  - committed repositories derive a stable project ID from the root commit,
  - project metadata updates preserve stable fields,
  - initialization timestamps are recorded,
  - host paths are canonicalized through real filesystem paths when they exist.
- Worktrees:
  - friendly names are slugged into stable branch/directory names,
  - created worktrees share the parent project ID,
  - sandbox paths are tracked,
  - removal deletes the worktree branch and untracks the sandbox.
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
- Full project service behavior: icon discovery, start command discovery, persisted project store migration, and integration with config/service layers.
- VCS watcher/event bus integration and branch-change notifications.
- Worktree bootstrap/start/reset flows and upstream's broader failure matrix.
- Sync persistence, bus wiring, server routes, and cross-process behavior.

## Boundary Notes

`opencodehx.host.node.NodeProcess` keeps raw Node `spawnSync` overload complexity at the host seam. App-facing callers receive typed stdout/stderr/status through the narrow `SpawnSyncResult` extern instead of broad `Dynamic`.

`ProjectRuntime` stores canonical realpaths when the path exists. This avoids macOS `/var` versus `/private/var` drift and gives project/worktree comparisons one stable host spelling.

