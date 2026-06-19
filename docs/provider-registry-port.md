# Provider Registry Port

**Beads:** `opencodehx-024`, `opencodehx-025`
**Upstream oracle:** `../opencode/packages/opencode/src/provider/provider.ts`, `schema.ts`, `models.ts`, `auth/index.ts`, `config/provider.ts`, `env/index.ts`, plus `../opencode/packages/opencode/test/provider/provider.test.ts` and `amazon-bedrock.test.ts`.

## Slice

This slice adds the first Haxe-owned provider registry:

- `opencodehx.provider.ProviderTypes` defines `ProviderID` and `ModelID` abstracts, typed provider/model/capability/cost/limit records, and the upstream `interleaved` union as `Bool | { field }`.
- `opencodehx.provider.ProviderRegistry` resolves providers from config, env, auth content, and Bedrock env/config/auth seams.
- Provider filters cover `disabled_providers`, `enabled_providers`, per-provider `whitelist`, and `blacklist`.
- Model lookup covers aliases, slash-containing model IDs, default model config, small-model priority, and missing-model errors.
- `FakeProvider` now uses the same typed provider/model records as the registry instead of local duplicate DTOs.
- `opencodehx.provider.AiSdkProvider` adds the first AI SDK `streamText` facade through narrow Haxe externs.
- `opencodehx.smoke.AiSdkProviderSmoke` exercises credential-free AI SDK streaming via `ai/test` `MockLanguageModelV3`.
- `opencodehx.provider.AiSdkLanguageLoader` resolves the first real bundled SDK factory path through `@ai-sdk/openai-compatible`.
- `opencodehx.provider.ProviderTransform` ports the first pure provider request-option transforms from upstream.

## Evidence

`ProviderSmoke` is the executable fixture for this slice. It covers:

- Anthropic env loading and config option overlays.
- Custom providers and custom model aliases.
- Provider and model filtering.
- Auth file-shaped API keys.
- Bedrock region, profile, endpoint-to-`baseURL`, env autoload, and bearer auth.
- The pre-existing credential-free fake provider transcript harness.

`AiSdkProviderSmoke` is the executable fixture for the first AI SDK runtime path. It covers:

- Text deltas through `streamText`.
- Tool-call and tool-result events through `ai.tool(...)` and JSON Schema input.
- Stream error callback handling and final error finish reason.
- Abort propagation through `AbortController`.
- AI SDK usage aggregation and finish reason typing.
- A credential-free OpenAI-compatible provider factory path from Haxe config through `ProviderRegistry.resolveLanguage`, including alias-to-upstream model ID selection and `LanguageModelV3` metadata.

`ProviderTransformSmoke` covers the first upstream `provider/transform.test.ts` subset:

- Request defaults for cache keys, OpenAI/Azure `store`, Z.ai/Zhipu thinking, Google thinking config, GPT-5 text verbosity, and Gateway caching.
- AI SDK `providerOptions` routing for package keys, Gateway upstream slugs, Gateway routing-option splits, and the Amazon-to-Bedrock slug override.
- Temperature, `topP`, `topK`, max-output-token helpers now shared by session compaction, and reasoning variant generation across the main upstream provider families.
- Gemini JSON Schema sanitization for missing array item schemas, nested arrays, combiner nodes, non-object cleanup, required filtering, enum stringification, and non-Gemini no-op behavior.

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

The AI SDK boundary is intentionally small. `AiSdk.hx` uses raw `@:ts.type(...)` only for SDK-owned types such as `LanguageModelV3`, OpenAI-compatible factory settings, `Tool`, `JSONSchema7`, and provider stream parts; the app-facing surface is the typed `AiSdkProvider` event/result model. `genes.ts.Undefinable<T>` is used for SDK options that require JavaScript `undefined` rather than Haxe `null`.

## Deferred Scope

This is not the full provider runtime:

- More bundled providers, non-bundled dynamic provider installation/loading, deeper provider-specific request options, `models.dev` fetch/cache, plugin provider hooks, and provider message/completion transforms remain `opencodehx-nrh`.
- GitLab model discovery, OAuth flows, and auth persistence remain deferred to their owning provider/auth/plugin slices.
- Completion mapping into the full async session loop remains deferred until the provider/session integration slice owns live stream consumption.

## genes-ts Notes

The Haxe model generates strict-checkable TypeScript, but the provider registry exposed output polish debt: repeated temporary declarations, `tmpN` names in larger object literals, and visible `StringMap.inst` access in generated user modules. Keep the Haxe source typed and clear; reduce these shapes into generic `../genes` fixtures instead of weakening the provider model.

Regular Genes' existing ES6 output path is a useful performance-oriented secondary profile. `../genes-vanilla` is the read-only reference for original Genes behavior; OpenCodeHX compiler work still lands in `../genes`, and idiomatic TypeScript remains the default output surface.
