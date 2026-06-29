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
- `PermissionAsyncRuntime`, a focused pending-permission service keyed by `InstanceRuntime` directory. It covers upstream-shaped pending requests, typed scoped/global bus publication for `permission.asked` and `permission.replied`, `once`/`always`/`reject` replies, same-session rejection, matching same-session `always` resolution, service-local approval persistence, directory isolation, and pending rejection on instance dispose/reload.
- Tool integration through the existing `ToolContext.ask` hook.

## Evidence

`PermissionSmoke` covers:

- Pure rules: config conversion, wildcard evaluation, specific-over-wildcard precedence, home-directory expansion, merge ordering, exact/glob/wildcard permission matching, and unknown-permission fallback.
- Tool policy helpers: task-tool permission rules, task disabled-tool wildcard edge cases, edit-family disabled behavior, and bash arity prefixing.
- Synchronous tool boundary behavior: ask/always/reject decisions and read/bash tool integration.
- Async pending lifecycle behavior: pending payload/listing, `permission.asked`/`permission.replied` scoped and global bus events, `once`, `reject`, corrected reject messages, same-session reject cancellation, `always` approvals, matching same-session resolution, directory isolation, instance dispose/reload rejection, deny-before-pending short-circuiting, and all-allow immediate resolution.

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Boundary

This does not yet persist approved permissions to the session database or integrate the async service into the live session/tool graph. The synchronous runtime remains the active `ToolContext.ask` adapter because the current tool registry is synchronous. When the live session/tool graph is promoted to an async/effectful boundary, it should keep these pure rule semantics and `PermissionAsyncRuntime` lifecycle behavior as the oracle for the pending service.

## genes-ts Note

Optional record fields in constructors may need explicit branch assignments instead of ternary expressions so generated TypeScript narrows under `strictNullChecks`.
