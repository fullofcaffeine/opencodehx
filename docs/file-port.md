# File Primitive Port

**Bead:** `opencodehx-015`  
**Upstream oracle:** `../opencode/packages/opencode/src/file/ignore.ts`, `file/ripgrep.ts`, `file/index.ts`, `tool/glob.ts`, `tool/grep.ts`, and matching `../opencode/packages/opencode/test/file/*` / `test/tool/*` fixtures.

## Slice

This slice adds the first Node-first file primitives needed by tool work:

- `opencodehx.file.FileIgnore` ports OpenCode's default ignored folders/files, including upstream `node_modules` nested/non-nested matching, and supports extra/whitelist glob checks.
- `opencodehx.file.AppFileSystem` covers the upstream shared filesystem helper surface used by the app: directory/file predicates, JSON round trips, recursive writes, ancestor search, simple glob helpers, exists/remove passthrough, MIME lookup, containment, and overlap checks.
- `opencodehx.file.Ripgrep` wraps local `rg` with upstream-style `--no-config`, hidden-file, `.git` exclusion, glob, max-depth, JSON search, and partial-result semantics.
- `opencodehx.file.FileSystem` adds project-contained path resolution, upstream-shaped `read()` results for text, image-base64, and known binary files, raw text reads, directory listing with `.gitignore`/`.ignore` flags, and file/text search helpers.
- `opencodehx.file.FileWatcherRuntime` adds a narrow Node `fs.watch` seam for typed file-update events, covering deterministic root add/change/unlink publication, non-git roots, cleanup, `.git/index` suppression, and `.git/HEAD` publication for VCS branch refresh.
- `FileSmoke` builds a fixture workspace and covers AppFileSystem helper parity, ignore defaults, extra/whitelist rules, path containment and traversal rejection, `read()` text trimming, missing files, image base64 metadata, known binary empty content, list sorting/subdirectory paths, hidden handling, glob file search, and JSON grep parsing.

## Deferred Parity

This does not port the full OpenCode `File.Service`, cache/state machine, fuzzysort search, full watcher/fsmonitor integration, protected file rules, file patch/diff reads, ripgrep download/bootstrap, or Effect streaming. `file/path-traversal.test.ts` also includes `Instance.containsPath` worktree/monorepo cases; those remain owned by the project runtime seam rather than the file primitive. The first tool slices should use these primitives directly, then promote repeated needs into a richer service facade.

## Runtime Seam

`Ripgrep` currently shells out to `rg` found on `PATH`, which is suitable for the local development and smoke gate. Upstream can download a pinned ripgrep binary; OpenCodeHX should add that bootstrap only when packaging/runtime tasks need it.

`FileWatcherRuntime` currently uses Node's built-in `fs.watch` behind an injectable backend. Normal smoke uses the injected backend for deterministic service and VCS evidence; `npm run file:watcher:smoke` runs the real backend against a temporary git repository and stays out of normal CI because native watcher timing varies by platform.
