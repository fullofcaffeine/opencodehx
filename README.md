# OpenCodeHX

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`.

The current `0.1.0-beta.0` beta baseline has the public-readiness scaffolding in place: repo-managed hooks, Haxe formatting, staged and full-history gitleaks checks, GitHub CI, Dependabot, semantic-release dry-run support, and release contract checks. It is still a port-in-progress, not a production OpenCode replacement.

The project intentionally uses 0.x beta versioning until upstream OpenCode parity, packaging, and runtime smoke coverage are strong enough for stable release claims.

## Port Progress

Current Beads-based completion snapshot:

```text
[##########################--------------] 65% (55/85 non-epic port beads closed)
```

This is an unweighted planning indicator, not a parity claim. The working port already has the core scaffold, config, tools, parser-backed bash permissions with shell-selection parity fixtures, real Node PTY lifecycle and WebSocket replay controls, permissions, provider registry, first AI SDK streamText smoke, OpenAI-compatible/Anthropic/Bedrock SDK factory smokes, Bedrock small-model selection, Cloudflare AI Gateway env/config loading plus no-network SDK factory coverage, OpenCode public/paid model gating, first provider request-option/variant/schema transform smoke, models.dev normalization plus cache/fetch smoke, headless fake-provider flow, session retry/compaction/abort fixtures, server seam, and first TUI scaffold/transcript/dialog slices. Remaining major work includes broader provider SDK loading/transforms, CLI surface parity, SDK/MCP/ACP/LSP/plugin surfaces, live TUI behavior, packaging, and upstream drift/rebase discipline.

The working plan lives in [opencodehx-prd-plan.md](opencodehx-prd-plan.md). Day-to-day work is tracked in Beads under `.beads/issues.jsonl`; start with:

```sh
bd ready --json
```

Primary local references:

- `../opencode`: upstream OpenCode oracle
- `../genes`: sibling Genes checkout containing the `genes-ts` compiler mode

Builds currently require the sibling `../genes` checkout pinned in [reference/genes.pin.json](reference/genes.pin.json). GitHub CI checks out `fullofcaffeine/genes-ts` next to this repository to preserve that layout.

See [AGENTS.md](AGENTS.md) for project rules, Haxe design direction, and the `genes-ts` improvement loop.

## Local Hooks

Install the repo-managed pre-commit hook:

```sh
haxelib install formatter
brew install gitleaks # or use another gitleaks install method
npm run hooks:install
```

The hook runs staged `gitleaks` and formats staged `.hx` files with haxe-formatter. CI runs a dedicated gitleaks workflow, and local public-readiness checks run with:

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
