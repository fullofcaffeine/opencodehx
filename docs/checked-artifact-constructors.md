# Checked Artifact Constructors

**Beads:** `opencodehx-8dx`, `opencodehx-zot`, `opencodehx-prt`

OpenCodeHX keeps user, config, plugin, model-emitted, and wire strings at runtime boundaries. Fixed source-authored references should use typed wrappers or macro-checked constructors when this repo owns a local catalog.

## Current Catalogs

| Artifact family | Checked surface | Boundary surface |
| --- | --- | --- |
| TUI plugin routes | `TuiRoutes.plugin("...")` checks built-in plugin routes against `TuiPluginRouteName`. | Dynamic route names from future plugin/runtime surfaces stay runtime data until their registry exists. |
| TUI keybind actions | `TuiKeybindActions.action("...")` checks built-in action IDs against `TuiKeybindActionName`. | User keymap/config strings stay permission/config boundary data. |
| Tool IDs | `KnownToolID` and `ToolIDs.known("...")` check source-authored fixed tool references. | Model-emitted, plugin, config, disabled-tool, and unknown-tool paths still flow through runtime `String` APIs. |
| Provider IDs | `KnownProviderID` and `ProviderIDs.known("...")` check built-in provider references in the registry and Haxe-owned smokes. TUI dialog fixtures use a TUI-local `TuiProviderIDs.known("...")` catalog to avoid pulling provider runtime code into the TSX scaffold. | Config-defined, plugin-defined, `models.dev`, missing-provider, and typo-suggestion cases stay dynamic provider IDs. |
| Server event types | `ServerEventType` and `ServerEventTypes.known("...")` check source-authored server/SSE event names. `ServerEventTypes.fromBoundary(...)` narrows SDK/SSE wire values. | Unknown future event names should be rejected or introduced into the catalog when the route/event owner lands. |
| Resource paths | `KnownResourcePath` and `ResourcePaths.known("...")` check Haxe-owned reads from copied resources. | Resource manifest contents are still decoded from generated JSON at runtime; build-script source paths remain JS harness work. |
| JS harness generated targets | `scripts/harness/paths.mjs` centralizes fixed package members, generated `dist`/`src-gen` entrypoints, generated TUI scaffold paths, copied resource targets, and generated runtime module imports used by JS harnesses and build scripts. | Temporary directories, packed tarball filenames, installed global roots, package-local `node_modules`, live server URLs, WebSocket URLs, and runtime-discovered package contents stay dynamic script data. |

`npm run macro:diagnostics` has negative fixtures for TUI keybind actions, tool IDs, provider IDs, TUI provider IDs, server event types, and resource paths.

## Deliberate Non-Catalogs

Model IDs are not globally cataloged yet. Built-in model strings, `models.dev` entries, config aliases, provider-specific upstream model IDs, and typo-suggestion tests share the same runtime lookup path, and a static catalog would drift quickly. Add provider-scoped model catalogs only when an owning slice has stable local model fixtures or generated models.dev pins.

Config keys remain schema/parser boundary data. Haxe source already narrows parsed JSON/JSONC/markdown into typed config records; raw config field names in decoders are compatibility keys, not source-authored command IDs.

Fixture, snapshot, generated-output, package-member, `dist/`, and `src-gen/` paths in JavaScript harnesses are not covered by Haxe macros. Fixed paths now go through `scripts/harness/paths.mjs` where practical. Paths whose values are discovered from `npm pack`, global install layout, temporary workspaces, host platform binaries, or live server state remain script-owned boundary data.

## Adding A New Catalog

1. Keep the raw string at the external boundary.
2. Add an enum abstract or typed wrapper for source-authored fixed values.
3. Add a macro constructor only when the call site benefits from literal authoring.
4. Add a negative fixture to `scripts/harness/macro-diagnostics.mjs`.
5. Document any skipped string family here with a boundary reason or a follow-up Bead.
