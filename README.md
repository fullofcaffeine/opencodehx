# OpenCodeHX

OpenCodeHX is a Haxe-authored port of upstream OpenCode that emits TypeScript through `genes-ts`.

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
