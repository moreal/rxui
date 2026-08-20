# M10 10k-row Data Grid measurements

## Scope and method

This report compares the same checked seven-operation trace under:

1. full collection recomputation plus the keyed region;
2. explicit checked `ListDelta` propagation;
3. the initial hybrid cost model (`maxDeltaEdits = 256`).

The trace creates 10,000 rows, updates row 5000, removes every tenth row,
swaps rows 1 and 9998, filters to odd rows, sorts descending, and selects row
7777. Every measurement follows native and browser correctness checks that all
three strategies finish with 5,000 visible rows, first key 9999, last key 3,
and selected key 7777. Timings are observations, not CI thresholds or theorems.

Measurements were taken on 2026-08-21 on an Apple M1 Max (10 cores, 64 GB),
macOS 26.6.2, Lean 4.33.0/Lake 5.0.0, Node 22.23.2, pnpm 10.33.0, and the
Playwright 1.62.1 bundled Chromium. Other applications were active, so only
large, repeatable differences should be interpreted.

## Native reference and cost-model measurements

Command: `lake exe leanrx_grid_bench -- 20`, five consecutive samples after a
build. The latency column is the median elapsed time divided by twenty traces.
Allocation units are deterministic model units: one projected row allocation or
delta payload row, not allocator-profiler bytes.

| Strategy | Median per trace | Allocation units | Derived evaluations | Region visits | Delta edits | Delta modes | Resets |
|---|---:|---:|---:|---:|---:|---:|---:|
| Full | 67.5 ms | 53,000 | 56,000 | 53,000 | 0 | 0 | 0 |
| Delta | 65.0 ms | 20,002 | 1,007 | 35,004 | 1,007 | 7 | 3 |
| Hybrid | 67.7 ms | 29,002 | 28,004 | 29,004 | 4 | 3 | 0 |

The work model predicts much less allocation and derived work for explicit
delta, but the native wall-clock samples are effectively tied. List traversal,
delta construction/checking, and the deliberately small sample obscure the
modeled reduction. This is a negative result: model counts alone do not establish
throughput superiority.

`./scripts/check_grid_bench.sh` repeats the correctness baseline with three
iterations and locks all deterministic work counts while accepting any
non-negative elapsed time.

## Chromium measurements

Command: focused generated-app Playwright test with `--repeat-each=5`. Each cell
below is the median operation latency in milliseconds. It includes browser event
dispatch, generated update/propagation, DOM work, and Playwright observation.

| Strategy | Mount | Update one | Remove 1,000 | Swap two | Filter odd | Sort desc | Select |
|---|---:|---:|---:|---:|---:|---:|---:|
| Full | 17.9 | 65.6 | 37.9 | 85.8 | 38.6 | 52.9 | 21.2 |
| Delta | 13.7 | 33.0 | 43.6 | 25.7 | 39.0 | 49.6 | 18.8 |
| Hybrid | 12.2 | 32.8 | 40.9 | 26.9 | 32.7 | 47.0 | 16.3 |

Delta/hybrid materially improve the one-row update and two-row reorder in this
fixture. Explicit delta loses to full recomputation on the 1,000-row removal and
does not improve filtering. The hybrid avoids emitting a large delta batch for
those resets and has the best median in four of the six post-mount operations,
but the result is one machine/browser/workload and is not a universal cost law.

The final copied work snapshots were identical across all five samples:

| Strategy | Generated derived evaluations | Standard DOM writes | Region mounts | Region updates | Region moves | Region disposals | Full resets | Accepted delta ops | Validation visits |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Full | 83,000 | 43,006 | 10,000 | 43,000 | 23,997 | 5,000 | — | — | — |
| Delta | 89,000 | 10,008 | 10,000 | 10,002 | 15,001 | 5,000 | 3 | 1,006 | 21,006 |
| Hybrid | 98,000 | 19,008 | 10,000 | 19,002 | 15,001 | 5,000 | 4 | 4 | 29,004 |

The generated derived counters are higher for delta/hybrid even though DOM writes
fall by about 77%/56%. That disagreement with the native cost model is retained,
not normalized away: the specialized emitter performs validation/projection work
that the initial model does not capture.

`performance.memory.usedJSHeapSize` reported a median 12.7 MB after each
strategy (the first sample reported 11.9 MB for all three). This process-wide,
coarsely reported value did not distinguish strategies and is insufficient as an
allocation profiler. The deterministic allocation units above are therefore
labeled modeled work, not measured JavaScript heap allocation.

## Size and build cost

The deterministic ABI-7 artifacts measured:

| Artifact | Bytes |
|---|---:|
| Readable generated module (all three exports) | 14,854 |
| Compact generated module (all three exports) | 12,593 |
| Manifest | 611 |
| Native expected oracle | 141 |
| DOM + region + disposer hosts | 14,365 |
| Compact module plus shared hosts | 26,958 |

The module intentionally contains all variants, so these numbers do not isolate
the marginal bytes of one strategy. A clean no-hardlinks checkout built the
`leanrx_data_grid_js` executable in 11.68 s real time (126 jobs); subsequent
artifact generation took 2.01 s real time. These are machine-specific samples,
not build-time budgets.

## Complexity and API burden

The experiment adds 140 lines of pure delta semantics/proof-carrying planning,
189 net lines to the region host (162 to 351), 345 lines of grid reference/cost
model, 70 lines of the sealed component contract, and 865 lines in the
specialized typed-JavaScript-AST emitter. Native, fake-DOM, artifact, browser,
and benchmark regressions add about 620 lines. The public opt-in surface exposes
the closed `ListDelta` vocabulary and proof-carrying `PlannedDeltas`; ordinary
static scalar/component applications do not need either.

This is significant complexity for a workload-dependent benefit. `mapDelta`,
`filterDelta`, `keyBy`, `sortDelta`, folds, and joins still lack the individual
correctness connections required by the architecture.

## Decision

Structural delta remains an opt-in experimental library. It is valuable for
small keyed updates/reorders and proves that checked delta application can reduce
DOM work, but the evidence does not justify making it a first-class language or
default compiler feature. Full keyed reconciliation remains the default; a
specialized backend may opt into delta/hybrid only with an explicit checked cost
model and benchmark evidence.

Promotion requires at least multiple browsers/device classes and collection
shapes, an actual JavaScript allocation profile, per-strategy/tree-shaken bundle
comparison, proofs for composed delta operators, and a cost model that predicts
the generated validation/projection work seen here.
