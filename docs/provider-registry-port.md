# Provider Registry Port

**Bead:** `opencodehx-024`
**Upstream oracle:** `../opencode/packages/opencode/src/provider/provider.ts`, `schema.ts`, `models.ts`, `auth/index.ts`, `config/provider.ts`, `env/index.ts`, plus `../opencode/packages/opencode/test/provider/provider.test.ts` and `amazon-bedrock.test.ts`.

## Slice

This slice adds the first Haxe-owned provider registry:

- `opencodehx.provider.ProviderTypes` defines `ProviderID` and `ModelID` abstracts, typed provider/model/capability/cost/limit records, and the upstream `interleaved` union as `Bool | { field }`.
- `opencodehx.provider.ProviderRegistry` resolves providers from config, env, auth content, and Bedrock env/config/auth seams.
- Provider filters cover `disabled_providers`, `enabled_providers`, per-provider `whitelist`, and `blacklist`.
- Model lookup covers aliases, slash-containing model IDs, default model config, small-model priority, and missing-model errors.
- `FakeProvider` now uses the same typed provider/model records as the registry instead of local duplicate DTOs.

## Evidence

`ProviderSmoke` is the executable fixture for this slice. It covers:

- Anthropic env loading and config option overlays.
- Custom providers and custom model aliases.
- Provider and model filtering.
- Auth file-shaped API keys.
- Bedrock region, profile, endpoint-to-`baseURL`, env autoload, and bearer auth.
- The pre-existing credential-free fake provider transcript harness.

Run it with:

```bash
npm run smoke
```

`npm run build` also strict-checks the generated TypeScript.

## Haxe Modeling

Provider IDs and model IDs are Haxe abstracts over strings. This keeps upstream-compatible wire values while preventing accidental mixing at Haxe call sites.

Capabilities, costs, limits, headers, and provider/model maps are typed records or maps. `headers` lowers to `Record<string, string>` in generated TypeScript.

The upstream `interleaved` capability is not `Dynamic`: it is modeled as `EitherType<Bool, ProviderInterleavedConfig>`, which emits a TypeScript union.

`options` and `variants` remain open records because upstream models them as `Record<string, any>` provider-SDK passthrough data. Keep that openness localized: once a provider-specific option shape becomes stable and useful, add a provider facade or typedef rather than widening the whole registry.

Config, auth, and env inputs are still dynamic JSON/process boundaries. The registry normalizes them into typed provider/model records as soon as the current slice has enough schema knowledge. Further config-schema tightening belongs to `opencodehx-ajd`.

## Deferred Scope

This is not the full provider runtime:

- AI SDK dynamic loading, `getLanguageModel`, stream transforms, and provider-specific request options remain `opencodehx-025`.
- `models.dev` fetch/cache, GitLab model discovery, plugin provider hooks, OAuth flows, and auth persistence remain deferred to their owning provider/auth/plugin slices.
- Provider transform variants and completion mapping remain deferred until message/provider streaming is ported.

## genes-ts Notes

The Haxe model generates strict-checkable TypeScript, but the provider registry exposed output polish debt: repeated temporary declarations, `tmpN` names in larger object literals, and visible `StringMap.inst` access in generated user modules. Keep the Haxe source typed and clear; reduce these shapes into generic `../genes` fixtures instead of weakening the provider model.

Regular Genes' existing ES6 output path is a useful performance-oriented secondary profile. `../genes-vanilla` is the read-only reference for original Genes behavior; OpenCodeHX compiler work still lands in `../genes`, and idiomatic TypeScript remains the default output surface.
