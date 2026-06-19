# Provider Registry Port

**Beads:** `opencodehx-024`, `opencodehx-025`, `opencodehx-nrh`
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
- `ProviderRegistry.fromModelsDevProvider` normalizes the upstream `models.dev` provider/model payload shape into the typed provider registry model, including experimental modes.
- `ProviderModelsDev` adds the first models.dev fetch/cache seam with injected fetcher support, Node cache file selection, forced refresh, local file override, snapshot fallback, and typed catalog output.
- `CopilotChatMessages` ports the first typed OpenAI-compatible GitHub Copilot prompt-message conversion slice.
- `CopilotChatCompletion` ports pure GitHub Copilot response metadata, non-stream response content assembly, finish-reason, response-usage, stream-final-usage, and prediction-token metadata normalization.
- `CopilotChatStream` ports the pure GitHub Copilot chat stream state machine over typed parsed chunks, before the actual SSE/Web Stream adapter lands.
- `CopilotChatTools` ports pure GitHub Copilot request-body tool formatting for OpenAI-compatible function tools and tool-choice modes.

## Evidence

`ProviderSmoke` is the executable fixture for this slice. It covers:

- Anthropic env loading and config option overlays.
- Custom providers and custom model aliases.
- Provider and model filtering.
- Auth file-shaped API keys.
- Bedrock region, profile, endpoint-to-`baseURL`, env autoload, and bearer auth.
- `models.dev` provider normalization for provider API inheritance, required defaults, reasoning variants, experimental mode naming, body-key camel casing, mode cost overrides, and preservation of base over-200k pricing.
- `models.dev` fetch/cache orchestration for custom source URLs, user-agent headers, cache writes and reads, fresh-cache refresh skips, forced refresh, local `modelsPath` override, snapshot fallback, and disabled-fetch empty catalog behavior.
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
- Message transforms for interleaved reasoning content, empty/unsupported attachment replacement, Anthropic/Bedrock empty-content filtering, Anthropic assistant tool-tail splitting, cache placement/skipping, Claude/Mistral tool-call ID normalization, Mistral assistant bridge insertion, and provider-option key remapping.

`CopilotChatMessagesSmoke` covers representative upstream `provider/copilot/convert-to-copilot-messages.test.ts` cases:

- System/user text flattening.
- Image data, `Uint8Array`, and remote URL parts.
- Assistant text, tool calls, and tool results.
- Denied tool-execution fallback.
- Approval-response skipping.
- Reasoning text and opaque reasoning metadata.
- Full conversation ordering.

`CopilotChatCompletionSmoke` covers the first pure upstream `provider/copilot/copilot-chat-model.test.ts` helper behavior:

- Response metadata from OpenAI-compatible response/chunk bodies.
- Non-stream text, reasoning, and tool-call content assembly with Copilot reasoning metadata.
- OpenAI-compatible finish-reason mapping.
- `doGenerate` response-usage shape.
- `doStream` final usage and no-cache accounting.
- Raw stream usage nulls when usage is absent.
- Accepted/rejected prediction-token metadata.

`CopilotChatStreamSmoke` covers representative upstream stream-state behavior from `provider/copilot/copilot-chat-model.test.ts`:

- `stream-start` and first-chunk response metadata.
- Text start/delta/end ordering.
- Reasoning start/delta/end ordering.
- Reasoning-to-tool transition ordering.
- Reasoning opaque metadata on reasoning, tool-call, and late finish events.
- Tool input start/delta/end and tool-call assembly from parsed argument chunks.
- Final finish reason, token usage/no-cache accounting, and accepted/rejected prediction metadata.
- Error chunks and invalid chunk diagnostics for duplicate reasoning opaque, missing tool IDs, and missing tool names.

`CopilotChatToolsSmoke` covers representative upstream request-body formatting from `provider/copilot/copilot-chat-model.test.ts`:

