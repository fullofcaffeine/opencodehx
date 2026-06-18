# Effect Compatibility Strategy

**Bead:** `opencodehx-009`  
**Goal:** compile and port OpenCode's Effect-heavy control flow without reimplementing Effect before parity.

## Position

OpenCodeHX should treat upstream `effect` as an ecosystem dependency at first. The Haxe source should not clone Effect's runtime, scheduler, layer model, stream implementation, or schema system during the early parity line.

The initial path is:

1. Bind narrow Effect APIs as externs.
2. Wrap repeated patterns in `opencodehx.fx`.
3. Keep OpenCode behavior as the oracle.
4. Replace or Haxe-native-ify selected patterns only after parity evidence exists.

## Initial Compile Proof

The first extern/facade pair is:

- `opencodehx.externs.effect.EffectApi`
- `opencodehx.fx.Task`

`EffectApi` binds `Effect.succeed(...)` and `Effect.fail(...)` from the npm `effect` package. `Task<T>` is the first Haxe-facing wrapper. It intentionally stores the raw Effect runtime value as `Dynamic` until we know the exact subset needed by config/session/provider slices.

The runtime smoke constructs a `Task.succeed(...)` value so generated TypeScript imports `effect` and exercises the dependency under NodeNext.

The npm `effect@4.0.0-beta.48` declaration tree currently fails full third-party library checking under `tsc` with a missing internal `SchemaErrorTypeId` name. OpenCodeHX keeps generated/user source strict, but `tsconfig.json` uses `skipLibCheck: true` until the Effect dependency or TypeScript compiler path changes. Track this as dependency compatibility debt, not a `genes-ts` compiler limitation.

## Near-Term Facade Shape

Use `opencodehx.fx` names for Haxe-facing code:

| Haxe facade | Upstream concept | First use |
| --- | --- | --- |
| `Task<T>` | `Effect.Effect<T, E, R>` narrowed over time | config/session async computations |
| `Stream<T>` | `Stream.Stream<T, E, R>` | provider token streams and tool streams |
| `Service<T>` | `Context.Service` | config/session/provider service access |
| `Layer<T>` | `Layer.Layer` | dependency assembly and test/runtime setup |
| `Scope` | Effect scope/finalizer semantics | host resources and session lifecycle |

Do not expose upstream Effect's full type parameter set everywhere until a real slice needs it. Start with ergonomic Haxe wrappers and add type precision where it removes concrete bugs or generated TS ambiguity.

## Boundary Debt

The initial `Task<T>` implementation uses `Dynamic` for the raw Effect runtime value. This is accepted boundary debt, tracked in `docs/genes-ts-limitation-ledger.md`, because:

- upstream Effect's type surface is large,
- the first parity slices need compile/runtime interop before full type modeling,
- premature full externs would be noisy and likely wrong,
- the wrapper isolates the dynamic value from application-facing Haxe code.

Tighten this boundary when `opencodehx-011` (config), `opencodehx-013` (message/session DTOs), or provider/session processor work shows the required Effect subset.

## Rules

- Prefer `Task<T>` and future `opencodehx.fx` wrappers in OpenCodeHX code.
- Keep raw `Dynamic` inside extern/facade modules unless a task explicitly accepts a dynamic interop boundary.
- Add minimal `../genes` repros for generated TS quality problems.
- Use upstream tests and golden behavior to decide whether a native Haxe replacement is safe.
