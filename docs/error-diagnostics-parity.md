# Error Diagnostics Parity

**Bead:** `opencodehx-049`
**Upstream oracle:** `../opencode/packages/opencode/src/util/error.ts`, `../opencode/packages/opencode/src/cli/error.ts`, `../opencode/packages/opencode/test/util/error.test.ts`, and `../opencode/packages/opencode/test/cli/error.test.ts`

## Slice

OpenCodeHX now has a shared user-facing error normalization path:

- `opencodehx.util.ErrorTools` mirrors upstream `errorMessage`, `errorFormat`, and `errorData` for native JavaScript `Error` values, record-like throwables, opaque values, and custom `toString()` fallbacks.
- `opencodehx.cli.ErrorFormatter` mirrors upstream CLI formatting for account transport/service errors, provider model misses, and config JSON/validation failures.
- `opencodehx.account.AccountTransportError` keeps the upstream tagged-error message shape for network failures before an HTTP response exists.
- `Cli.runAsync` formats caught live-provider and server startup exceptions through the shared CLI formatter before writing `stderr`.

## Evidence

`fixtures/resources/errors/diagnostics.golden.json` is the checked-in golden for representative util and CLI diagnostics. `UtilSmoke.errorTools()` and `CliSmoke.diagnosticFormatting()` compare generated runtime output against it.

The async CLI smoke also proves live provider-registry stderr now uses the upstream-style model-not-found diagnostic with the suggested `opencode models` action line.

Current gate:

```bash
npm run build
npm run smoke
```

## Boundary

This is representative diagnostics parity, not the final complete taxonomy. Full yargs validation output, Effect/NamedError coverage beyond the provider/config/account cases above, MCP/provider initialization errors, and TUI rendering of diagnostics remain later surface-specific slices.
