# Utility Port Notes

**Bead:** `opencodehx-012`

## Ported Utilities

| Haxe module | Upstream oracle | Evidence |
| --- | --- | --- |
| `opencodehx.util.Format` | `src/util/format.ts`, `test/util/format.test.ts` | `UtilSmoke.formatDuration()` covers upstream duration boundaries. |
| `opencodehx.util.Lazy` | `src/util/lazy.ts`, `test/util/lazy.test.ts` | `UtilSmoke.lazy()` covers single evaluation, cached value, and reset behavior. |
| `opencodehx.util.Iife` | `src/util/iife.ts`, `test/util/iife.test.ts` | `UtilSmoke.iife()` covers immediate invocation, returned value passthrough, Promise passthrough for async functions, and void-return callbacks. |
| `opencodehx.util.DataUrl` | `src/util/data-url.ts`, `test/util/data-url.test.ts` | `UtilSmoke.dataUrl()` covers base64, percent-decoding, missing comma, and `decodeURIComponent` plus-sign parity. |
| `opencodehx.util.ErrorTools` | `src/util/error.ts`, `test/util/error.test.ts` | `UtilSmoke.errorTools()` covers native errors, record-like errors, opaque throwables, and `errorData` shape against `fixtures/resources/errors/diagnostics.golden.json`. |
| `opencodehx.util.Wildcard` | `src/util/wildcard.ts`, `test/util/wildcard.test.ts` | `UtilSmoke.wildcard()` covers `*`/`?` glob tokens, regex escaping, trailing command ` *`, slash normalization, platform case sensitivity, most-specific rule selection, and structured command sequence matching. |
| `opencodehx.util.Which` | `src/util/which.ts`, `test/util/which.test.ts` | `UtilSmoke.which()` covers missing commands, PATH overrides, first PATH match, Unix executable-bit filtering, Windows PATHEXT, and Windows Path casing fallback. |
| `opencodehx.util.ModuleResolver` | `packages/shared/src/util/module.ts`, `test/util/module.test.ts` | `UtilSmoke.moduleResolver()` covers package subpath resolution, ancestor `node_modules`, per-root isolation, package `main`, and missing-package null behavior. |
| `opencodehx.util.LogRuntime` | `src/util/log.ts`, `test/util/log.test.ts` | `UtilSmoke.logCleanup()` covers `Log.init` retention parity: only basename timestamped logs matching `????-??-??T??????.log` are candidates, the oldest entries are deleted until the newest ten remain, non-matching files are ignored, `dev.log` is used in dev mode, and print mode skips file creation. |
| `opencodehx.util.Timeout` | `src/util/timeout.ts`, `test/util/timeout.test.ts` | `UtilSmoke.timeout()` covers fast Promise resolution before the timeout and rejection with the upstream timeout message after the deadline. |
| `opencodehx.util.Lock` | `src/util/lock.ts`, `test/util/lock.test.ts` | `UtilSmoke.lock()` covers writer exclusivity, blocked readers while a writer is held, writer-priority wakeup, and reader acquisition after the queued writer releases. |
| `opencodehx.host.node.NodeBuffer` | Node `Buffer` usage in upstream `decodeDataUrl` | Generated TS imports `node:buffer` only through the host facade. |
| `opencodehx.externs.web.UriCodec` | JavaScript global `decodeURIComponent` | Keeps percent-decoding behind a named typed boundary so utility code does not embed raw `js.Syntax.code`. |

## Notes

- `Lazy<T>` is modeled as a Haxe class with `get()` and `reset()` rather than a callable function with an attached `reset` property. This keeps Haxe source clearer while preserving the behavior OpenCode relies on.
- `Iife.iife` intentionally stays as a tiny generic callback helper. Async parity is Promise passthrough: the helper returns the callback's Promise unchanged, so normal JavaScript `await` behavior remains owned by the host runtime.
- `DataUrl.decode` intentionally uses JavaScript `decodeURIComponent` through `UriCodec` instead of Haxe `StringTools.urlDecode`, because upstream does not translate `+` into a space.
- Base64 decoding is routed through `opencodehx.host.node.NodeBuffer`. A first attempt using Haxe `haxe.crypto.Base64` pulled in generated stdlib `Bytes.ts` that did not strict-check cleanly; the Node facade matches upstream behavior and keeps the host seam explicit.
- `LogRuntime` intentionally ports the upstream test's init/cleanup contract without claiming the full logger surface yet. Logger creation, service-tag caching, log-level filtering, timers, write streams, and Effect logger bridging remain owned by later session/server/runtime slices.
- `Timeout.withTimeout` mirrors upstream's Promise/timer shape and uses the existing `WebTimers` facade for `setTimeout`/`clearTimeout`.
- `Lock` exposes a Haxe-native `dispose()` token while preserving upstream's runtime ordering semantics. A future TypeScript-facing facade can add `[Symbol.dispose]` if this utility becomes a public generated-TS API.
- `npm run build` now cleans `src-gen` and `dist` first so stale generated files cannot poison `tsc` after a failed experiment.
