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
