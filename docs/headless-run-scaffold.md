# Headless Run Scaffold

**Bead:** `opencodehx-021`  
**Upstream oracle:** `../opencode/packages/opencode/src/index.ts` and `../opencode/packages/opencode/src/cli/cmd/run.ts`

## Slice

This slice adds the first executable CLI path:

- `opencodehx.cli.Cli` handles `--help`, `--version`, and `run [message..]`.
- `run --model openai/gpt-5.2` uses the deterministic fake provider from `opencodehx-020`.
- `run --format json` emits the same normalized one-turn transcript as the fake-provider harness.
- Default `run` output prints the assistant text for non-JSON headless use.
- `CliSmoke` covers the pure parser/dispatcher, and `scripts/harness/cli-smoke.mjs` verifies the generated Node binary behavior.

Useful commands:

```bash
node dist/index.js --help
node dist/index.js --version
node dist/index.js run --model openai/gpt-5.2 "Say hello from the fixture."
node dist/index.js run --format json --model openai/gpt-5.2 "Say hello from the fixture."
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

This is not the full yargs/OpenCode command surface. It deliberately accepts only the fake provider model and the minimal `run` flags needed to unblock the next session processor slice. Session creation, storage-backed conversation history, commands, file attachments, permission prompts, server attach, model/provider registry lookup, and real agent selection remain deferred.

When `opencodehx-022` ports the one-turn session processor, keep this CLI facade stable and replace the transcript construction internals with the real session flow.
