# Headless Run Scaffold

**Bead:** `opencodehx-021`  
**Upstream oracle:** `../opencode/packages/opencode/src/index.ts` and `../opencode/packages/opencode/src/cli/cmd/run.ts`

## Slice

This slice adds the first executable CLI path:

- `opencodehx.cli.Cli` handles `--help`, `--version`, and `run [message..]`.
- `opencodehx.cli.CliSurface` records the broader upstream yargs command surface so non-`run` command help, aliases, options, and known-command errors can be tested while most command side effects are still deferred.
- `run --model openai/gpt-5.2` uses the deterministic fake provider from `opencodehx-020`.
- `run --format json` emits the same normalized one-turn transcript as the fake-provider harness.
- Default `run` output prints the assistant text for non-JSON headless use.
- `run --dir <path>` resolves a real workspace directory for the deterministic fake-provider path while preserving the fixture directory when no `--dir` is provided, so transcript parity remains stable and bootstrapping smokes can still prove workspace-sensitive assistant metadata.
- `run --file <path>` and `-f <path>` resolve local files or directories into upstream-shaped user `file` parts before the prompt text. Existing files use `text/plain`, directories use `application/x-directory`, filenames come from the path basename, and URLs use Node `file://` URLs. Missing files fail before provider/session execution.
- `run --session <id>` now validates a stored session through the configured SQLite database, reuses the recovered session ID, and uses the stored session directory when `--dir` is absent. `run --continue` lists sessions newest-first and selects the latest root session, skipping forked children. `run --session <id> --fork` and `run --continue --fork` create a fresh child `ses_...` session with `parentID` pointing at the recovered parent.
- When `OPENCODE_DB` is explicitly set, a new non-resumed `run` generates a fresh `ses_...` ID, persists the deterministic two-message transcript through `SessionStore`, and can be exported immediately with `export <sessionID>`. A following `run --session <sessionID>` or `run --continue` appends another deterministic turn with fresh turn-scoped message/part IDs, while `--fork` starts a new persisted child session instead of appending.
- `CliSmoke` covers the pure parser/dispatcher, and `scripts/harness/cli-smoke.mjs` verifies the generated Node binary behavior.
- `run --mock-ai-sdk` routes through the credential-free async AI SDK-backed session harness (`Cli.runAsync` -> `SessionProcessor.runAiSdk`). This proves the generated CLI can wait for provider promises and emit a normal transcript without requiring credentials; the mock path also honors `--dir`, persists/resumes/appends through `OPENCODE_DB`, includes recovered text-only user/assistant history in resumed model prompts, and the session layer covers registry tool schema advertisement, AI SDK-emitted tool-call dispatch, and bounded repeated follow-up calls after successful tool results in smoke fixtures.
- `run --live-ai-sdk --model provider/model` is an opt-in live path through `ProviderRegistry.getLanguage` and the real AI SDK stream facade. It loads well-known remote configs from `wellknown` auth entries, the XDG global config directory, project config for the run directory, `OPENCODE_AUTH_CONTENT`, the upstream-shaped XDG data `auth.json` file, and read-only active-account `/api/config` from the upstream-shaped SQLite account tables before resolving providers.
- The CLI still intentionally defaults to the deterministic fake-provider path until full live session orchestration, cancellation, richer upstream message-history construction, and retry scheduling are wired.

Useful commands:

```bash
node dist/index.js --help
node dist/index.js --version
node dist/index.js run --model openai/gpt-5.2 "Say hello from the fixture."
node dist/index.js run --format json --model openai/gpt-5.2 "Say hello from the fixture."
node dist/index.js run --dir "$PWD" --format json --model openai/gpt-5.2 "Say hello from this workspace."
node dist/index.js run --dir "$PWD" --file README.md --format json "Use this file."
OPENCODE_DB=/path/to/opencode.db node dist/index.js run --format json "Persist this session."
OPENCODE_DB=/path/to/opencode.db node dist/index.js run --session ses_example --format json "Continue this session."
OPENCODE_DB=/path/to/opencode.db node dist/index.js run --continue --format json "Continue the latest root session."
OPENCODE_DB=/path/to/opencode.db node dist/index.js run --session ses_example --fork --format json "Fork this session."
node dist/index.js run --mock-ai-sdk "Say hello through the SDK."
node dist/index.js run --mock-ai-sdk --dir "$PWD" --format json "Say hello through the SDK."
node dist/index.js run --live-ai-sdk --model openai/gpt-5.2 "Say hello with a real provider."
OPENCODE_DB=/path/to/opencode.db node dist/index.js export ses_example --sanitize
npm run cli:smoke
```

## Evidence

Gates used for this slice:

```bash
npm run build
npm run smoke
npm run cli:smoke
npm run transcript:parity
```

`transcript:parity` now checks both `--transcript-fixture` and `run --format json` against the golden transcript.

## Boundary

This is not the full yargs/OpenCode command runtime. The command surface catalog covers help text, aliases, options, and known-command errors for the upstream command set, but most non-`run` command handlers still intentionally stop before side effects. `export <sessionID>` is the first exception and currently covers only the non-interactive SQLite-backed path, not the upstream interactive session picker. The default path deliberately accepts only the fake provider model and the minimal `run` behavior needed to keep transcript parity deterministic. `--dir` is now honored by deterministic and mock runs, `--file` now records local file/directory attachment metadata as user parts, `OPENCODE_DB` lets fresh and resumed scaffold runs persist, `--session`/`--continue` validate and reuse stored session IDs, and `--fork` creates a fresh child session with recovered text-only history available to the mock AI SDK prompt path. Full upstream history construction, project initialization, and permission prompting around that workspace are still later slices. The `--mock-ai-sdk` path is a development harness over the real AI SDK stream facade, not a live provider claim. The `--live-ai-sdk` path is real but intentionally thin: it requires an explicit `--model`, loads well-known remote config, active-account remote config, global/project config, process env, and upstream-shaped auth storage, and still lacks account login/token refresh, server-backed session orchestration, cancellation, retry scheduling, and upstream message-history construction around tool/file parts. Session creation without explicit `OPENCODE_DB`, full history-aware storage-backed conversation continuation, slash commands, live provider attachment handling beyond recorded file parts, permission prompts, server attach, full model/provider registry UX, real agent selection, most side-effecting CLI subcommands, and complete provider-backed CLI chat remain deferred.

Future live-chat work should keep this CLI facade stable while replacing only the provider/session execution path behind it.
