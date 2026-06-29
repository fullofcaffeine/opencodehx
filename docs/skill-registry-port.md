# Skill Registry Port

**Upstream oracle:** `../opencode/packages/opencode/src/skill/*`, `../opencode/packages/opencode/test/skill/skill.test.ts`, and `../opencode/packages/opencode/test/session/system.test.ts`

## Slice

This slice ports the local, filesystem-backed skill registry without pulling in the full upstream Effect service graph.

Implemented:

- `opencodehx.skill.SkillRegistry` as a typed, synchronous local registry.
- Skill records with `name`, `description`, `location`, and raw markdown `content`.
- `.opencode/skill/**/SKILL.md` and `.opencode/skills/**/SKILL.md` discovery.
- Project and global external skill discovery from `.claude/skills/**/SKILL.md` and `.agents/skills/**/SKILL.md`.
- `skills.paths` config support for extra local skill roots.
- `skills.urls` remote discovery through `SkillRemoteDiscovery`, including `index.json` fetching, listed file downloads into a cache directory, `SKILL.md` requirement filtering, trailing-slash normalization, cache reuse, and cache path containment.
- Missing-frontmatter or missing-required-field skills are skipped, matching upstream's permissive registry behavior.
- Duplicate names resolve later by discovery order, matching the upstream map assignment behavior.
- `dirs` returns directories for discovered `SKILL.md` files, including invalid skill files, because upstream records dirs during scanning before validation.
- Stable name-sorted skill lists and verbose XML-ish formatting with file URLs.
- `SkillRegistry.available(discovery, agent)` filters the sorted list through agent `permission.skill` rules, using the skill name as the permission pattern and preserving upstream last-match wildcard behavior.

Smoke coverage lives in `opencodehx.smoke.SkillSmoke` and exercises local `.opencode` skills, invalid skill skipping, discovered dirs, external `.claude`/`.agents` skills, global-home external skills, `disableExternal`, `skills.paths`, remote `skills.urls`, sorted verbose formatting, and permission-filtered availability.

## Deliberate Boundaries

Remote skill downloads currently write text payloads through the Node fs seam because the first upstream fixtures are markdown/resource files. If binary bundled resources become required, add a typed `ArrayBuffer`/`Uint8Array` write path rather than widening the app-facing skill model.

`SessionSystemPrompt` now consumes `SkillRegistry.available` and `SkillRegistry.format` for live CLI AI SDK system prompts, including agent `permission.skill` filtering. Full upstream Effect service integration and binary remote skill resources remain deferred.

Skill frontmatter uses the shared markdown parser's `unknown` boundary, then immediately narrows required fields into `SkillInfo`. Do not let skill content or metadata become broad `Dynamic` in app-facing code.
