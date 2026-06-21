# Provider Registry Port

**Beads:** `opencodehx-024`, `opencodehx-025`, `opencodehx-nrh`, `opencodehx-hup`
**Upstream oracle:** `../opencode/packages/opencode/src/provider/provider.ts`, `schema.ts`, `models.ts`, `auth/index.ts`, `config/provider.ts`, `env/index.ts`, plus `../opencode/packages/opencode/test/provider/provider.test.ts` and `amazon-bedrock.test.ts`.

## Slice

This slice adds the first Haxe-owned provider registry:

- `opencodehx.provider.ProviderTypes` defines `ProviderID` and `ModelID` abstracts, typed provider/model/capability/cost/limit records, and the upstream `interleaved` union as `Bool | { field }`.
- `opencodehx.provider.ProviderRegistry` resolves providers from config, env, typed auth entries, and Bedrock env/config/auth seams.
- Provider filters cover `disabled_providers`, `enabled_providers`, per-provider `whitelist`, and `blacklist`.
- Model lookup covers aliases, slash-containing model IDs, default model config, Anthropic/OpenCode/GitHub Copilot small-model priority, Bedrock small-model cross-region precedence, and missing-model errors.
- `FakeProvider` now uses the same typed provider/model records as the registry instead of local duplicate DTOs.
- `opencodehx.provider.AiSdkProvider` adds the first AI SDK `streamText` facade through narrow Haxe externs.
- `opencodehx.smoke.AiSdkProviderSmoke` exercises credential-free AI SDK streaming via `ai/test` `MockLanguageModelV3`.
- `opencodehx.provider.AiSdkLanguageLoader` resolves the first real bundled SDK factory paths through `@ai-sdk/openai-compatible`, `@ai-sdk/openai`, `@ai-sdk/xai`, `@ai-sdk/azure`, `@ai-sdk/google`, `@ai-sdk/google-vertex`, `@ai-sdk/google-vertex/anthropic`, `@ai-sdk/anthropic`, `@ai-sdk/amazon-bedrock`, `@ai-sdk/mistral`, `@ai-sdk/groq`, `@ai-sdk/cohere`, `@ai-sdk/perplexity`, `@openrouter/ai-sdk-provider`, `@ai-sdk/deepinfra`, `@ai-sdk/cerebras`, `@ai-sdk/gateway`, `@ai-sdk/togetherai`, `@ai-sdk/vercel`, `@ai-sdk/alibaba`, and `gitlab-ai-provider`.
- `opencodehx.provider.BedrockLanguageLoader` ports Bedrock cross-region inference-profile model ID selection before SDK `languageModel(...)` calls.
- `opencodehx.provider.ProviderTransform` ports the first pure provider request-option transforms from upstream.
- `ProviderRegistry.fromModelsDevProvider` normalizes the upstream `models.dev` provider/model payload shape into the typed provider registry model, including experimental modes.
- `ProviderModelsDev` adds the first models.dev fetch/cache seam with injected fetcher support, Node cache file selection, forced refresh, local file override, snapshot fallback, and typed catalog output.
- `ProviderRegistry` covers the first Cloudflare AI Gateway loading seam: required account/gateway/token env or auth credentials autoload the provider, and config metadata options survive the provider merge.
- `opencodehx.auth.AuthStore` owns the Node auth storage seam for `OPENCODE_AUTH_CONTENT` and XDG data `auth.json`, validating upstream `api`, `oauth`, and `wellknown` entry shapes before provider/config code sees them.
- `CloudflareAiGatewayLoader` wires the real `ai-gateway-provider` package into the typed AI SDK loader surface, forwarding account/gateway credentials plus cache/log/metadata options through narrow externs before calling `gateway.chat(...)`; the smoke also validates the SDK's generated `cf-aig-*` request headers.
- `ProviderRegistry` ports upstream OpenCode provider paid-model gating: public access keeps free models and a public API key, while env/auth/config API keys keep paid models visible.
- `opencodehx.plugin.PluginConfigHooks` models the upstream `server().config(cfg)` hook order for provider loading: typed plugin hooks mutate the live config before `ProviderRegistry` reads `cfg.provider`, `enabled_providers`, or `disabled_providers`.
- `CopilotChatMessages` ports the first typed OpenAI-compatible GitHub Copilot prompt-message conversion slice.
- `CopilotChatCompletion` ports pure GitHub Copilot response metadata, non-stream response content assembly, finish-reason, response-usage, stream-final-usage, and prediction-token metadata normalization.
- `CopilotChatRequest` ports pure GitHub Copilot request argument shaping for OpenAI-compatible chat calls.
- `CopilotOpenAICompatibleProvider` ports the pure GitHub Copilot/OpenAI-compatible provider factory settings: default/base URL handling, provider name/kind IDs, request URL construction, header merging, authorization defaults, and AI SDK user-agent suffixing.
- `CopilotChatSseDecoder` ports the first pure SSE `data:` decoder layer for GitHub Copilot chat streams, turning event-source response text into typed parsed/raw chunks before the Web Stream adapter lands.
- `CopilotChatStreamAdapter` ports the first typed Web `ReadableStream<Uint8Array>` response-body reader layer and connects live response text to the SSE decoder and stream state machine.
- `CopilotChatStream` ports the pure GitHub Copilot chat stream state machine over typed parsed chunks, before the actual SSE/Web Stream adapter lands.
- `CopilotChatTools` ports pure GitHub Copilot request-body tool formatting for OpenAI-compatible function tools and tool-choice modes.
- `CopilotChatLanguageModel` ports the first Haxe-owned GitHub Copilot/OpenAI-compatible chat model class surface over the typed helpers.
- `CopilotAiSdkLanguageModel` adapts the Haxe-owned chat model to the exact AI SDK `LanguageModelV3` call/result/stream surface without production casts.
- `CopilotResponsesLanguageModel` ports the first Haxe-owned GitHub Copilot/OpenAI Responses `LanguageModelV3` path for `gpt-5` non-mini models, including typed request-body construction, non-stream result mapping, and core SSE event mapping.
- `CopilotLanguageLoader` wires configured `@ai-sdk/github-copilot` models through the upstream `shouldUseCopilotResponsesApi` rule: chat models use `ProviderRegistry.resolveCopilotChat`, while `gpt-5` non-mini models use `ProviderRegistry.resolveCopilotResponses`.
- `ProviderOptionAccess` centralizes typed reads from open provider SDK options, keeping `Record<string, any>`-style boundary access localized and narrowed before loaders consume it.

