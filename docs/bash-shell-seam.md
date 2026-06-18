# Bash Shell Seam

**Bead:** `opencodehx-018`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/bash.ts`, `../opencode/packages/opencode/test/pty/pty-session.test.ts`

## Slice

This slice adds the first Node-backed shell execution seam:

- `opencodehx.host.node.NodeProcess` wraps `node:child_process.spawnSync` behind a small Haxe-facing API.
- `bash` is registered as a builtin tool.
- `BashTool` validates `command`, `description`, optional `timeout`, and optional `workdir`.
- Tool permission requests are emitted for `bash` command execution and for external working directories/path arguments.
- Output is normalized into upstream-shaped `ToolResult` metadata with `exit`, `description`, `truncated`, `signal`, and preview output.
- Runtime smoke covers command output, cwd, inherited env, timeout metadata, output truncation, denied bash permission, and denied external-directory permission.

## Evidence

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Boundary

This is a Node-first, non-interactive shell tool, not the full upstream PTY system. It uses synchronous process execution to unblock deterministic session/tool lifecycle work. Long-lived PTY sessions, bus events, WebSocket controls, streaming metadata updates, and upstream's tree-sitter Bash/PowerShell scanner are follow-up work.

The command scanner is conservative and string-based. It catches common file-path commands and external cwd usage, but it should be replaced with the real tree-sitter/resource-backed scanner once `.wasm` resource handling is in place.

## genes-ts / Host Lesson

Node's `spawnSync` has overload-heavy TypeScript types. Keep the raw extern argument as `Dynamic` and expose a typed Haxe facade from `opencodehx.host.node.NodeProcess`; otherwise generated TypeScript can fail strict overload resolution even when the runtime call is valid.
