# Bash Shell Seam

**Bead:** `opencodehx-018`  
**Upstream oracle:** `../opencode/packages/opencode/src/tool/bash.ts`, `../opencode/packages/opencode/test/pty/pty-session.test.ts`

## Slice

This seam started as the first Node-backed shell execution slice and now includes the parser-backed permission scanner follow-up:

- `opencodehx.host.node.NodeProcess` wraps `node:child_process.spawnSync` behind a small Haxe-facing API.
- `bash` is registered as a builtin tool.
- `BashTool` validates `command`, `description`, optional `timeout`, and optional `workdir`.
- `BashCommandScanner` preloads `web-tree-sitter` plus Bash/PowerShell WASM grammars and extracts upstream-style command patterns and file path arguments.
- `NodeProcess` now mirrors upstream `Shell.preferred`/`Shell.acceptable` selection semantics for blacklisted shells, Git Bash normalization, PowerShell fallback, `COMSPEC`, and POSIX/Darwin fallback behavior.
- Tool permission requests are emitted for parsed `bash` command execution and for external working directories/path arguments.
- Output is normalized into upstream-shaped `ToolResult` metadata with `exit`, `description`, `truncated`, `signal`, and preview output.
- Runtime smoke covers command output, cwd, inherited env, timeout metadata, output truncation, denied bash permission, denied external-directory permission, tree-sitter multi-command prompts, nested command path extraction, shell-selection parity fixtures, and deterministic Windows PowerShell scanner cases for drive-relative paths, `$PWD`, `$PSHOME`, FileSystem providers, and conditionals.

## Evidence

Gates used for this slice:

```bash
npm run build
npm run smoke
```

## Boundary

This is still a Node-first, non-interactive shell tool. It uses synchronous process execution to unblock deterministic session/tool lifecycle work. Long-lived PTY lifecycle is now represented separately in `docs/pty-runtime.md`; streaming bash metadata updates and the full upstream Effect process runner remain follow-up work.

The Windows shell-selection and PowerShell path fixtures are deterministic and run on every host by threading an explicit platform through the scanner/selector helpers. Native Windows process execution still needs a real Windows CI or manual smoke pass before we claim runtime parity for `pwsh`, `powershell`, `cmd.exe`, and Git Bash process spawning.

The command scanner uses tree-sitter after `BashCommandScanner.preload()` has loaded the WASM assets copied by `scripts/build/copy-resources.mjs`. A conservative string fallback remains only for call sites that run before preload; production runtime startup should initialize the scanner before executing bash tools.

## genes-ts / Host Lesson

Node's `spawnSync` has overload-heavy TypeScript types. Keep the raw extern argument as `Dynamic` and expose a typed Haxe facade from `opencodehx.host.node.NodeProcess`; otherwise generated TypeScript can fail strict overload resolution even when the runtime call is valid.

Tree-sitter's `Tree` and `Node` exports are type-only from generated TS's point of view. Model them as narrow `@:ts.type` abstracts at the extern boundary and return typed scanner DTOs to application code; do not let parser-owned dynamic objects leak into tool logic.