## Evidence

`ProviderSmoke` is the executable fixture for this slice. It covers:

- Anthropic env loading, config option overlays, nested provider option deep merge, multiple configured providers loading together, env-source precedence when config also augments the provider, fallback env variable lookup, and single-vs-multiple env key capture.
- Custom providers, brand-new providers, custom model aliases, provider-name defaults, provider `api` to model API URL inheritance, provider `baseURL` options, new model SDK/API inheritance from existing providers, Google Vertex proxy `baseURL` preservation, per-model provider API/package overrides, model defaults, custom cost/cache values, tool-call capability defaults/overrides, text/image modality defaults and overrides, default zero limits, and model headers.
- Provider and model filtering, including empty enabled lists, enabled-plus-disabled precedence, and combined whitelist/blacklist behavior.
- Reasoning model variant generation plus config customization, database-model final-pass filtering, custom reasoning model variants, per-variant disable, all-variant disable, and stripping `disabled` from kept variant options.
- User-facing `ModelNotFound` suggestions for misspelled provider IDs and model IDs.
- Provider lookup, model sort, and closest-model helpers, including missing providers, no-match queries, and ordered multi-term matching.
- Auth file-shaped API keys.
- Provider config hooks from plugins, including a plugin-added provider/model, hook reapplication across registry rebuilds, and plugin-owned enabled/disabled provider filters.
- Anthropic env autoload, default beta headers, no-network `@ai-sdk/anthropic` `languageModel(...)` resolution, and the current SDK's `LanguageModelV2` descriptor shape.
- Bedrock region, profile, endpoint-to-`baseURL`, env autoload, bearer auth, web-identity autoload, small-model global/regional/unprefixed selection, OpenCode/GitHub Copilot small-model priority, cross-region model-prefix detection, and no-network `@ai-sdk/amazon-bedrock` `languageModel(...)` resolution.
- Cloudflare AI Gateway env autoload for `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_GATEWAY_ID`, and `CLOUDFLARE_API_TOKEN`, preservation of configured `options.metadata`, `cf-aig-metadata` header fallback parsing, cache/log option request-header generation, and no-network AI SDK factory/model resolution through `ai-gateway-provider`.
- GitLab Duo registry loading for `GITLAB_TOKEN`, config `options.apiKey`, API-auth keys, OAuth access-token auth shape, `GITLAB_INSTANCE_URL`, default/custom AI Gateway headers, feature flags, and static `duo-chat-*` models.
- OpenCode provider public/paid model gating: no key hides paid models, while `OPENCODE_API_KEY`, auth content, or config `options.apiKey` keeps paid models visible.
- `models.dev` provider normalization for provider API inheritance, required defaults, reasoning variants, experimental mode naming, body-key camel casing, mode cost overrides, and preservation of base over-200k pricing.
- `models.dev` fetch/cache orchestration for custom source URLs, user-agent headers, cache writes and reads, fresh-cache refresh skips, forced refresh, local `modelsPath` override, snapshot fallback, and disabled-fetch empty catalog behavior.
- The pre-existing credential-free fake provider transcript harness.

