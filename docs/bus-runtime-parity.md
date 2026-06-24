# Bus Runtime Parity

OpenCodeHX currently covers the callback-facing and stream-shaped subsets of upstream OpenCode's bus behavior.

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

`opencodehx.bus.BusStreamRuntime` is a small stream-shaped adapter over the same bus. It lets Haxe fixtures exercise the upstream Effect-native `Stream.runForEach(bus.subscribe(...))` contract without pulling the full Effect service graph into the first bus slice.

`opencodehx.smoke.BusSmoke` is the executable evidence for the callback cases from:

- `../opencode/packages/opencode/test/bus/bus.test.ts`
- `../opencode/packages/opencode/test/bus/bus-integration.test.ts`
- observable stream delivery from `../opencode/packages/opencode/test/bus/bus-effect.test.ts`

Remaining scope:

- full upstream Effect `Layer`, `Deferred`, scoped fiber, and `Instance.provide` service-context wiring beyond the portable scope-keyed bus registry
