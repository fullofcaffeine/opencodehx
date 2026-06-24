# File Primitive Port

**Bead:** `opencodehx-015`  
**Upstream oracle:** `../opencode/packages/opencode/src/file/ignore.ts`, `file/ripgrep.ts`, `file/index.ts`, `tool/glob.ts`, `tool/grep.ts`, and matching `../opencode/packages/opencode/test/file/*` / `test/tool/*` fixtures.

## Slice

This slice adds the first Node-first file primitives needed by tool work:

- `opencodehx.file.FileIgnore` ports OpenCode's default ignored folders/files, including upstream `node_modules` nested/non-nested matching, and supports extra/whitelist glob checks.
- `opencodehx.file.AppFileSystem` covers the upstream shared filesystem helper surface used by the app: directory/file predicates, JSON round trips, recursive writes, ancestor search, simple glob helpers, exists/remove passthrough, MIME lookup, containment, and overlap checks.
- `opencodehx.file.Ripgrep` wraps local `rg` with upstream-style `--no-config`, hidden-file defaults, hidden-file exclusion, `.git` exclusion, glob/file filters, max-depth, missing-directory failure, JSON search metadata, and partial-result semantics.
- `opencodehx.file.FileSearchRuntime` adds the upstream `File.Service.search()` filename/directory discovery subset: empty-query files, directory results with trailing slash, hidden-directory ordering, search-before-init behavior, simple fuzzy path matching, limits, dot/hidden query preference, refresh after file changes, and root isolation.
- `opencodehx.file.FileSystem` adds project-contained path resolution, upstream-shaped `read()` results for text, image-base64, and known binary files, git-backed diff/patch metadata for changed text files, fsmonitor-disabled git reads/status checks, raw text reads, directory listing with `.gitignore`/`.ignore` flags, and file/text search helpers.
- `opencodehx.project.VcsRuntime` owns the current file status evidence for modified, added, deleted, mixed, clean, non-git, and binary working-tree changes.
- `opencodehx.file.FileWatcherRuntime` adds a narrow Node `fs.watch` seam for typed file-update events, covering deterministic root add/change/unlink publication, non-git roots, cleanup, `.git/index` suppression, and `.git/HEAD` publication for VCS branch refresh.
- `FileSmoke` builds a fixture workspace and covers AppFileSystem helper parity, ignore defaults, extra/whitelist rules, path containment and traversal rejection, `read()` text trimming, missing files, image base64 metadata, known binary empty content, read diff/patch metadata for modified and staged text files, git fsmonitor-disabled status/read behavior, list sorting/subdirectory paths, filename/directory search behavior, hidden handling, glob/file-target search, empty matches, missing ripgrep cwd failure, and JSON grep parsing.

## Deferred Parity

This does not port the full OpenCode `File.Service`, cache/state machine, exact fuzzysort ranking, full watcher integration, protected file rules, exact `diff` package patch formatting, ripgrep download/bootstrap, ripgrep worker-mode split, or Effect streaming. Native Windows fsmonitor daemon assertions are conditional because non-Windows Git builds do not expose the same daemon lifecycle. `file/path-traversal.test.ts` also includes `Instance.containsPath` worktree/monorepo cases; those remain owned by the project runtime seam rather than the file primitive. The first tool slices should use these primitives directly, then promote repeated needs into a richer service facade.

## Runtime Seam

`Ripgrep` currently shells out to `rg` found on `PATH`, which is suitable for the local development and smoke gate. Upstream can download a pinned ripgrep binary; OpenCodeHX should add that bootstrap only when packaging/runtime tasks need it.

`FileWatcherRuntime` currently uses Node's built-in `fs.watch` behind an injectable backend. Normal smoke uses the injected backend for deterministic service and VCS evidence; `npm run file:watcher:smoke` runs the real backend against a temporary git repository and stays out of normal CI because native watcher timing varies by platform.
