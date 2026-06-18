# Utility Port Notes

**Bead:** `opencodehx-012`

## Ported Utilities

| Haxe module | Upstream oracle | Evidence |
| --- | --- | --- |
| `opencodehx.util.Format` | `src/util/format.ts`, `test/util/format.test.ts` | `UtilSmoke.formatDuration()` covers upstream duration boundaries. |
| `opencodehx.util.Lazy` | `src/util/lazy.ts`, `test/util/lazy.test.ts` | `UtilSmoke.lazy()` covers single evaluation, cached value, and reset behavior. |
| `opencodehx.util.DataUrl` | `src/util/data-url.ts`, `test/util/data-url.test.ts` | `UtilSmoke.dataUrl()` covers base64, percent-decoding, missing comma, and `decodeURIComponent` plus-sign parity. |
| `opencodehx.host.node.NodeBuffer` | Node `Buffer` usage in upstream `decodeDataUrl` | Generated TS imports `node:buffer` only through the host facade. |

## Notes

- `Lazy<T>` is modeled as a Haxe class with `get()` and `reset()` rather than a callable function with an attached `reset` property. This keeps Haxe source clearer while preserving the behavior OpenCode relies on.
- `DataUrl.decode` intentionally uses JavaScript `decodeURIComponent` instead of Haxe `StringTools.urlDecode`, because upstream does not translate `+` into a space.
- Base64 decoding is routed through `opencodehx.host.node.NodeBuffer`. A first attempt using Haxe `haxe.crypto.Base64` pulled in generated stdlib `Bytes.ts` that did not strict-check cleanly; the Node facade matches upstream behavior and keeps the host seam explicit.
- `npm run build` now cleans `src-gen` and `dist` first so stale generated files cannot poison `tsc` after a failed experiment.