`AiSdkProviderSmoke` is the executable fixture for the first AI SDK runtime path. It covers:

- Text deltas through `streamText`.
- Tool-call and tool-result events through `ai.tool(...)` and JSON Schema input.
- Registry-derived tool schema advertisement through AI SDK tools without `execute`, preserving model-visible schemas while keeping actual tool execution under the session registry/permission path.
- Stream error callback handling and final error finish reason.
- Abort propagation through `AbortController`.
- AI SDK usage aggregation and finish reason typing.
- Credential-free provider factory paths from Haxe config through `ProviderRegistry.resolveLanguage`, including OpenAI-compatible alias-to-upstream model ID selection and Anthropic/Bedrock no-network factory/model selection.
- Official OpenAI-family no-network factory/model selection through `@ai-sdk/openai`, `@ai-sdk/xai`, and `@ai-sdk/azure`, including responses-vs-chat selection, OpenAI organization/project settings, xAI's narrower settings shape, Azure resource/API-version/deployment URL settings, and provider/model header merging.
- Google-family no-network factory/model selection through `@ai-sdk/google`, `@ai-sdk/google-vertex`, and `@ai-sdk/google-vertex/anthropic`, including Google API-key/baseURL/name forwarding, Vertex project/location/API-key settings, Vertex Anthropic's narrower no-API-key settings shape, and the current V3 descriptor providers.
- Simple bundled-provider no-network factory/model selection through `@ai-sdk/mistral`, `@ai-sdk/groq`, `@ai-sdk/cohere`, `@ai-sdk/perplexity`, `@openrouter/ai-sdk-provider`, `@ai-sdk/deepinfra`, `@ai-sdk/cerebras`, `@ai-sdk/gateway`, `@ai-sdk/togetherai`, `@ai-sdk/vercel`, and `@ai-sdk/alibaba`, forwarding only the stable `baseURL`, `apiKey`, and header settings until typed fetch, ID-generation, metadata-cache, app-attribution, embedding/video endpoint, and provider-specific request-option seams own the remaining SDK hooks.
- GitLab no-network factory/model selection through `gitlab-ai-provider`, including static Duo chat model IDs, instance URL, API key, feature flags, and AI Gateway headers narrowed from registry options into the SDK settings bridge.
- Cloudflare AI Gateway no-network factory/model selection, including account ID, gateway ID, API key, cache key, cache TTL, cache skipping, log collection, opaque metadata forwarding, `cf-aig-metadata` fallback parsing, and SDK-generated request headers for the stable Cloudflare options.
- Typed SDK loader failure paths for unsupported bundled packages, missing `api`/`baseURL`, and missing `chat(...)`/`responses(...)` methods.

`ProviderTransformSmoke` covers the first upstream `provider/transform.test.ts` subset:

