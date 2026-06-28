# Utility Port Notes

**Bead:** `opencodehx-012`

## Ported Utilities

| Haxe module | Upstream oracle | Evidence |
| --- | --- | --- |
| `opencodehx.util.Format` | `src/util/format.ts`, `test/util/format.test.ts` | `UtilSmoke.formatDuration()` covers upstream duration boundaries. |
| `opencodehx.util.Lazy` | `src/util/lazy.ts`, `test/util/lazy.test.ts` | `UtilSmoke.lazy()` covers single evaluation, cached value, and reset behavior. |
| `opencodehx.util.Iife` | `src/util/iife.ts`, `test/util/iife.test.ts` | `UtilSmoke.iife()` covers immediate invocation, returned value passthrough, Promise passthrough for async functions, and void-return callbacks. |
| `opencodehx.util.DataUrl` | `src/util/data-url.ts`, `test/util/data-url.test.ts` | `UtilSmoke.dataUrl()` covers base64, percent-decoding, missing comma, and `decodeURIComponent` plus-sign parity. |
| `opencodehx.util.ErrorTools` | `src/util/error.ts`, `test/util/error.test.ts` | `UtilSmoke.errorTools()` covers every upstream `util/error.test.ts` assertion for native errors, record-like errors, opaque throwables, and `errorData` shape against `fixtures/resources/errors/diagnostics.golden.json`. |
| `opencodehx.util.Wildcard` | `src/util/wildcard.ts`, `test/util/wildcard.test.ts` | `UtilSmoke.wildcard()` covers `*`/`?` glob tokens, regex escaping, trailing command ` *`, slash normalization, platform case sensitivity, most-specific rule selection, and structured command sequence matching. |
| `opencodehx.util.GlobRuntime` | `packages/shared/src/util/glob.ts`, `test/util/glob.test.ts` | `UtilSmoke.glob()` covers `scan`, `scanSync`, and `match` behavior for file-only/default scanning, absolute paths, include-all directories, nested `**` patterns, no-match results, dotfiles, symlink-follow traversal when host symlinks are available, and brace expansion. |
| `opencodehx.util.Which` | `src/util/which.ts`, `test/util/which.test.ts` | `UtilSmoke.which()` covers missing commands, PATH overrides, first PATH match, Unix executable-bit filtering, Windows PATHEXT, and Windows Path casing fallback. |
| `opencodehx.util.ModuleResolver` | `packages/shared/src/util/module.ts`, `test/util/module.test.ts` | `UtilSmoke.moduleResolver()` covers package subpath resolution, ancestor `node_modules`, per-root isolation, package `main`, and missing-package null behavior. |
| `opencodehx.util.LogRuntime` | `src/util/log.ts`, `test/util/log.test.ts` | `UtilSmoke.logCleanup()` covers `Log.init` retention parity: only basename timestamped logs matching `????-??-??T??????.log` are candidates, the oldest entries are deleted until the newest ten remain, non-matching files are ignored, `dev.log` is used in dev mode, and print mode skips file creation. |
| `opencodehx.util.Timeout` | `src/util/timeout.ts`, `test/util/timeout.test.ts` | `UtilSmoke.timeout()` covers fast Promise resolution before the timeout and rejection with the upstream timeout message after the deadline. |
| `opencodehx.util.Abort` | `src/util/abort.ts`, `test/memory/abort-leak.test.ts` | `UtilSmoke.abort()` covers `abortAfter`, clearing a timeout before abort, and `abortAfterAny` composed-signal abort behavior. `npm run memory:abort:smoke` adds opt-in Bun heap-growth evidence for the webfetch path and bound-handler retention comparison. |
| `opencodehx.util.Lock` | `src/util/lock.ts`, `test/util/lock.test.ts` | `UtilSmoke.lock()` covers writer exclusivity, blocked readers while a writer is held, writer-priority wakeup, and reader acquisition after the queued writer releases. |
| `opencodehx.util.ProcessRuntime` | `src/util/process.ts`, `test/util/process.test.ts` | `UtilSmoke.process()` covers stdout/stderr capture, nothrow exit codes, `RunFailedError`, abort and SIGKILL timeout behavior, cwd/env options, Windows shell/cmd-script cases when on Windows, and missing-command rejection. |
| `opencodehx.host.node.NodeBuffer` | Node `Buffer` usage in upstream `decodeDataUrl` | Generated TS imports `node:buffer` only through the host facade. |
| `opencodehx.externs.web.UriCodec` | JavaScript global `decodeURIComponent` | Keeps percent-decoding behind a named typed boundary so utility code does not embed raw `js.Syntax.code`. |

## Notes

- `Lazy<T>` is modeled as a Haxe class with `get()` and `reset()` rather than a callable function with an attached `reset` property. This keeps Haxe source clearer while preserving the behavior OpenCode relies on.
- `Iife.iife` intentionally stays as a tiny generic callback helper. Async parity is Promise passthrough: the helper returns the callback's Promise unchanged, so normal JavaScript `await` behavior remains owned by the host runtime.
- `DataUrl.decode` intentionally uses JavaScript `decodeURIComponent` through `UriCodec` instead of Haxe `StringTools.urlDecode`, because upstream does not translate `+` into a space.
- `GlobRuntime` is a focused Haxe implementation for the shared OpenCode glob oracle. It is not a full replacement for npm `glob`; broaden it only with upstream fixtures or product call sites that prove the extra pattern surface is needed.
- Base64 decoding is routed through `opencodehx.host.node.NodeBuffer`. A first attempt using Haxe `haxe.crypto.Base64` pulled in generated stdlib `Bytes.ts` that did not strict-check cleanly; the Node facade matches upstream behavior and keeps the host seam explicit.
- `LogRuntime` intentionally ports the upstream test's init/cleanup contract without claiming the full logger surface yet. Logger creation, service-tag caching, log-level filtering, timers, write streams, and Effect logger bridging remain owned by later session/server/runtime slices.
- `Timeout.withTimeout` mirrors upstream's Promise/timer shape and uses the existing `WebTimers` facade for `setTimeout`/`clearTimeout`.
- `Abort.abortAfter` mirrors upstream's bound-controller abort timer shape. The default smoke proves abort and clear behavior; `scripts/harness/abort-leak-smoke.mjs` owns the upstream Bun GC heap-growth worker evidence as an opt-in host-sensitive gate so normal Node smoke remains deterministic.
- `Lock` exposes a Haxe-native `dispose()` token while preserving upstream's runtime ordering semantics. A future TypeScript-facing facade can add `[Symbol.dispose]` if this utility becomes a public generated-TS API.
- `ProcessRuntime` is a Node host seam with string stdout/stderr instead of exposing Node `Buffer` to Haxe callers. The smoke still covers the upstream behavioral contract, including platform-conditional Windows cases.
- `npm run build` now cleans `src-gen` and `dist` first so stale generated files cannot poison `tsc` after a failed experiment.
