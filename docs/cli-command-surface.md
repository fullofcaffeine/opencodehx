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
- first non-interactive `run --session <id>`, `run --continue`, and `--fork` recovery wiring that validates the session in the configured SQLite store, preserves the recovered session ID for normal resume, creates a fresh child session for forked runs, defaults the run directory from the stored session when `--dir` is absent, and appends new turns in the default or `OPENCODE_DB` store;
- new headless `run` invocations persist a generated session into the configured SQLite store by default, making the result immediately exportable/resumable while preserving `OPENCODE_DB` as an override;
- pure GitHub remote URL parsing for the upstream `github` command's supported remote forms;
- pure GitHub action helpers for response text extraction from typed message parts and prompt-too-large diagnostics for attached files;
- pure console account display formatting for account labels and active org rows;
- pure `import <file>` share helpers for share URL parsing, same-origin auth decisions, and flat share-data grouping;
- an explicit "known but not implemented yet" error for commands outside the current runnable `run`/non-interactive `export` paths.

The executable runtime remains intentionally narrow. `run` still owns the deterministic fake-provider path and `--mock-ai-sdk`; the generated CLI now routes explicit non-fake `--model provider/model` values and plain runs with a local config `model` to the provider-registry live path. `--live-ai-sdk` remains as an explicit harness override. `export <sessionID>` owns the first non-interactive session export side effect. Other commands are recognized for help and surface parity but do not perform side effects yet.

## Evidence

`src/opencodehx/smoke/CliSmoke.hx` covers the pure dispatcher and `scripts/harness/cli-smoke.mjs` covers generated Node behavior:

- top-level help lists the upstream command set and global options;
- `run --help` includes upstream run options such as `--file`, `--continue`, `--session`, and `--dangerously-skip-permissions`;
- alias help resolves to canonical usage for `auth login --help` and `plug --help`;
- `providers list` is recognized as a known unsupported command instead of falling through to an unknown-command error;
- `run --file <file>` and `-f <dir>` attach local file/directory metadata as ordered user `file` parts before the text prompt, and missing files fail before provider execution.
- `export <sessionID>` reads a seeded SQLite session through `OPENCODE_DB`, emits parseable `{ info, messages }` JSON on stdout, preserves the upstream-style `Exporting session: ...` progress line on stderr, supports `--sanitize`, and reports missing sessions.
- `run --session <id>` reads the same seeded SQLite store, emits JSON with the recovered session ID, defaults assistant path metadata to the stored session directory, honors an explicit `--dir` override, and reports missing sessions.
- `run --continue` lists stored sessions newest-first, skips forked child sessions, and continues the latest root session in the non-interactive scaffold.
- `run --session <id> --fork` reads the same recovered session history, emits a fresh generated child session ID, persists that child with `info.parentID` pointing at the recovered parent, and exports the child transcript.
- `run --format json ...` generates a fresh `ses_...` ID, persists the two-message transcript, and `export <generated>` reads it back through the generated CLI. A following `run --session <generated>` appends a second two-message turn with fresh message/part IDs and export returns all four messages. The same path is covered with `OPENCODE_DB` overrides for custom database locations.
- `GitHubRemote.parse` mirrors upstream `cli/github-remote.test.ts` for HTTPS/HTTP, `git@`, `ssh://git@`, optional `.git` suffixes, hyphen/underscore/number/dot owner and repo names, non-GitHub rejection, invalid URLs, missing owner/repo, and extra path rejection.
- `GitHubAction` mirrors upstream `cli/github-action.test.ts` pure helpers: response text extraction returns the last text part, returns `null` for reasoning/tool/step-only responses, throws on empty part arrays, and formats prompt-too-large errors with attached base64 file sizes.
- `AccountDisplay` mirrors upstream `cli/account.test.ts` for account URL labels, active account suffixes, and active org row formatting after ANSI stripping.
- `CliImport` mirrors upstream `cli/import.test.ts` pure helpers for valid and invalid share URLs, same-origin auth-header decisions including default `:443` normalization, and transformation from flat session/message/part share rows into export-shaped nested data.
- `ErrorFormatter` covers upstream-style account transport, provider model-not-found, and config invalid diagnostics against `fixtures/resources/errors/diagnostics.golden.json`.

Gates used for this slice:

```bash
npm run format:haxe
npm run build
npm run cli:smoke
npm run smoke
```

## Boundary

This is not a claim that the full yargs runtime has been ported. Provider login/logout, account console side effects beyond display formatting, full history-aware prompt construction, the interactive export picker, import fetch/file/database side effects, GitHub action execution/network behavior, MCP auth/add/debug, DB shell behavior, package upgrade/uninstall, and live server/web command behavior remain later product slices. The catalog should move with those implementations so help text and aliases do not drift while command handlers land.