- Request defaults for cache keys, OpenAI/Azure `store`, Z.ai/Zhipu thinking, Google thinking config, GPT-5 text verbosity, Gateway caching, OpenRouter/LLM Gateway usage, Baseten/OpenCode template-thinking, Anthropic Kimi thinking budgets, Alibaba reasoning enablement, OpenCode GPT-5 encrypted reasoning includes, and Venice prompt caching.
- AI SDK `providerOptions` routing for package keys, Gateway upstream slugs, Gateway routing-option splits, and the Amazon-to-Bedrock slug override.
- Temperature, `topP`, `topK`, max-output-token cap/fallback helpers now shared by session compaction, upstream `smallOptions` defaults, GPT-5 verbosity/reasoning defaults, Google/Vertex thinkingConfig gating, and reasoning variant generation across the main upstream provider families, including generic reasoning-effort provider families, DeepSeek/Minimax/GLM exclusions, SAP provider routing, Grok mini special cases, Gateway Google/generic routing, Gateway Anthropic dot-format IDs, Azure/OpenAI exclusions, OpenAI release-date effort expansion, and newer Copilot GPT-5/codex `xhigh` behavior.
- Gemini JSON Schema sanitization for missing array item schemas, nested arrays, mixed object/array structures, combiner nodes, non-object cleanup, required filtering, enum stringification, and non-Gemini no-op behavior.
- Message transforms for interleaved reasoning content, empty/unsupported attachment replacement plus valid image preservation, Anthropic/Bedrock empty-content filtering and non-Anthropic filtering avoidance, Anthropic and Vertex Anthropic assistant tool-tail splitting plus valid-order preservation, cache placement/skipping including full non-gateway cache bundles, content-part cache placement, tool-approval cache fallback, Bedrock SDK/custom-profile, and Vertex Anthropic edges, OpenAI item-metadata preservation before provider request-body stripping including provider-ID keyed metadata, store=true, and non-OpenAI package guards, Claude/Mistral tool-call ID normalization, Mistral assistant bridge insertion, Azure identity-key preservation, and Azure/Copilot/Bedrock provider-option key remapping.

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

`CopilotChatRequestSmoke` covers representative upstream request-body shaping from `provider/copilot/copilot-chat-model.test.ts`:

- Model IDs, converted prompt messages, standard call settings, stop sequences, seed, and typed Copilot provider options.
- Streaming request bodies add `stream: true` and optional `stream_options.include_usage` while preserving the prepared chat args and warnings.
- `topK` unsupported warnings.
- Absent/text response formats omit `response_format`.
- JSON response formats emit `json_object`.
- Structured JSON Schema formats emit `json_schema`, preserve the schema payload, and default the schema name to `response`.
- Unsupported JSON Schema formats downgrade to `json_object` and emit the upstream unsupported `responseFormat` warning.
- Tool formatting and tool warnings inside the complete request args path.

`CopilotProviderFactorySmoke` covers representative upstream `provider/sdk/copilot/copilot-provider.ts` factory behavior:

- Default OpenAI-compatible base URL and provider name.
- One-trailing-slash base URL normalization and URL callback output.
- API-key `Authorization` defaults.
- User headers overriding defaults, header cloning before caller mutation, lower-case normalized header keys, and AI SDK user-agent suffixing.
- `languageModel` aliasing to chat models, plus separate chat/responses provider IDs.
- Empty `baseURL` validation.

`CopilotChatStreamSmoke` covers representative upstream stream-state behavior from `provider/copilot/copilot-chat-model.test.ts`:

- `stream-start` and first-chunk response metadata.
- Text start/delta/end ordering.
- Raw chunk passthrough ordering when `includeRawChunks` is enabled, and omission when disabled.
- Reasoning start/delta/end ordering.
- Reasoning-to-tool transition ordering.
- Reasoning opaque metadata on same-chunk content transitions, tool-call-only chunks, reasoning, tool-call, and late finish events.
- Tool input start/delta/end and multi-tool-call assembly from parsed argument chunks.
- Final finish reason, token usage/no-cache accounting, and accepted/rejected prediction metadata.
- Error chunks and invalid chunk diagnostics for duplicate reasoning opaque, missing tool IDs, and missing tool names.

`CopilotChatSseDecoderSmoke` covers the first typed SSE boundary before live Web Stream wiring:

