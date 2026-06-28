# Permission Model Port

**Bead:** `opencodehx-019`  
**Upstream oracle:** `../opencode/packages/opencode/src/permission/{index,evaluate,arity,schema}.ts`, `../opencode/packages/opencode/test/permission/{next.test.ts,arity.test.ts}`, `../opencode/packages/opencode/test/permission-task.test.ts`, and permission assertions in tool tests.

## Slice

This slice adds the first Haxe-owned permission model:

- `PermissionRule` records with upstream action strings: `allow`, `deny`, and `ask`.
- `PermissionRules.evaluate` with last matching wildcard rule semantics.
- `PermissionRules.fromConfig` for upstream-shaped config objects, including top-level wildcard-first ordering and `~` / `$HOME` expansion.
- `PermissionRules.disabled` for removing tools when a wildcard deny applies, including edit-family mapping for `write`, `edit`, and `apply_patch`.
- `PermissionRules.merge` and pure rule ordering cases for exact matches, glob matches, wildcard permission names, unknown permissions, and config/default override ordering.
- `BashArity.prefix` for deriving the command-prefix tokens used by bash permission matching, including upstream arity-1/2/3 and longest-match cases.
- `PermissionRuntime`, a synchronous ask/reply adapter for the current tool execution model. It supports prompt replies of `once`, `always`, and `reject`, and records upstream-shaped permission ask payloads.
- Tool integration through the existing `ToolContext.ask` hook.

## Evidence

`PermissionSmoke` covers config conversion, wildcard evaluation, specific-over-wildcard precedence, home-directory expansion, merge ordering, exact/glob/wildcard permission matching, unknown-permission fallback, task-tool permission rules, task disabled-tool wildcard edge cases, edit-family disabled behavior, bash arity prefixing, ask/always/reject behavior, and read/bash tool integration.

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Boundary

This does not yet persist approved permissions to the session database, publish bus events, isolate pending permission queues by project instance, reject pending requests on instance dispose/reload, or model the full async pending-permission lifecycle. The runtime is intentionally synchronous because the current tool registry is synchronous. When the live session/tool graph is promoted to an async/effectful boundary, it should keep these pure rule semantics as the oracle for the pending service.

## genes-ts Note

Optional record fields in constructors may need explicit branch assignments instead of ternary expressions so generated TypeScript narrows under `strictNullChecks`.
