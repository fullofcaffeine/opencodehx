# Effect Runtime Parity

**Bead:** `opencodehx-dov`

## Upstream Oracle

- `../opencode/packages/opencode/src/effect/observability.ts`
- `../opencode/packages/opencode/test/effect/observability.test.ts`

## What Landed

`opencodehx.effect.ObservabilityResource` ports the pure resource DTO behavior used by upstream observability setup:

- `OTEL_RESOURCE_ATTRIBUTES` is parsed as comma-separated `key=value` entries.
- Keys and values use JavaScript `decodeURIComponent` semantics.
- A malformed entry drops all env-provided resource attributes.
- Built-in OpenCode attributes are applied after env attributes, so env collisions cannot override `opencode.client` or `service.instance.id`.

`EffectSmoke.observabilityResource()` covers the upstream resource parser assertions with injected env/process metadata.

## Boundary

This slice does not port the full Effect observability layer, OTLP logger, OpenTelemetry trace exporter, or AppRuntime logger installation. Those remain under the broader Effect/runtime rows.
