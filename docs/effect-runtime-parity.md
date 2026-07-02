# Effect Runtime Parity

**Beads:** `opencodehx-dov`, `opencodehx-1rt`, `opencodehx-n3n`, `opencodehx-4kc`, `opencodehx-vqu0`, `opencodehx-bfo1`

## Upstream Oracle

- `../opencode/packages/opencode/src/effect/observability.ts`
- `../opencode/packages/opencode/test/effect/observability.test.ts`
- `../opencode/packages/opencode/src/effect/app-runtime.ts`
- `../opencode/packages/opencode/src/effect/bridge.ts`
- `../opencode/packages/opencode/test/effect/app-runtime-logger.test.ts`
- `../opencode/packages/opencode/src/effect/cross-spawn-spawner.ts`
- `../opencode/packages/opencode/test/effect/cross-spawn-spawner.test.ts`
- `../opencode/packages/opencode/src/effect/run-service.ts`
- `../opencode/packages/opencode/test/effect/run-service.test.ts`
- `../opencode/packages/opencode/test/effect/instance-state.test.ts`
- `../opencode/packages/opencode/test/effect/runner.test.ts`

## What Landed

`opencodehx.effect.ObservabilityResource` ports the pure resource DTO behavior used by upstream observability setup:

- `OTEL_RESOURCE_ATTRIBUTES` is parsed as comma-separated `key=value` entries.
- Keys and values use JavaScript `decodeURIComponent` semantics.
- A malformed entry drops all env-provided resource attributes.
- Built-in OpenCode attributes are applied after env attributes, so env collisions cannot override `opencode.client` or `service.instance.id`.

`EffectSmoke.observabilityResource()` covers the upstream resource parser assertions with injected env/process metadata.

`opencodehx.effect.AppRuntimeLoggerRuntime` covers the stable logger/context facts from upstream AppRuntime setup without pulling in the full Effect service graph:

- `Observability.layer`-style setup replaces the default logger with the OpenCode Effect logger.
- `RunServiceRuntime` sees the same logger replacement as AppRuntime.
- instance directory context can be attached to an AppRuntime-style run; and
- a captured bridge preserves the logger set and instance directory across a Promise async boundary.

`EffectSmoke.appRuntimeLogger()` and `EffectSmoke.appRuntimeLoggerBridge()` cover those cases.

`opencodehx.util.ProcessRuntime` now also exposes the typed process-handle features needed for the first upstream cross-spawn spawner evidence:

- stdout, stderr, and combined `all` capture;
- zero and nonzero exit codes;
- cwd and env options;
- stdin input;
- kill and running-state observation;
- invalid cwd and missing command failure; and
- Windows shell and `.cmd` script behavior when the smoke runs on Windows.

`EffectSmoke.crossSpawnSpawner()` covers those cases while reusing the Node host seam from `util/process.test.ts`.

`opencodehx.effect.RuntimeMemo` and `RunServiceRuntime` cover the stable memo-map behavior from upstream `makeRuntime`: separately-created runtimes can depend on the same shared layer and see one initialized dependency. `EffectSmoke.runServiceMemoMap()` creates two runtime services over one memoized shared service, proves both return the same shared ID, and proves the dependency factory ran once. `EffectSmoke.runServiceAsync()` covers Promise-backed service execution and proves async calls reuse the initialized service.

`opencodehx.effect.InstanceStateRuntime` covers the stable instance-state lifecycle: values are cached per instance directory, isolated across directories, invalidated on `InstanceRuntime.reload`, and disposed on `InstanceRuntime.disposeAll`.

`opencodehx.effect.RunnerRuntime` covers the stable Runner concurrency contract without pulling in full Effect fiber machinery:

- the first `ensureRunning` work runs and returns its result;
- failures propagate and reset the runner to idle;
- concurrent callers share the active run;
- concurrent callers all receive the same active-run failure;
- replacement work passed while busy is ignored;
- completed runners can run again;
- idle cancellation is a no-op;
- cancellation settles all queued callers, either with `RunnerCancelledError` or the configured interrupt fallback; and
- stale work completions after cancellation are ignored so a later run can start cleanly, including when a replacement run starts before the interrupt fallback settles.

`EffectSmoke.runner()` covers those cases as async smoke evidence.

## Boundary

This slice does not port the full Effect observability layer, OTLP logger, OpenTelemetry trace exporter, Effect `ManagedRuntime`, `Layer`, `Context.Service`, `runFork`/`runCallback`, real `Logger.CurrentLoggers`, real Effect `Scope`/`Fiber` interruption for Runner, full `ChildProcessSpawner` service integration, Effect `Stream` byte chunks, scoped child cleanup, multi-stage `pipeTo` helpers, ALS-backed `InstanceRef`, or high-contention instance context propagation. Those remain under the broader Effect/runtime rows.
