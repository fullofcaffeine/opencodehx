# Permission Model Port

**Bead:** `opencodehx-019`  
**Upstream oracle:** `../opencode/packages/opencode/src/permission/{index,evaluate,arity,schema}.ts`, `../opencode/packages/opencode/test/permission/next.test.ts`, and permission assertions in tool tests.

## Slice

This slice adds the first Haxe-owned permission model:

- `PermissionRule` records with upstream action strings: `allow`, `deny`, and `ask`.
- `PermissionRules.evaluate` with last matching wildcard rule semantics.
- `PermissionRules.fromConfig` for upstream-shaped config objects, including top-level wildcard-first ordering and `~` / `$HOME` expansion.
- `PermissionRules.disabled` for removing tools when a wildcard deny applies, including edit-family mapping for `write`, `edit`, and `apply_patch`.
- `PermissionRuntime`, a synchronous ask/reply adapter for the current tool execution model. It supports prompt replies of `once`, `always`, and `reject`, and records upstream-shaped permission ask payloads.
- Tool integration through the existing `ToolContext.ask` hook.

## Evidence

`PermissionSmoke` covers config conversion, wildcard evaluation, specific-over-wildcard precedence, disabled tools, ask/always/reject behavior, and read/bash tool integration.

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Boundary

This does not yet persist approved permissions to the session database, publish bus events, or model the full async pending-permission lifecycle. The runtime is intentionally synchronous because the current tool registry is synchronous. When `opencodehx-022` adds the session processor, it should either keep this adapter around the sync tool surface or promote tool execution to an async/effectful boundary.

## genes-ts Note

Optional record fields in constructors may need explicit branch assignments instead of ternary expressions so generated TypeScript narrows under `strictNullChecks`.
