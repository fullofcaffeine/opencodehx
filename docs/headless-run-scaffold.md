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
- A new non-resumed `run` generates a fresh `ses_...` ID, persists the deterministic two-message transcript through `SessionStore` using the default XDG data database, and can be exported immediately with `export <sessionID>`. A following `run --session <sessionID>` or `run --continue` appends another deterministic turn with fresh turn-scoped message/part IDs, while `--fork` starts a new persisted child session instead of appending. `OPENCODE_DB` remains an override for isolated or custom database paths.
- `CliSmoke` covers the pure parser/dispatcher, and `scripts/harness/cli-smoke.mjs` verifies the generated Node binary behavior.
- `run --mock-ai-sdk` routes through the credential-free async AI SDK-backed session harness (`Cli.runAsync` -> `SessionProcessor.runAiSdk`). This proves the generated CLI can wait for provider promises and emit a normal transcript without requiring credentials; the mock path also honors `--dir`, persists/resumes/appends through the default or `OPENCODE_DB` store, includes recovered text/user-file/assistant-tool history in resumed model prompts, and the session layer covers registry tool schema advertisement, AI SDK-emitted tool-call dispatch, and bounded repeated follow-up calls after successful tool results in smoke fixtures.
- `run --model provider/model` now routes explicit non-fake models through `ProviderRegistry.getLanguage` and the real AI SDK stream facade from the generated CLI. Plain `run` does the same when local global/project config provides a non-fake `model`, or when `default_agent`/`--agent` selects an agent with a non-fake model; no-config runs still use the deterministic fake provider. The `--live-ai-sdk` harness flag remains as an explicit override. The live path loads well-known remote configs from `wellknown` auth entries, the XDG global config directory, project config for the run directory, `OPENCODE_AUTH_CONTENT`, the upstream-shaped XDG data `auth.json` file, and read-only active-account `/api/config` from the upstream-shaped SQLite account tables before resolving providers. It shares the deterministic/mock headless run plumbing for `--file`, default/`OPENCODE_DB` fresh-session persistence/export, `--session` resumed append, `--continue`, and `--fork` child sessions. `CliSmoke` and `scripts/harness/cli-smoke.mjs` run local no-network OpenAI-compatible servers and verify a successful streamed assistant response without the scaffold flag, plain config/default-agent live resolution, model-emitted `read`, `write`, `edit`, `apply_patch`, and `bash` tool calls with continuation, `write` file creation, `edit` file mutation, `apply_patch` patch mutation, `bash` command side effects, config-denied write enforcement including skip-flag deny precedence, `--dangerously-skip-permissions` approval for config-asked writes, provider-error events, assistant `finish: "error"` persistence/export, request URL, authorization header, `stream: true` request body, file part, exported session, resumed append, latest-root continue, and fork parent linkage.
- Live AI SDK requests now use the existing `SessionLlm` assembly path for both initial calls and tool-result continuations. The stream facade forwards max output tokens, temperature, `topP`, `topK`, request headers, transformed provider options, `maxRetries: 0`, and `--variant`-selected model options into `streamText(...)`; `SessionProcessorSmoke` verifies those fields through `MockLanguageModelV3.doStreamCalls`. Selected/default agent config now feeds that same live path for agent name, model fallback, variant fallback, provider options, temperature, `top_p`, disabled tool filtering, and agent permission rules. Live CLI runs also build upstream-shaped system prompts from the selected agent or provider prompt resource, project environment text, permission-filtered skill availability, and file-backed system instructions before sending the AI SDK request body.
- The CLI still intentionally defaults to the deterministic fake-provider path when no local config model or default-agent model is present, until full live session orchestration, cancellation, remaining upstream message-history edges, and retry loop scheduling are wired.

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
node dist/index.js run --model provider/model "Say hello with a real provider."
node dist/index.js run "Say hello with the configured model."
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

`transcript:parity` now checks both `--transcript-fixture` and `run --format json` against the golden transcript. The `run` check normalizes fresh persisted session IDs back to the fixture ID before comparison, because normal CLI runs intentionally create new sessions.

## Boundary

This is not the full yargs/OpenCode command runtime. The command surface catalog covers help text, aliases, options, and known-command errors for the upstream command set, but most non-`run` command handlers still intentionally stop before side effects. `export <sessionID>` is the first exception and currently covers only the non-interactive SQLite-backed path, not the upstream interactive session picker. The default path deliberately accepts only the fake provider model and the minimal `run` behavior needed to keep transcript parity deterministic. `--dir` is now honored by deterministic, mock, and live runs; `--file` now records local file/directory attachment metadata as user parts; default storage plus `OPENCODE_DB` overrides let fresh and resumed scaffold runs persist; `--session`/`--continue` validate and reuse stored session IDs; and `--fork` creates a fresh child session with recovered text history available to the mock/live AI SDK prompt path. Session smokes also prove recovered user file parts and assistant tool-call/tool-result history in the live AI SDK model prompt. Full upstream history edges, project initialization, and interactive permission prompting around that workspace are still later slices. The `--mock-ai-sdk` path is a development harness over the real AI SDK stream facade, not a live provider claim. The live AI SDK path is real but intentionally thin: explicit non-fake `--model provider/model` routes there from the generated CLI, plain configured/default-agent `run` also routes there when local config provides `model` or an agent model, `--live-ai-sdk` remains available as a harness override, and the path loads well-known remote config, active-account remote config, global/project config, process env, and upstream-shaped auth storage. It now has local OpenAI-compatible streaming, selected/default agent request assembly, provider-aware request params/options/headers/variants in the real `streamText(...)` call, retryable stream-error status/part recording without implicit SDK retries, upstream-shaped provider/environment/skills/instruction system prompt assembly including local files and remote instruction URLs, nearby read-tool instruction reminders with per-message dedupe and recovered loaded-history suppression, provider-error transcript metadata, local live `read`, `write`, `edit`, `apply_patch`, and `bash` tool-call/continuation fixtures with write/edit/patch/bash side-effect verification, config-denied live write-tool enforcement including skip-flag deny precedence, `--dangerously-skip-permissions` approval for config-asked writes, and default/OPENCODE_DB export/resume evidence without external credentials. It still lacks account login/token refresh, server-backed session orchestration, cancellation, retry loop scheduling, broader interactive permission prompting, reminder prompt services, and remaining upstream message-history edges such as compaction/subtask/media-tool-result nuance. Slash commands, server attach, full model/provider registry UX, most side-effecting CLI subcommands, and complete provider-backed CLI chat remain deferred.

Future live-chat work should keep this CLI facade stable while replacing only the provider/session execution path behind it.
