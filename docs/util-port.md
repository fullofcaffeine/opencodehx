# Utility Port Notes

**Bead:** `opencodehx-012`

## Ported Utilities

| Haxe module | Upstream oracle | Evidence |
| --- | --- | --- |
| `opencodehx.util.Format` | `src/util/format.ts`, `test/util/format.test.ts` | `UtilSmoke.formatDuration()` covers upstream duration boundaries. |
| `opencodehx.util.Lazy` | `src/util/lazy.ts`, `test/util/lazy.test.ts` | `UtilSmoke.lazy()` covers single evaluation, cached value, and reset behavior. |
| `opencodehx.util.DataUrl` | `src/util/data-url.ts`, `test/util/data-url.test.ts` | `UtilSmoke.dataUrl()` covers base64, percent-decoding, missing comma, and `decodeURIComponent` plus-sign parity. |
| `opencodehx.util.ErrorTools` | `src/util/error.ts`, `test/util/error.test.ts` | `UtilSmoke.errorTools()` covers native errors, record-like errors, opaque throwables, and `errorData` shape against `fixtures/resources/errors/diagnostics.golden.json`. |
| `opencodehx.util.Wildcard` | `src/util/wildcard.ts`, `test/util/wildcard.test.ts` | `UtilSmoke.wildcard()` covers `*`/`?` glob tokens, regex escaping, trailing command ` *`, slash normalization, platform case sensitivity, most-specific rule selection, and structured command sequence matching. |
| `opencodehx.util.Which` | `src/util/which.ts`, `test/util/which.test.ts` | `UtilSmoke.which()` covers missing commands, PATH overrides, first PATH match, Unix executable-bit filtering, Windows PATHEXT, and Windows Path casing fallback. |
| `opencodehx.util.ModuleResolver` | `packages/shared/src/util/module.ts`, `test/util/module.test.ts` | `UtilSmoke.moduleResolver()` covers package subpath resolution, ancestor `node_modules`, per-root isolation, package `main`, and missing-package null behavior. |
| `opencodehx.host.node.NodeBuffer` | Node `Buffer` usage in upstream `decodeDataUrl` | Generated TS imports `node:buffer` only through the host facade. |
| `opencodehx.externs.web.UriCodec` | JavaScript global `decodeURIComponent` | Keeps percent-decoding behind a named typed boundary so utility code does not embed raw `js.Syntax.code`. |

## Notes

- `Lazy<T>` is modeled as a Haxe class with `get()` and `reset()` rather than a callable function with an attached `reset` property. This keeps Haxe source clearer while preserving the behavior OpenCode relies on.
- `DataUrl.decode` intentionally uses JavaScript `decodeURIComponent` through `UriCodec` instead of Haxe `StringTools.urlDecode`, because upstream does not translate `+` into a space.
- Base64 decoding is routed through `opencodehx.host.node.NodeBuffer`. A first attempt using Haxe `haxe.crypto.Base64` pulled in generated stdlib `Bytes.ts` that did not strict-check cleanly; the Node facade matches upstream behavior and keeps the host seam explicit.
- `npm run build` now cleans `src-gen` and `dist` first so stale generated files cannot poison `tsc` after a failed experiment.
