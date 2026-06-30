# OpenCodeHX

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`.

The current `0.1.0-beta.0` beta baseline has the public-readiness scaffolding in place: repo-managed hooks, Haxe formatting, staged and full-history gitleaks checks, GitHub CI including a Windows shell parity job, Dependabot, semantic-release dry-run support, and release contract checks. It is still a port-in-progress, not a production OpenCode replacement.

The project intentionally uses 0.x beta versioning until upstream OpenCode parity, packaging, and runtime smoke coverage are strong enough for stable release claims.

## Port Progress

Current Beads-based completion snapshot:

```text
[#######################################-] 98% (328/337 non-epic port beads closed)
```

This is an unweighted planning indicator, not a parity claim.

What runs today:

- The generated CLI has deterministic fake-provider `run`, credential-free mock AI SDK `run`, local live AI SDK `run --model provider/model`, plain config-model/default-agent live `run`, `run --file`, recovered text/file/tool/media/provider-transform/compaction/subtask/interrupted-output history prompts, default and `OPENCODE_DB` session persistence, `run --session`, `run --continue`, `run --fork`, and non-interactive `export <sessionID>`.
- Local no-network live OpenAI-compatible fixtures prove successful streaming, provider-aware request params/options/headers/variants and provider message transforms reaching `streamText(...)`, upstream-shaped system prompts with file-backed instructions reaching the request body, selected/default agent model/tool filtering, provider-error persistence/export, registry tool schema advertisement, bounded continuation calls, model-emitted `read`, `write`, `edit`, `apply_patch`, and `bash` tool calls, a write-then-read multi-step tool chain, config-denied live tool calls including deny precedence under `--dangerously-skip-permissions`, and skip-flag approval for config-asked writes with persisted/exported tool parts and workspace side effects.
- The npm package smoke installs the packed binary globally in a temporary prefix and repeats the installed `run --dir`, `run --file`, mock/live run, live default-agent config, live single-tool and multi-tool-chain calls, persistence/export/resume/continue/fork, TUI scaffold, and `serve` health/SSE/session/PTY workflows.
- The runtime foundation includes config and TUI config migration/precedence, account-backed remote config/token substitution, auth discovery/storage normalization, account repo persistence and credential-free account service smokes including token refresh/coalescing, permissions with async pending-lifecycle and server route evidence, question runtime plus server routes, parser-backed bash permissions, file/search tools including read-tool image/PDF attachments, custom `.opencode/tool(s)` discovery evidence, per-message instruction dedupe, and recovered loaded-instruction suppression, standalone patch and snapshot runtimes, provider registry and SDK factory smokes, models.dev cache/fetch, storage persistence and JSON migration evidence, sessions, server routes with typed session/PTY request decoding, SDK-compatible create/list/resume/event flow, AppRuntime logger/context evidence, cross-spawn process-handle evidence, Effect runner shared-run/cancel evidence, workspace restore batching/progress evidence, MCP/ACP/LSP/plugin minimum seams, PTY lifecycle/WebSocket replay, native file-watcher evidence, performance baselines, checked artifact macros, and TUI scaffold/transcript/dialog slices.

The CLI still defaults to the deterministic fake provider when no local config model or default-agent model is present. The live path is real but intentionally thin: it has credential-free local provider evidence, side-effecting tool-loop evidence, provider-aware request options and prompt transforms, selected/default agent request assembly, retryable stream-error intent recording plus deterministic initial/continuation retry-loop evidence, live AI SDK stream/continuation cancellation evidence, injected and config-backed server-owned live AI SDK route/status/active-abort evidence, upstream-shaped provider/environment/skills/instruction system prompts including remote instruction URLs, nearby read-tool instruction reminders with per-message dedupe and recovered loaded-history suppression, and recovered text/file/tool/media/provider-metadata/provider-transform/compaction/subtask/interrupted-output prompt history. Full agentic chat parity still needs broader retry backoff and user-facing cancellation lifecycle wiring, richer interactive permission prompting UX, reminder prompt services, broader provider loading, live plugin installs/imports/auth/adaptors, real MCP/ACP transports and OAuth, real LSP process/download flows, live TUI behavior beyond the scaffold, credential-backed provider success where safe, and periodic upstream drift runs using the documented rebase procedure.

Try the generated CLI locally:

```sh
npm run build
node dist/index.js run --format json "Say hello from OpenCodeHX."
node dist/index.js run --mock-ai-sdk --dir "$PWD" --format json "Say hello through the SDK."
node dist/index.js serve --hostname 127.0.0.1 --port 0
```

To exercise the packaged binary path, run:

```sh
npm run package:smoke
```

The working plan lives in [opencodehx-prd-plan.md](opencodehx-prd-plan.md). Day-to-day work is tracked in Beads under `.beads/issues.jsonl`; start with:

```sh
bd ready --json
```

Primary local references:

- `../opencode`: upstream OpenCode oracle
- `../genes`: sibling Genes checkout containing the `genes-ts` compiler mode

Builds currently require the sibling `../genes` checkout pinned in [reference/genes.pin.json](reference/genes.pin.json). GitHub CI checks out `fullofcaffeine/genes-ts` next to this repository to preserve that layout.

Strict TypeScript output is the default generated product surface. Classic Genes ES6 output is tracked only as a future secondary profile; see [compiler-output-profiles.md](docs/compiler-output-profiles.md).

CI installs npm packages with lifecycle scripts disabled, then explicitly rebuilds the `better-sqlite3` native addon and runs the local `bun` package installer for Bun-backed harnesses. The Node smoke job also installs `ripgrep` before exercising the file-search seam. Keep those bootstrap steps with `npm run test:haxe:unit`, `npm run macro:diagnostics`, `npm run tui:scaffold`, and `npm run smoke`.

See [AGENTS.md](AGENTS.md) for project rules, Haxe design direction, and the `genes-ts` improvement loop.

## Local Hooks

Install the repo-managed shared hooks:

```sh
haxelib install formatter
brew install gitleaks # or use another gitleaks install method
npm run hooks:install
```

The shared hook directory is `.beads-hooks/`: it chains Beads' `pre-commit`,
`pre-push`, `post-merge`, `post-checkout`, and `prepare-commit-msg` hooks with
the existing staged gitleaks and Haxe formatter checks.

CI runs a dedicated gitleaks workflow, and local public-readiness checks run with:

```sh
npm run public:precommit
```

Release/readiness contracts can be checked without a full generated build:

```sh
npm test
```

The broader local CI gate is:

```sh
npm run ci:full
```

The native Windows shell/PTY parity gate is separate from the portable local gate:

```sh
npm run windows:shell:smoke
```

It skips on non-Windows hosts and runs under the GitHub `windows-shell-parity` job.

Native file-watcher evidence is also explicit because watcher timing varies by host:

```sh
npm run file:watcher:smoke
```

This builds the generated output and uses the real Node `fs.watch` backend against a temporary git repo, proving `.git/HEAD` changes refresh VCS branch state through the typed event bus.

The Bun-only abort leak oracle is opt-in because it uses forced GC and heap-growth thresholds:

```sh
npm run memory:abort:smoke
```

It builds first, runs the repo-pinned Bun binary, and checks both the local webfetch abort path and the bound-handler retention comparison in a fresh worker process.

Live package-manager side effects are also outside normal smoke and CI. To exercise the opt-in npm/pnpm/Bun/Homebrew/Chocolatey/Scoop harness on a disposable host, run:

```sh
OPENCODEHX_LIVE_PACKAGE_MANAGERS=1 npm run live:package-managers
```

Use `OPENCODEHX_LIVE_PACKAGE_MANAGERS_TARGETS=npm,bun` to limit targets. The harness uses temp prefixes/projects or package-manager dry-run/noop modes where available, and skips managers that are unavailable or lack a repo-approved disposable path.
