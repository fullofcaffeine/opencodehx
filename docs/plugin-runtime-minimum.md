# Plugin Runtime Minimum Surface

**Bead:** `opencodehx-030`

## Upstream Oracles

- `../opencode/packages/opencode/test/plugin/shared.test.ts`
- `../opencode/packages/opencode/test/plugin/meta.test.ts`
- `../opencode/packages/opencode/test/plugin/loader-shared.test.ts`
- `../opencode/packages/opencode/test/plugin/trigger.test.ts`
- `../opencode/packages/opencode/test/plugin/install.test.ts`

## Current Surface

OpenCodeHX now has a dependency-free first plugin runtime seam. The port matrix now promotes exact evidence for `plugin/shared.test.ts`, `plugin/meta.test.ts`, `plugin/loader-shared.test.ts`, `plugin/trigger.test.ts`, the pure JWT/account-id helper part of `plugin/codex.test.ts`, the Cloudflare AI Gateway chat-params rule from `plugin/cloudflare.test.ts`, the GitHub Copilot plugin model merge/remap rules from `plugin/github-copilot-models.test.ts`, and the pure auth-override/config-hook isolation behavior from `plugin/auth-override.test.ts`; install/live auth/built-in provider/workspace plugin rows remain deferred.

- `opencodehx.plugin.PluginShared` covers upstream-style plugin spec parsing for plain, scoped, versioned, git URL, alias, and `npm:` protocol specs. It also resolves file plugin targets through the existing config path resolver, reads package metadata, resolves basic package entrypoints, resolves plugin IDs, and validates `oc-themes` entries.
- `opencodehx.plugin.PluginMeta` tracks file and npm plugin metadata in JSON: source, requested version, installed version, file modified time, fingerprint, load count, and first/same/updated states.
- `opencodehx.plugin.PluginRuntime` loads configured plugin origins through injected resolver/module-provider seams, preserving deterministic order. It applies the upstream server-plugin shape rules covered in the smoke: default V1 server plugins win over named legacy exports, file V1 plugins need an ID, V1 server+tui exports are rejected, identical legacy function exports dedupe, missing modules skip, and trigger hooks run sequentially.
- `opencodehx.plugin.PluginAuthHooks` covers typed auth method precedence: later hooks for the same `ProviderID` replace earlier built-in methods without using string-keyed maps.
- `opencodehx.plugin.PluginCodex` covers the pure Codex token helper seam: JWT payload parsing, malformed token rejection, root/nested/organization account-id extraction, and `id_token` before `access_token` precedence.
- `opencodehx.plugin.PluginCloudflare` covers the built-in Cloudflare AI Gateway request-parameter rule: `maxOutputTokens` becomes JavaScript `undefined` only for OpenAI reasoning models routed through `cloudflare-ai-gateway`.
- `opencodehx.plugin.PluginGithubCopilotModels` covers the built-in GitHub Copilot model hook rules: endpoint model merges preserve existing model capability overrides while new models default temperature support on, and fallback enterprise OAuth models are remapped to the Copilot enterprise host plus `@ai-sdk/github-copilot`.
- `opencodehx.smoke.PluginSmoke` proves parser cases, metadata state transitions, injected npm package metadata, V1 rejection rules, legacy dedupe, default V1 precedence, `experimental.chat.system.transform` invocation, typed auth-method override precedence, Codex JWT/account-id helper behavior, the four Cloudflare chat-param cases, and the GitHub Copilot model merge/remap cases.

## Boundaries

This is not live plugin package integration yet. Dynamic `import(...)`, `Npm.add`, install concurrency, compatibility semver checks, built-in auth plugin OAuth/device/browser flows, live auth loader/callback persistence, live Cloudflare auth/provider override integration, live GitHub Copilot model fetch/auth/header hooks, TUI plugin entrypoints, workspace adaptors, browser-like plugin APIs, and event bus subscriptions remain follow-up work.

The runtime uses injected module providers so the first parity evidence is deterministic and credential-free. JSON package metadata and persisted metadata are narrowed at the boundary; arbitrary plugin hook input remains `genes.ts.Unknown` until the owning hook schemas are ported.
