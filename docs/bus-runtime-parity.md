# Bus Runtime Parity

OpenCodeHX currently covers the callback-facing subset of upstream OpenCode's bus behavior.

`opencodehx.bus.BusRuntime` provides:

- typed event definitions by wire type string
- synchronous `publish`
- typed `subscribe` with event-type filtering
- `subscribeAll` for heterogenous event observation
- idempotent unsubscribe
- multiple subscribers per event type
- copied history snapshots
- portable scope-keyed bus instances
- scope isolation by caller-provided instance key
- disposal that publishes `instance.disposed` to wildcard subscribers before clearing listeners

`opencodehx.smoke.BusSmoke` is the executable evidence for the callback cases from:

- `../opencode/packages/opencode/test/bus/bus.test.ts`
- `../opencode/packages/opencode/test/bus/bus-integration.test.ts`

Remaining scope:

- Effect-native stream delivery in `bus/bus-effect.test.ts`
- full upstream `Instance.provide` service-context wiring beyond the portable scope-keyed bus registry
