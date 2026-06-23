# Headless Run Scaffold

**Bead:** `opencodehx-021`  
**Upstream oracle:** `../opencode/packages/opencode/src/index.ts` and `../opencode/packages/opencode/src/cli/cmd/run.ts`

## Slice

This slice adds the first executable CLI path:

- `opencodehx.cli.Cli` handles `--help`, `--version`, and `run [message..]`.
- `opencodehx.cli.CliSurface` records the broader upstream yargs command surface so non-`run` command help, aliases, options, and known-command errors can be tested while command side effects are still deferred.
- `run --model openai/gpt-5.2` uses the deterministic fake provider from `opencodehx-020`.
- `run --format json` emits the same normalized one-turn transcript as the fake-provider harness.
- Default `run` output prints the assistant text for non-JSON headless use.
- `CliSmoke` covers the pure parser/dispatcher, and `scripts/harness/cli-smoke.mjs` verifies the generated Node binary behavior.
- `run --mock-ai-sdk` routes through the credential-free async AI SDK-backed session harness (`Cli.runAsync` -> `SessionProcessor.runAiSdk`). This proves the generated CLI can wait for provider promises and emit a normal transcript without requiring credentials; the session layer also covers registry tool schema advertisement, AI SDK-emitted tool-call dispatch, and bounded repeated follow-up calls after successful tool results in smoke fixtures.
- `run --live-ai-sdk --model provider/model` is an opt-in live path through `ProviderRegistry.getLanguage` and the real AI SDK stream facade. It loads well-known remote configs from `wellknown` auth entries, the XDG global config directory, project config for the run directory, `OPENCODE_AUTH_CONTENT`, the upstream-shaped XDG data `auth.json` file, and read-only active-account `/api/config` from the upstream-shaped SQLite account tables before resolving providers.
- The CLI still intentionally defaults to the deterministic fake-provider path until full live session orchestration, cancellation, upstream message-history prompt construction, and retry scheduling are wired.

Useful commands:

```bash
node dist/index.js --help
node dist/index.js --version
node dist/index.js run --model openai/gpt-5.2 "Say hello from the fixture."
node dist/index.js run --format json --model openai/gpt-5.2 "Say hello from the fixture."
node dist/index.js run --mock-ai-sdk "Say hello through the SDK."
node dist/index.js run --mock-ai-sdk --format json "Say hello through the SDK."
node dist/index.js run --live-ai-sdk --model openai/gpt-5.2 "Say hello with a real provider."
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

This is not the full yargs/OpenCode command runtime. The command surface catalog covers help text, aliases, options, and known-command errors for the upstream command set, but most non-`run` command handlers still intentionally stop before side effects. The default path deliberately accepts only the fake provider model and the minimal `run` behavior needed to keep transcript parity deterministic. The `--mock-ai-sdk` path is a development harness over the real AI SDK stream facade, not a live provider claim. The `--live-ai-sdk` path is real but intentionally thin: it requires an explicit `--model`, loads well-known remote config, active-account remote config, global/project config, process env, and upstream-shaped auth storage, and still lacks account login/token refresh, server-backed session orchestration, cancellation, retry scheduling, and upstream message-history prompt construction around tool results. Session creation, storage-backed conversation history, slash commands, file attachment ingestion, permission prompts, server attach, full model/provider registry UX, real agent selection, side-effecting CLI subcommands, and complete provider-backed CLI chat remain deferred.

Future live-chat work should keep this CLI facade stable while replacing only the provider/session execution path behind it.
