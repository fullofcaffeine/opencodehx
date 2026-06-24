# Effect Runtime Parity

**Beads:** `opencodehx-dov`, `opencodehx-1rt`

## Upstream Oracle

- `../opencode/packages/opencode/src/effect/observability.ts`
- `../opencode/packages/opencode/test/effect/observability.test.ts`
- `../opencode/packages/opencode/src/effect/run-service.ts`
- `../opencode/packages/opencode/test/effect/run-service.test.ts`

## What Landed

`opencodehx.effect.ObservabilityResource` ports the pure resource DTO behavior used by upstream observability setup:

- `OTEL_RESOURCE_ATTRIBUTES` is parsed as comma-separated `key=value` entries.
- Keys and values use JavaScript `decodeURIComponent` semantics.
- A malformed entry drops all env-provided resource attributes.
- Built-in OpenCode attributes are applied after env attributes, so env collisions cannot override `opencode.client` or `service.instance.id`.

`EffectSmoke.observabilityResource()` covers the upstream resource parser assertions with injected env/process metadata.

`opencodehx.effect.RuntimeMemo` and `RunServiceRuntime` cover the stable memo-map behavior from upstream `makeRuntime`: separately-created runtimes can depend on the same shared layer and see one initialized dependency. `EffectSmoke.runServiceMemoMap()` creates two runtime services over one memoized shared service, proves both return the same shared ID, and proves the dependency factory ran once.

## Boundary

This slice does not port the full Effect observability layer, OTLP logger, OpenTelemetry trace exporter, AppRuntime logger installation, Effect `ManagedRuntime`, `Layer`, `Context.Service`, or async `runPromise`/`runFork` APIs. Those remain under the broader Effect/runtime rows.