- Empty tool arrays become absent `tools` and `tool_choice`.
- Function tools emit the OpenAI-compatible function/tool schema shape.
- Provider tools emit unsupported warnings and are filtered from the OpenAI-compatible request tools.
- Auto, none, required, and named tool-choice modes map to the upstream OpenAI-compatible shape.

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

`ProviderModelsDev.parse` keeps `Dynamic` and a single cast inside the JSON decoder boundary because Haxe's `Json.parse` and `Reflect.field` cannot refine runtime objects into structural typedefs. The boundary validates the consumed models.dev shape first, then returns a typed `ModelsDevCatalog` to the registry.

The AI SDK boundary is intentionally small. `AiSdk.hx` uses raw `@:ts.type(...)` only for SDK-owned types such as `LanguageModelV3`, OpenAI-compatible factory settings, `Tool`, `JSONSchema7`, and provider stream parts; the app-facing surface is the typed `AiSdkProvider` event/result model. `genes.ts.Undefinable<T>` is used for SDK options that require JavaScript `undefined` rather than Haxe `null`.

## Deferred Scope

This is not the full provider runtime:

- More bundled providers, non-bundled dynamic provider installation/loading, deeper provider-specific request options, plugin provider hooks, and the full Copilot live SSE/Web Stream provider adapter remain `opencodehx-nrh`.
- GitLab model discovery, OAuth flows, and auth persistence remain deferred to their owning provider/auth/plugin slices.
- Completion mapping into the full async session loop remains deferred until the provider/session integration slice owns live stream consumption.

## genes-ts Notes

The Haxe model generates strict-checkable TypeScript, but the provider registry exposed output polish debt: repeated temporary declarations, `tmpN` names in larger object literals, and visible `StringMap.inst` access in generated user modules. Keep the Haxe source typed and clear; reduce these shapes into generic `../genes` fixtures instead of weakening the provider model.

The models.dev runtime-options path exposed a generic optional-field narrowing hole for Haxe conditions such as `field == null || field == "" ? fallback : field`. The fix landed in `../genes` commit `bed806092d198f075a62d7da52f1d90b53feb860` (`genes-o41`), teaching `genes-ts` to carry optional-field non-null facts through boolean `&&`/`||` branches without OpenCodeHX-specific knowledge.

The Copilot usage-mapping helpers exposed generated cast noise after null-guarded locals used for `genes.ts.Undefinable<T>` output. The fix landed in `../genes` commit `b96af41741e6ea2b0e36c5a50005e38af4aebeb3` (`genes-9lz`), teaching `genes-ts` to emit direct TypeScript locals after stable null guards instead of `Register.unsafeCast<T>(value)`.

The Copilot request-body tool formatter exposed two generic object-context gaps: call arguments such as `Array<T>.push({ ... })` lost the expected anonymous record type, and `EitherType<String, { @:native("function") ... }>` object arms lost native-field metadata after abstract following. The fix landed in `../genes` commit `5b93d285bbf3325c5647c16863af02c7e7fd1c45` (`genes-izm`), teaching `genes-ts` to propagate callee parameter context and inspect `EitherType` parameters before the abstract erases to `Dynamic`.

The same formatter also exposed a generic raw-template gap: `genes.ts.Undefinable<T>.orNull()` lowers through `js.Syntax.code("{0} ?? null", value)`, and placeholder emission was bypassing Genes' native-aware field-name path. The fix landed in `../genes` commit `909b9cfae0c8bf917cd93e5644d22c48718a3c51` (`genes-1im`), teaching `genes-ts` raw syntax templates to emit placeholder values through Genes' raw JS value path so `@:native` anonymous fields remain correct without adding TS-only casts to raw snippets.

Regular Genes' existing ES6 output path is a useful performance-oriented secondary profile. `../genes-vanilla` is the read-only reference for original Genes behavior; OpenCodeHX compiler work still lands in `../genes`, and idiomatic TypeScript remains the default output surface.