- `data:` frame extraction, comment/unknown-field skipping, and `[DONE]` omission.
- Raw JSON preservation for `includeRawChunks` parity.
- Typed chunk decoding for response metadata, text deltas, usage details, and provider error frames.
- Invalid JSON, invalid `choices`, and invalid tool-call index diagnostics.

`CopilotChatStreamAdapterSmoke` covers the first typed Web stream adapter boundary:

- Constructing a Web `ReadableStream<Uint8Array>` fixture through Haxe externs, not raw `Syntax.code`.
- Reading `Response.body` through the narrow `WebStreams` facade.
- Incremental `TextDecoder` decoding into SSE response text.
- Feeding decoded chunks through `CopilotChatSseDecoder` and `CopilotChatStream.collectRaw`.
- Warning preservation and raw/text/metadata event ordering.

`CopilotChatToolsSmoke` covers representative upstream request-body formatting from `provider/copilot/copilot-chat-model.test.ts`:

- Empty tool arrays become absent `tools` and `tool_choice`.
- Function tools emit the OpenAI-compatible function/tool schema shape.
- Provider tools emit unsupported warnings and are filtered from the OpenAI-compatible request tools.
- Auto, none, required, and named tool-choice modes map to the upstream OpenAI-compatible shape.

`CopilotChatLanguageModelSmoke` covers the first upstream-like provider class behavior from `provider/copilot/copilot-chat-model.test.ts` and `provider/sdk/copilot/chat/openai-compatible-chat-language-model.ts`:

- Model class identity: `specificationVersion`, `modelId`, `provider`, provider-options name, structured-output support, and cloned `supportedUrls`.
- Class model ID winning over request-object model IDs, matching upstream's `this.modelId` request-body behavior.
- Class-level structured-output support turning JSON Schema response formats into `json_schema`.
- Class-level include-usage mode adding `stream_options.include_usage`.
- Delegation through the typed HTTP client for generate and stream paths, including call headers, raw chunk passthrough, and warning preservation.
- Exact AI SDK `LanguageModelV3CallOptions` adaptation for prompts, JSON response formats, tools, tool choice, provider options keyed as `copilot` and provider name, undefined HTTP headers, generated content, finish reason, and usage.
- Registry resolution for a configured `github-copilot` provider/model using upstream-style `@ai-sdk/github-copilot` metadata, including SDK model ID selection, Copilot base URL, API-key headers, model headers, and explicit structured-output opt-in.
- `ProviderRegistry.getLanguage` returning the Haxe-owned Copilot SDK facade as a structurally accepted `LanguageModelV3`.

`CopilotResponsesLanguageModelSmoke` covers the first upstream-like Responses behavior from `provider/provider.ts`, `provider/sdk/copilot/copilot-provider.ts`, and `provider/sdk/copilot/responses/openai-responses-language-model.ts`:

- Upstream `shouldUseCopilotResponsesApi` routing: `gpt-5.2` routes to `.responses`, while `gpt-5-mini` remains on `.chat`.
- Registry resolution and `ProviderRegistry.getLanguage` returning a Haxe-owned Responses model structurally accepted as `LanguageModelV3`.
- Responses request body shape for `/responses`: `model`, `input`, `max_output_tokens`, JSON Schema response formatting, function tools, required tool choice, call headers, and `stream: true`.
- Reasoning-model behavior for `gpt-5`: system messages become developer messages, `temperature` and `topP` are stripped with unsupported warnings, and Copilot provider options emit `reasoning.effort` / `reasoning.summary`.
- Non-stream Responses output mapping for reasoning, text, URL sources, function calls, finish reason, input cache accounting, and reasoning-token usage.
- Core SSE mapping for `response.created`, message start/text delta/message end, raw chunk passthrough, `response.completed`, and final SDK `finish`.

Run it with:

```bash
npm run smoke
```

`npm run build` also strict-checks the generated TypeScript.

## Haxe Modeling

Provider IDs and model IDs are Haxe abstracts over strings. This keeps upstream-compatible wire values while preventing accidental mixing at Haxe call sites.

Provider/model typo suggestions are generated with a small deterministic Haxe Levenshtein scorer. Upstream uses `fuzzysort`; the Haxe version preserves the top-three suggestion behavior shape without adding a JavaScript-only dependency to core registry logic, which keeps the code easier to retarget.

