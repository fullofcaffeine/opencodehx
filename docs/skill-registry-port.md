# Skill Registry Port

**Upstream oracle:** `../opencode/packages/opencode/src/skill/*`, `../opencode/packages/opencode/test/skill/skill.test.ts`, and `../opencode/packages/opencode/test/session/system.test.ts`

## Slice

This slice ports the local, filesystem-backed skill registry without pulling in upstream Effect, remote discovery downloads, or the full session prompt service.

Implemented:

- `opencodehx.skill.SkillRegistry` as a typed, synchronous local registry.
- Skill records with `name`, `description`, `location`, and raw markdown `content`.
- `.opencode/skill/**/SKILL.md` and `.opencode/skills/**/SKILL.md` discovery.
- Project and global external skill discovery from `.claude/skills/**/SKILL.md` and `.agents/skills/**/SKILL.md`.
- `skills.paths` config support for extra local skill roots.
- Missing-frontmatter or missing-required-field skills are skipped, matching upstream's permissive registry behavior.
- Duplicate names resolve later by discovery order, matching the upstream map assignment behavior.
- `dirs` returns directories for discovered `SKILL.md` files, including invalid skill files, because upstream records dirs during scanning before validation.
- Stable name-sorted skill lists and verbose XML-ish formatting with file URLs.

Smoke coverage lives in `opencodehx.smoke.SkillSmoke` and exercises local `.opencode` skills, invalid skill skipping, discovered dirs, external `.claude`/`.agents` skills, global-home external skills, `disableExternal`, `skills.paths`, and sorted verbose formatting.

## Deliberate Boundaries

Remote `skills.urls` discovery and cache/download behavior remain deferred to the network/cache slice. The typed config shape preserves `urls` now, but `SkillRegistry` intentionally does not fetch them yet.

Permission-filtered `available(agent)` and integration with the final session system prompt service remain deferred until the agent/session layers own that behavior. The current `format` helper covers the sorted output shape used by upstream system prompt tests.

Skill frontmatter uses the shared markdown parser's `unknown` boundary, then immediately narrows required fields into `SkillInfo`. Do not let skill content or metadata become broad `Dynamic` in app-facing code.
