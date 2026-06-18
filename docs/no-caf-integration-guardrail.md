# No-Caf Integration Guardrail

**Bead:** `opencodehx-042`  
**Phase:** M0 through M8, until OpenCode parity evidence is strong enough for M9 preflight.

## Contract

OpenCodeHX Phase 1 is an upstream OpenCode parity project. Caf, Cafex, Cafetera, Brew, and related contract systems are reference material only until the M9 preflight milestone.

The core port must not include Caf-specific runtime behavior, storage schema, agent semantics, transport requirements, naming, fixtures, generated code assumptions, or build gates before M9.

## Allowed Before M9

- Mentioning Caf/Cafex in planning docs as deferred context.
- Reading Caf/Cafex artifacts to understand later adapter needs.
- Maintaining this guardrail and future preflight Beads.
- Mapping possible future seams in analysis docs, provided those docs do not block upstream parity work.

## Not Allowed Before M9

- Adding Caf/Cafex code paths to `src/opencodehx`.
- Making OpenCodeHX CLI, server, session, provider, storage, tool, or TUI behavior depend on Caf concepts.
- Adding Caf/Cafex fixtures as required gates for M1-M8.
- Forking `genes-ts` behavior for Caf-specific output.
- Prioritizing Caf adapter work ahead of upstream OpenCode parity Beads.
- Treating Cafex implementation details as semantic authority for OpenCodeHX core design.

## Dependency Policy

Caf/Cafex tasks must not block M1-M8 parity work. Any future implementation task that adds Caf-specific behavior must depend on an M9 decision/preflight task and must live outside the upstream-shaped core, for example under a clearly named adapter boundary.

The existing M9 analysis bead is `opencodehx-041` (`Cafex seam inventory mapped to OpenCodeHX capabilities`). It depends on the usable packaging/parity line rather than early bootstrap tasks, so it cannot block upstream parity.

## Review Checklist

Use this checklist for changes before M9:

- Does the change preserve upstream OpenCode behavior as the authority?
- Does it avoid Caf/Cafex names, DTOs, runtime assumptions, and storage shapes in core modules?
- If Caf/Cafex is mentioned, is it clearly analysis-only or deferred?
- Are fixtures and gates credential-free and OpenCode-shaped unless the task is explicitly M9+?
- Does any Caf-labeled Bead avoid blocking M1-M8 parity tasks?
- If a seam is created for later Caf work, is it justified by current OpenCode behavior too?

## When To Revisit

Revisit this guardrail only after:

1. M3 headless fake-provider flow passes.
2. Tool, provider, server, and TUI parity have enough evidence for daily use.
3. `opencodehx-041` maps Cafex responsibilities to OpenCodeHX extension points.
4. A decision record explicitly permits adapter work without changing OpenCodeHX core semantics.
