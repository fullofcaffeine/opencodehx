# Performance And UX Benchmark

**Bead:** `opencodehx-040`

OpenCodeHX now has a repeatable local benchmark harness:

```sh
npm run benchmark:parity
```

The command runs `npm run build`, verifies the TUI scaffold, then executes `scripts/harness/performance-benchmark.mjs`. The harness writes the current machine-local JSON result to `.artifacts/benchmarks/performance-ux-benchmark.json`.

## Current Run

Recorded on 2026-06-23 with:

- Node `v20.19.3`
- Bun `1.3.14`
- platform `darwin arm64`
- upstream OpenCode commit `69b7f3b8db82c3ab9dacd72d715a57d375de18e4`
- upstream OpenCode version `1.14.20`
- 7 measured iterations after 1 warmup

| Surface | Baseline | Median | p95 | Reading |
| --- | --- | ---: | ---: | --- |
| Upstream-shaped transcript oracle | fixture process | 28.33 ms | 29.59 ms | Deterministic JSON oracle builder, not full CLI runtime. |
| OpenCodeHX transcript fixture | `node dist/index.js --transcript-fixture` | 492.87 ms | 549.91 ms | Includes generated Node process startup and module load. |
| OpenCodeHX cold start help | `node dist/index.js --help` | 481.07 ms | 523.48 ms | Current generated CLI startup baseline. |
| OpenCodeHX fake-provider CLI | `node dist/index.js run ...` | 481.50 ms | 517.66 ms | Current headless fake-provider user path. |
| OpenCodeHX tool overhead | in-process write/read/edit/apply_patch fixture | 0.96 ms | 1.66 ms | Tool dispatch and filesystem work after modules are loaded. |
| OpenCodeHX TUI scaffold entry | Bun/OpenTUI scaffold entry | 453.00 ms | 471.04 ms | Measures scaffold process startup through `tui-scaffold:ok`. |

## Upstream Runtime Probe

The sibling upstream checkout could not provide a full runtime timing on this machine:

- `../opencode/packages/opencode/bin/opencode --help` fails from the source checkout because the package-local launcher is CommonJS-shaped but executes under the package's ESM scope.
- `bun run --conditions=browser ./src/index.ts --help` fails because the sibling checkout is missing current upstream workspace dependencies, starting with `effect/unstable/http`.

Because of that, this slice does not claim a native upstream CLI performance comparison. The only upstream timing in the current report is the existing upstream-shaped transcript oracle. A future refresh can replace this limitation with a real installed upstream binary or a fully bootstrapped upstream source checkout.

## Budgets

These are provisional local budgets for detecting drift in OpenCodeHX until a runnable upstream performance baseline is available:

| Surface | p95 budget | Current p95 | Status |
| --- | ---: | ---: | --- |
| Transcript fixture process | 750 ms | 549.91 ms | within budget |
| CLI cold start help | 750 ms | 523.48 ms | within budget |
| Fake-provider CLI run | 750 ms | 517.66 ms | within budget |
| Tool overhead fixture | 5 ms | 1.66 ms | within budget |
| TUI scaffold entry | 750 ms | 471.04 ms | within budget |

No regression Bead was created from this run. The upstream CLI runtime gap is accepted for this slice because the benchmark now records the failed probes explicitly and keeps the current OpenCodeHX budgets reproducible.

## Maintenance

- Keep benchmark results out of git; `.artifacts/` is ignored because timings are machine-local.
- Rerun `npm run benchmark:parity` before closing future performance-sensitive Beads.
- If a measured p95 exceeds its budget, either create a Bead with the affected surface and artifact path, or update this report with a concrete rationale for accepting the new baseline.
- Once a real upstream binary or fully bootstrapped source command is available, add it to `scripts/harness/performance-benchmark.mjs` and replace the upstream-runtime limitation above with actual comparative results.