Capabilities, costs, limits, headers, and provider/model maps are typed records or maps. `headers` lowers to `Record<string, string>` in generated TypeScript.

The upstream `interleaved` capability is not `Dynamic`: it is modeled as `EitherType<Bool, ProviderInterleavedConfig>`, which emits a TypeScript union.

`options` and `variants` remain open records because upstream models them as `Record<string, any>` provider-SDK passthrough data. Keep that openness localized: once a provider-specific option shape becomes stable and useful, add a provider facade or typedef rather than widening the whole registry.

Variant config follows upstream's control-data rule: `disabled` decides whether a variant exists, but it is not forwarded as a provider option. The registry regenerates canonical variants for loaded models, merges config over them, removes disabled entries, and strips the `disabled` key from variants that remain enabled.

Config, auth, and env inputs are still dynamic JSON/process boundaries. The registry normalizes them into typed provider/model records as soon as the current slice has enough schema knowledge. Further config-schema tightening belongs to `opencodehx-ajd`.

`PluginConfigHooks` intentionally mutates `ConfigInfo` instead of returning an overlay. That matches upstream's `server().config(cfg)` contract: plugin config hooks run before provider loading and may add provider definitions or alter provider filters in place. The current Haxe hook type is narrow on purpose; real external plugin module loading, install compatibility, auth hooks, tool hooks, and event hooks belong to the plugin runtime slice.

`ProviderModelsDev.parse` keeps `Dynamic` and a single cast inside the JSON decoder boundary because Haxe's `Json.parse` and `Reflect.field` cannot refine runtime objects into structural typedefs. The boundary validates the consumed models.dev shape first, then returns a typed `ModelsDevCatalog` to the registry.

`ProviderOptionAccess` owns the registry's provider-option weak reads. Provider options intentionally remain open because SDKs/plugins own arbitrary keys; loaders must ask `ProviderOptionAccess` for typed strings, booleans, URLs, and headers rather than reading option fields directly.

`CopilotChatSseDecoder`, `CopilotResponsesResponseDecoder`, and `CopilotResponsesStream` have the same kind of contained boundary: `Json.parse` and `Reflect.field` are private to the decoder/stream mapper, every consumed field is shape-checked, and callers receive only typed chat chunks, typed Responses DTOs, or AI SDK stream parts. Generated `any` is expected only in those private decoder surfaces until a reusable typed JSON decoder exists.

`opencodehx.externs.web.WebStreams` owns the current Web stream extern gap. Haxe 4.3's `js.html.Response` does not expose the standard `body` property, so the structural cast is localized in `WebResponseStreams.body`; provider code consumes a typed `ReadableStream<Uint8Array>` reader.

The AI SDK boundary is intentionally named and narrow. `AiSdk.hx` uses raw `@:ts.type(...)` for SDK-owned declaration surfaces such as language models, call options, generated content, stream parts, provider metadata, OpenAI-compatible/OpenAI/xAI/Azure/Google/Vertex/Anthropic/Bedrock/Mistral/Groq/Cohere/Perplexity/OpenRouter/DeepInfra/Cerebras/Gateway/TogetherAI/Vercel/Alibaba/GitLab factory settings, `Tool`, and `JSONSchema7`. Each raw alias has a Haxe backing shape where OpenCodeHX needs to read or construct values, so production provider code can satisfy SDK contracts structurally instead of casting. Registry tools are converted to AI SDK tools without `execute`; this intentionally prevents `streamText` from auto-running tools before OpenCodeHX permission and tool-result recording can own the call. `genes.ts.Undefinable<T>` is used for SDK options that require JavaScript `undefined` rather than Haxe `null`.

Google Vertex headers are typed by the SDK as `Resolvable<Record<string, string | undefined>>`, not as a plain header map. `AiSdkLanguageLoader.optionalHeadersOrAbsent(...)` performs only a narrow map-to-map widening from already validated `DynamicAccess<String>` headers into that optional-value record; it does not inspect unknown provider payloads or accept promise/function headers until a typed host-auth/request seam owns them.

