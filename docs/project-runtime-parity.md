# Project Runtime Parity

**Beads:** `opencodehx-who`, expanded by `opencodehx-hic`, `opencodehx-99y`, `opencodehx-obx`, and `opencodehx-grp`

This slice adds Haxe-owned runtime evidence for upstream project, git, VCS, worktree, instance bootstrap, npm, installation-adjacent, and sync tests. The executable fixture is `src/opencodehx/smoke/ProjectRuntimeSmoke.hx`, which runs as part of `npm run smoke`.

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
  - `FileWatcherRuntime` subscribes to the git metadata directory and publishes typed HEAD events into the same bus,
  - `npm run file:watcher:smoke` exercises the real Node `fs.watch` backend against a temporary git repo outside normal CI,
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
  - reset rejects the primary workspace and missing worktree directories,
  - non-git projects reject worktree info/create/remove paths,
  - Windows directory keys normalize existing realpaths case-insensitively while POSIX keys preserve case,
  - removal handles missing directories, deletes the worktree branch, and untracks the sandbox,
  - removal tolerates a nonzero `git worktree remove` result after Git has already detached the worktree, then still removes the directory, branch, and sandbox entry, and
  - Windows fsmonitor cleanup is represented by a native conditional smoke branch that configures fsmonitor, verifies daemon support when available, then removes the worktree through the same runtime path.
- Instance bootstrap:
  - `InstanceRuntime` records an ordered service graph on each cached context,
  - `InstanceBootstrapRuntime.upstreamOrder` preserves upstream's config, plugin, LSP, share, format, file, file-watcher, VCS, and snapshot initialization order,
  - the typed command hook subscribes to `command.executed` and marks the project initialized only for the default `init` command,
  - disposing an instance tears down service hooks before emitting `server.instance.disposed`,
  - disposed command hooks unsubscribe and no longer mutate project timestamps, and
  - a service-start refusal cleans up already-started services and does not cache the failed context.
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
- Opt-in live package-manager harness:
  - `npm run live:package-managers` is a guarded no-op unless `OPENCODEHX_LIVE_PACKAGE_MANAGERS=1` is set,
  - npm uses a temporary global prefix/cache and exercises install, upgrade-by-reinstall, and uninstall,
  - pnpm and Bun use temporary project directories and isolated stores/caches for add, upgrade-by-add, and remove,
  - Homebrew uses dry-run install/upgrade/uninstall when available,
  - Chocolatey uses `--noop` install/upgrade/uninstall on Windows when available, and
  - Scoop is probed read-only and skips mutation until a repo-approved disposable or dry-run install/remove path exists.
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
  - definition reset/init/freeze behavior,
  - projector registration and missing-projector diagnostics,
  - old-version run rejection,
  - shared aggregate sequence tracking across multiple SyncEvent definitions,
  - SQLite `event_sequence`/`event` table writes, restart reload, and cascade removal,
  - typed ProjectBus-style payload conversion,
  - GlobalBus-style sync payload metadata, and
  - payload descriptor registry output,
  - guarded `/sync/replay` and `/sync/history` server routes,
  - `/sync/start` delegation into a deterministic workspace sync runtime,
  - in-process remote history pull for active workspace sessions, and
  - local session history replay into a workspace peer,
  - upstream-shaped SSE frame parsing with CRLF normalization, multiline JSON `data:` joins, and `id`/`retry` non-JSON fallback messages, and
  - deterministic workspace SSE sync payload replay into local sync state,
  - workspace sync fence checks and timeout diagnostics,
  - upstream-shaped reconnect backoff delay calculation with a two-minute cap, and
  - per-event remote replay failure diagnostics without tearing down the whole deterministic stream,
  - typed remote workspace HTTP route construction for `/global/event`, `/sync/history`, and `/sync/replay`,
  - remote history/replay request header preservation, JSON body construction, and abort-signal forwarding, and
  - remote history/replay HTTP failure diagnostics that include response status and body text,
  - chunked `ReadableStream<Uint8Array>` SSE parsing with incomplete trailing-frame suppression, and
  - deterministic workspace stream application with connected/disconnected status transitions, and
  - bounded remote loop sequencing across SSE connect, history sync, stream application, disconnect, and planned reconnect delay recording, and
  - daemon-style workspace sync task ownership for start dedupe, owned abort signals, injected/real timer scheduling, reconnect scheduling, and stop cleanup, and
  - workspace HTTP proxy URL rewriting, hop-by-hop/request-header cleanup, target header injection, response content-header cleanup, disconnected-workspace guard, and `x-opencode-sync` fence success/timeout behavior.

## Deferred

- Full installation side effects for package managers that cannot be constrained to a disposable sandbox or dry-run/noop mode.
- Full project service behavior: deeper integration with config/service layers and any future automatic start-command inference beyond the stored `commands.start` field.
- Broader watcher service behavior beyond git HEAD updates, including full root file watching, config ignore integration, protected paths, and upstream `@parcel/watcher` backend parity.
- Concrete share/snapshot service internals, live plugin imports/installs, and real LSP process service boot inside the instance graph; the current graph records upstream order and lifecycle hooks without claiming those unported service bodies.
- Native Windows fsmonitor daemon behavior remains host-conditional: the smoke branch runs only on Windows and exits early when the installed Git does not support a running fsmonitor daemon.
- Full workspace control-plane routing/service integration beyond the covered sync/proxy seams.

## Boundary Notes

`opencodehx.host.node.NodeProcess` keeps raw Node `spawnSync` overload complexity at the host seam. App-facing callers receive typed stdout/stderr/status through the narrow `SpawnSyncResult` extern instead of broad `Dynamic`.

`ProjectRuntime` stores canonical realpaths when the path exists. This avoids macOS `/var` versus `/private/var` drift and gives project/worktree comparisons one stable host spelling.

When a `SessionStore` is supplied, `ProjectRuntime.fromDirectory` persists the discovered project and migrates legacy sessions from `global` only when their stored directory exactly matches the real project worktree. This matches upstream's project migration rule without making the default in-memory discovery path depend on SQLite.

`FileWatcherRuntime` is intentionally narrow: it converts native Node `fs.watch` callbacks into typed `FileUpdatedEvent` records and filters git metadata notifications down to `.git/HEAD` for VCS branch refresh. The injected smoke backend keeps normal `npm run smoke` deterministic, while `npm run file:watcher:smoke` gives opt-in native watcher evidence on hosts where `fs.watch` is reliable.

`InstanceBootstrapRuntime` is intentionally a Haxe-owned service graph seam, not an Effect clone. It preserves upstream bootstrap order and command initialization semantics with typed service factories so already-ported services can attach concrete lifecycle handles incrementally.
