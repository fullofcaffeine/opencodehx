# CLI Command Surface

**Bead:** `opencodehx-036`
**Upstream oracle:** `../opencode/packages/opencode/src/index.ts` plus `../opencode/packages/opencode/src/cli/cmd/*.ts`

## Slice

`opencodehx.cli.CliSurface` records the upstream yargs command surface in typed Haxe data:

- top-level commands registered by upstream `index.ts`, including `acp`, `mcp`, `run`, `debug`, `providers`, `agent`, `serve`, `models`, `stats`, `export`, `import`, `github`, `session`, `plugin`, `db`, and completion;
- upstream aliases currently visible to users, including `providers` as `auth`, `plugin` as `plug`, `mcp list` as `ls`, and provider/agent/run short options;
- first-level and selected nested subcommands for MCP, providers, agents, GitHub, sessions, debug utilities, and DB tools;
- command-specific help output for recognized commands and aliases;
- a first side-effecting `export <sessionID> [--sanitize]` path that reads the configured SQLite session store and writes upstream-shaped JSON to stdout while keeping the progress line on stderr;
- an explicit "known but not implemented yet" error for commands outside the current runnable `run`/non-interactive `export` paths.

The executable runtime remains intentionally narrow. `run` still owns the deterministic fake-provider path, `--mock-ai-sdk`, and the opt-in `--live-ai-sdk` provider-registry path. `export <sessionID>` owns the first non-interactive session export side effect. Other commands are recognized for help and surface parity but do not perform side effects yet.

## Evidence

`src/opencodehx/smoke/CliSmoke.hx` covers the pure dispatcher and `scripts/harness/cli-smoke.mjs` covers generated Node behavior:

- top-level help lists the upstream command set and global options;
- `run --help` includes upstream run options such as `--file`, `--continue`, `--session`, and `--dangerously-skip-permissions`;
- alias help resolves to canonical usage for `auth login --help` and `plug --help`;
- `providers list` is recognized as a known unsupported command instead of falling through to an unknown-command error;
- `run --file ignored.txt ...` does not leak the file option value into the prompt text.
- `export <sessionID>` reads a seeded SQLite session through `OPENCODE_DB`, emits parseable `{ info, messages }` JSON on stdout, preserves the upstream-style `Exporting session: ...` progress line on stderr, supports `--sanitize`, and reports missing sessions.
- `ErrorFormatter` covers upstream-style account transport, provider model-not-found, and config invalid diagnostics against `fixtures/resources/errors/diagnostics.golden.json`.

Gates used for this slice:

```bash
npm run format:haxe
npm run build
npm run cli:smoke
npm run smoke
```

## Boundary

This is not a claim that the full yargs runtime has been ported. Provider login/logout, account console flows, the interactive export picker, import side effects, GitHub actions, MCP auth/add/debug, DB shell behavior, package upgrade/uninstall, and live server/web command behavior remain later product slices. The catalog should move with those implementations so help text and aliases do not drift while command handlers land.
