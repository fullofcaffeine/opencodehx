# OpenCode Source Inventory And Parity Matrix

**Bead:** `opencodehx-001`

## Summary

- Upstream source root: `../opencode/packages/opencode/src`
- Source files inventoried: 523
- Approximate source LOC: 99317
- Upstream test files inventoried: 187
- Full source matrix: `reference/opencode-source-parity-matrix.csv`
- Test priority matrix: `reference/opencode-test-priority-matrix.csv`

## Area Summary

| Area | Files | LOC | Runtime classes | Port priorities |
| --- | ---: | ---: | --- | --- |
| account | 5 | 773 | portable:5 | P2:5 |
| acp | 4 | 2155 | portable:4 | P2:4 |
| agent | 6 | 574 | portable:2; resource:4 | P2:6 |
| auth | 1 | 98 | portable:1 | P2:1 |
| bus | 3 | 241 | portable:3 | P2:3 |
| cli | 185 | 43459 | portable:89; node-host:8; bun-host:2; tsx:84; resource:2 | P1:185 |
| command | 3 | 358 | portable:1; resource:2 | P2:3 |
| config | 23 | 2087 | portable:23 | P0:23 |
| control-plane | 10 | 995 | portable:7; node-host:3 | P3:10 |
| effect | 14 | 1295 | portable:13; node-host:1 | P2:14 |
| env | 1 | 38 | portable:1 | P0:1 |
| file | 5 | 1457 | portable:5 | P0:5 |
| flag | 1 | 108 | portable:1 | P0:1 |
| format | 2 | 613 | portable:2 | P0:2 |
| git | 1 | 261 | portable:1 | P2:1 |
| global | 1 | 59 | portable:1 | P2:1 |
| id | 1 | 87 | portable:1 | P0:1 |
| ide | 1 | 74 | portable:1 | P2:1 |
| installation | 2 | 348 | portable:2 | P3:2 |
| lsp | 7 | 2899 | portable:6; node-host:1 | P2:7 |
| mcp | 4 | 1526 | portable:4 | P2:4 |
| npm | 2 | 294 | portable:2 | P2:2 |
| patch | 1 | 685 | portable:1 | P2:1 |
| permission | 4 | 533 | portable:4 | P1:4 |
| plugin | 9 | 2695 | portable:6; node-host:2; bun-host:1 | P2:9 |
| project | 7 | 987 | portable:7 | P2:7 |
| provider | 33 | 8052 | portable:32; node-host:1 | P1:33 |
| pty | 5 | 463 | node-host:2; bun-host:1; portable:2 | P2:5 |
| question | 2 | 247 | portable:2 | P2:2 |
| root | 6 | 343 | portable:6 | P2:6 |
| server | 38 | 5944 | bun-host:1; node-host:28; portable:9 | P2:38 |
| session | 37 | 9295 | portable:23; node-host:1; resource:13 | P0:19; P2:18 |
| share | 4 | 449 | portable:4 | P3:4 |
| shell | 1 | 111 | node-host:1 | P2:1 |
| skill | 2 | 406 | portable:2 | P2:2 |
| snapshot | 1 | 778 | portable:1 | P2:1 |
| storage | 8 | 995 | bun-host:1; node-host:1; portable:6 | P1:8 |
| sync | 4 | 490 | portable:4 | P3:4 |
| tool | 42 | 4506 | portable:41; node-host:1 | P1:42 |
| util | 36 | 1939 | portable:33; node-host:2; tsx:1 | P0:36 |
| worktree | 1 | 600 | portable:1 | P2:1 |

## Classification Rules

- **Area** is mostly the first source/test path segment, with `cli/tui` grouped as `tui` and `v2` grouped into `session`.
- **Runtime class** is heuristic: `.tsx` and Solid/OpenTUI imports are `tsx`; `.bun.*` and Bun APIs are `bun-host`; `.node.*` and Node built-ins are `node-host`; prompts/templates are `resource`; the rest starts as `portable`.
- **Extern needs** are non-relative import specifiers extracted from static and dynamic imports.
- **genes-ts risks** flag TSX, dynamic imports, Node built-ins, Bun APIs, Effect/Zod usage, streams, resource imports, and obvious TS unions.
- **Port priority** favors pure/config/file/session DTO foundations first, then tools/providers/storage/CLI, then server/protocol/TUI/plugin surfaces.

This is a first-pass planning matrix, not a semantic proof. Refine rows as each slice is ported and tested.