Do not assume every loaded AI SDK package returns `LanguageModelV3`. The public `ai.streamText` model input accepts both `LanguageModelV2` and `LanguageModelV3`, and the current `@ai-sdk/anthropic` factory returns a `LanguageModelV2` descriptor. OpenCodeHX therefore uses a V2/V3 union for loaded SDK models, while keeping V3-specific DTOs and a V3-only bridge for Haxe-owned adapters and SDKs such as Cloudflare AI Gateway that explicitly require V3 models.

Bedrock bearer auth is passed as an explicit SDK `apiKey` instead of mutating `process.env`. When no bearer token exists, `AwsCredentialProvider` is an opaque exact-TS bridge for the SDK's `credentialProvider` field, produced by `@aws-sdk/credential-providers` and never inspected in Haxe.

Bedrock small-model selection intentionally follows upstream `Provider.getSmallModel`, not the broader SDK inference-profile prefixing helper. It prefers `global.` matches first, then `us.` or `eu.` regional matches derived from `provider.options.region`, then an unprefixed match. Other Bedrock inference-profile prefixes such as `jp.`, `apac.`, and `au.` belong to `BedrockLanguageLoader.sdkModelID(...)` when resolving the concrete SDK model ID for a selected model.

Cloudflare AI Gateway now has a real no-network SDK loader seam. The provider autoloads only when the account ID, gateway ID, and API token are all available through env/auth/config, then `CloudflareAiGatewayLoader` forwards the stable options into `ai-gateway-provider` and calls `gateway.chat(...)` with the unified model. `metadata` remains opaque provider-owned passthrough data because the SDK accepts arbitrary scalar metadata; the Haxe boundary names that openness rather than widening the registry model. When explicit metadata is absent, the loader mirrors upstream by parsing `options.headers["cf-aig-metadata"]` and immediately boxing the parsed value back into the typed metadata bridge. The smoke validates the real package's `parseAiGatewayOptions(...)` output for cache, TTL, skip-cache, collect-log, and metadata headers rather than inventing unsupported SDK fields.

The installed `ai-gateway-provider` declarations do not currently expose upstream's custom user-agent header hook as a stable typed option. Do not smuggle it through raw `Syntax.code` or untyped object mutation; add a narrow extern/facade once the package surface or an explicit fetch-wrapper seam gives us a typed runtime contract.

OpenCode provider paid-model filtering intentionally mirrors upstream's listing behavior. Without a user-owned key, auth entry, or `OPENCODE_API_KEY`, the registry leaves only zero-cost models and sets `options.apiKey` to `"public"` so the free public API path remains target-shaped. Once any of those credential seams is present, paid models remain visible and the user-provided credentials flow through the same env/auth/config loading paths as other providers.

## Deferred Scope

This is not the full provider runtime:

- More bundled and non-bundled provider loading beyond the current OpenAI-compatible/OpenAI-family/Google-family/Anthropic/Bedrock/Mistral/Groq/Cohere/Perplexity/OpenRouter/DeepInfra/Cerebras/Gateway/TogetherAI/Vercel/Alibaba/GitLab/Cloudflare AI Gateway evidence, dynamic provider installation/loading, deeper provider-specific request options, live Bedrock credential-chain/signing evidence, Cloudflare user-agent parity once the SDK exposes a typed seam for it, and real external plugin runtime/loading hooks remain `opencodehx-nrh`. `venice-ai-sdk-provider@1.1.19` currently peers AI SDK v5, so loading it under this AI SDK v6 tree is deferred until a compatible package or compatibility seam exists.
- Deeper Copilot Responses parity remains provider-runtime scope: provider-executed tool argument schemas, richer annotations/logprobs, image/code/file-search payload details, and live session-loop consumption need broader upstream fixtures before they should be treated as complete.
- GitLab live workflow model discovery, `gitlab-ai-provider` model-class routing, OAuth browser/login flows, and auth persistence remain deferred to their owning provider/auth/plugin slices.
- Completion mapping into the full async session loop remains deferred until the provider/session integration slice owns live stream consumption.

## genes-ts Notes

The Haxe model generates strict-checkable TypeScript, but the provider registry exposed output polish debt: repeated temporary declarations, `tmpN` names in larger object literals, and visible `StringMap.inst` access in generated user modules. Keep the Haxe source typed and clear; reduce these shapes into generic `../genes` fixtures instead of weakening the provider model.

