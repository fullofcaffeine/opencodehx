# OpenCodeHX

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`.

The current `0.1.0-beta.0` beta baseline has the public-readiness scaffolding in place: repo-managed hooks, Haxe formatting, staged and full-history gitleaks checks, GitHub CI including a Windows shell parity job, Dependabot, semantic-release dry-run support, and release contract checks. It is still a port-in-progress, not a production OpenCode replacement.

The project intentionally uses 0.x beta versioning until upstream OpenCode parity, packaging, and runtime smoke coverage are strong enough for stable release claims.

## Port Progress

Current Beads-based completion snapshot:

```text
[######################################--] 95% (159/168 non-epic port beads closed)
```

This is an unweighted planning indicator, not a parity claim. The working port already has the core scaffold, config, tools, parser-backed bash permissions with shell-selection parity fixtures, real Node PTY lifecycle and WebSocket replay controls, permissions, provider registry, first AI SDK streamText smoke, OpenAI-compatible/OpenAI/xAI/Azure/Google/Vertex/Anthropic/Bedrock/Mistral/Groq/Cohere/Perplexity/OpenRouter/DeepInfra/Cerebras/Gateway/TogetherAI/Vercel/Alibaba/GitLab SDK factory smokes, Bedrock small-model selection, Cloudflare AI Gateway env/config/auth loading plus no-network SDK factory and request-option header coverage, OpenCode public/paid model gating, first provider request-option/variant/schema transform smoke, models.dev normalization plus cache/fetch smoke, headless fake-provider flow, async `run --mock-ai-sdk` and opt-in `run --live-ai-sdk` CLI paths with global/project config, auth storage, well-known remote config discovery, read-only active-account remote config loading, registry tool schema advertisement to AI SDK model calls, and bounded repeated AI SDK calls after successful tool results, a typed upstream CLI command-surface catalog with alias/help smokes, a typed upstream-order instance bootstrap graph with command-executed project initialization, a local npm global-install package smoke including installed `run --dir`, installed `run --mock-ai-sdk --dir`, installed TUI scaffold execution through package-local Bun, and installed `serve` health/SSE/session/PTY workflow, an opt-in live package-manager side-effect harness, a native file-watcher harness for VCS branch refresh, session retry/compaction/abort fixtures, store-backed session export, server seam, SDK-compatible create/list/resume/event smoke, first MCP/ACP protocol-surface smoke, first LSP runtime/client/tool smoke, first plugin metadata/loader/trigger smoke, source-authored checked artifact macro diagnostics for tools/providers/events/resources, first performance/UX benchmark baselines, and first TUI scaffold/transcript/dialog slices with macro-checked route/keybind diagnostics. The CLI `run` command still defaults to the deterministic fake provider; full live agentic chat wiring and side-effecting CLI subcommands remain later CLI/session integration slices. Remaining major work includes broader provider SDK loading/transforms, full published SDK/MCP/ACP/LSP/plugin surfaces, real MCP/ACP transports and OAuth flows, live plugin imports/installs/auth/adaptors, real LSP process transports/downloads, live TUI behavior beyond the scaffold, and periodic upstream drift runs using the documented rebase procedure.

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

Live package-manager side effects are also outside normal smoke and CI. To exercise the opt-in npm/pnpm/Bun/Homebrew/Chocolatey/Scoop harness on a disposable host, run:

```sh
OPENCODEHX_LIVE_PACKAGE_MANAGERS=1 npm run live:package-managers
```

Use `OPENCODEHX_LIVE_PACKAGE_MANAGERS_TARGETS=npm,bun` to limit targets. The harness uses temp prefixes/projects or package-manager dry-run/noop modes where available, and skips managers that are unavailable or lack a repo-approved disposable path.
