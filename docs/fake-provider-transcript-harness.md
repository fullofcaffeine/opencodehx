# Fake Provider Transcript Harness

**Bead:** `opencodehx-020`  
**Upstream oracle:** `../opencode/packages/opencode/test/fake/provider.ts`, `../opencode/packages/opencode/test/session/llm.test.ts`, and the Message V2 shapes in `../opencode/packages/opencode/src/session/message-v2.ts`

## Slice

This slice adds a credential-free provider fixture and transcript comparison harness:

- `opencodehx.provider.FakeProvider` mirrors the upstream test provider's default provider/model IDs, capability flags, model limits, and zero-cost shape.
- `opencodehx.harness.TranscriptHarness` emits a deterministic one-turn user/assistant transcript using the Haxe Message V2 codec.
- `node dist/index.js --transcript-fixture` prints the OpenCodeHX transcript JSON without running the normal smoke suite.
- `node dist/index.js run --format json --model openai/gpt-5.2 "Say hello from the fixture."` now emits the same transcript through the headless run scaffold.
- `scripts/harness/upstream-fake-provider-oracle.mjs` emits the upstream-shaped oracle transcript.
- `scripts/harness/transcript-parity.mjs` compares the upstream oracle, OpenCodeHX output, and `fixtures/transcripts/one-turn.golden.json`.

Run it with:

```bash
npm run transcript:parity
```

## Evidence

Gates used for this slice:

```bash
npm run build
npm run smoke
node scripts/harness/transcript-parity.mjs
```

`ProviderSmoke` also validates the generated transcript can be parsed back through `MessageCodec`.

## Boundary

OpenCodeHX does not have the headless session processor yet, so the upstream side is an upstream-shaped oracle script rather than the real `opencode run` flow. That is deliberate: it gives the next session slice a stable credential-free target while keeping this bead limited to provider and transcript mechanics.

`opencodehx-021` added the OpenCodeHX `run --format json` side of the comparison. The upstream side is still an oracle script; replace or augment it with a real upstream command runner once a stable upstream fake-provider run path is available.

## Haxe Modeling Lesson

Provider info/model records are precise typedefs instead of `Dynamic`, and `opencodehx-024` moved keyed provider/model maps into typed `Map<String, ProviderModel>` records shared with the provider registry. The transcript itself is built from typed `WithParts` messages, then encoded into a typed `SessionTranscript` envelope with only the serialized Message V2 records kept as `genes.ts.Unknown`.
