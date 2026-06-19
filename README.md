# OpenCodeHX

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`.

## Port Progress

Current Beads-based completion snapshot:

```text
[########################----------------] 61% (43/70 non-epic port beads closed)
```

This is an unweighted planning indicator, not a parity claim. The working port already has the core scaffold, config, tools, permissions, provider registry, headless fake-provider flow, server seam, and first TUI scaffold/transcript slices. Remaining major work includes real AI SDK streaming, CLI surface parity, SDK/MCP/ACP/LSP/plugin surfaces, fuller TUI dialogs, packaging, and upstream drift/rebase discipline.

The working plan lives in [opencodehx-prd-plan.md](opencodehx-prd-plan.md). Day-to-day work is tracked in Beads under `.beads/issues.jsonl`; start with:

```sh
bd ready --json
```

Primary local references:

- `../opencode`: upstream OpenCode oracle
- `../genes`: sibling Genes checkout containing the `genes-ts` compiler mode

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