The models.dev runtime-options path exposed a generic optional-field narrowing hole for Haxe conditions such as `field == null || field == "" ? fallback : field`. The fix landed in `../genes` commit `bed806092d198f075a62d7da52f1d90b53feb860` (`genes-o41`), teaching `genes-ts` to carry optional-field non-null facts through boolean `&&`/`||` branches without OpenCodeHX-specific knowledge.

The Bedrock small-model fixture exposed a generic emitted-local naming bug: inline-expanded Haxe helpers such as `Map.set(key, value)` can introduce ordinary locals with the same source name but different types in one TypeScript function. The fix landed in `../genes` commit `8acd1061fb633ea99a2c78c0267cbec436bef6ff` (`genes-t55`), teaching `genes-ts` to allocate emitted local names by typed `TVar.id` within each function/lexical block and suffix real collisions such as `value_1`.

The Cloudflare AI Gateway smoke exposed a generic TypeScript precedence bug around `genes.ts.Undefinable<T>.orNull()`: generated `value ?? null != null` is parsed as `value ?? (null != null)`, not `(value ?? null) != null`. The fix landed in `../genes` commit `ab862272e1813d44393fa5e8bc059a8fb7d67298` (`genes-20r`), teaching `genes-ts` to parenthesize nullish-coalescing operands in null comparisons without adding OpenCodeHX-specific source workarounds.

The Copilot usage-mapping helpers exposed generated cast noise after null-guarded locals used for `genes.ts.Undefinable<T>` output. The fix landed in `../genes` commit `b96af41741e6ea2b0e36c5a50005e38af4aebeb3` (`genes-9lz`), teaching `genes-ts` to emit direct TypeScript locals after stable null guards instead of `Register.unsafeCast<T>(value)`.

The Copilot request-body tool formatter exposed two generic object-context gaps: call arguments such as `Array<T>.push({ ... })` lost the expected anonymous record type, and `EitherType<String, { @:native("function") ... }>` object arms lost native-field metadata after abstract following. The fix landed in `../genes` commit `5b93d285bbf3325c5647c16863af02c7e7fd1c45` (`genes-izm`), teaching `genes-ts` to propagate callee parameter context and inspect `EitherType` parameters before the abstract erases to `Dynamic`.

The same formatter also exposed a generic raw-template gap: `genes.ts.Undefinable<T>.orNull()` lowers through `js.Syntax.code("{0} ?? null", value)`, and placeholder emission was bypassing Genes' native-aware field-name path. The fix landed in `../genes` commit `909b9cfae0c8bf917cd93e5644d22c48718a3c51` (`genes-1im`), teaching `genes-ts` raw syntax templates to emit placeholder values through Genes' raw JS value path so `@:native` anonymous fields remain correct without adding TS-only casts to raw snippets.

AI SDK model method selection exposed a useful Haxe modeling rule: use closed enum abstracts for closed runtime domains. `AiSdkModelMethod` intentionally has `to String` but not `from String`, because OpenCodeHX chooses among `languageModel`, `chat`, and `responses` internally. That lets `genes-ts` emit `"chat" | "languageModel" | "responses"` in the resolution record, locals, and `loadModel` parameter. If an enum abstract keeps `from String`, `genes-ts` correctly treats it as open and emits plain `string`.

The AI SDK method-selection slice also exposed the generic enum-abstract widening bug fixed in `../genes` commit `ea54cb1251877e2f408a56cbfc9d2d4598e526ae` (`genes-w74`). Closed enum abstracts now preserve literal unions through typedef fields, class fields, nested object fields, and locals initialized from cached calls/fields. Keep the Haxe source honest: close the abstract when the domain is closed, keep it open when arbitrary provider/runtime values are accepted.

The Copilot provider factory stays type-safe and cast-free, but it shows a generated-output polish opportunity: `using StringTools` helpers such as `endsWith` still emit runtime helper calls instead of native TypeScript string methods. Keep the Haxe source readable; reduce this into a generic `genes-ts` fixture if it starts obscuring high-risk generated modules.

Regular Genes' existing ES6 output path is a useful performance-oriented secondary profile. `../genes-vanilla` is the read-only reference for original Genes behavior; OpenCodeHX compiler work still lands in `../genes`, and idiomatic TypeScript remains the default output surface.
