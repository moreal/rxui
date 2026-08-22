# M10 10k-row Data Grid measurements

## Scope and method

This report compares the same checked seven-operation trace under:

1. full collection recomputation plus the keyed region;
2. explicit checked `ListDelta` propagation;
3. the initial hybrid cost model (`maxDeltaEdits = 256`).

The trace starts from the checked empty state, creates 10,000 rows, updates row
5000, removes every tenth row, swaps rows 1 and 9998, filters to odd rows, sorts
by key descending, and selects row 7777. Native and browser gates compare the
complete final 5,000-row ordered projection, including every key, text value,
and selection bit. It begins with key 9999 and ends with key 1. Intermediate
browser assertions also lock each operation's defining effect. Timings are
observations, not CI thresholds or theorems.

Measurements were taken on 2026-08-21 on an Apple M1 Max (10 cores, 64 GB),
macOS 26.6.2, Lean 4.33.0/Lake 5.0.0, Node 22.23.2, pnpm 10.33.0, and the
Playwright 1.62.1 bundled Chromium. Other applications were active, so only
large, repeatable differences should be interpreted.

## Exact reproduction commands

From a checkout with the pinned browser dependencies already installed:

```sh
for sample in 1 2 3 4 5; do
  lake exe leanrx_grid_bench -- 20
done
./scripts/check_grid_bench.sh

grid_report_dir="$(mktemp -d)"
lake exe leanrx_data_grid_js -- "$grid_report_dir/dist"
LEANRX_GRID_DIST="$grid_report_dir/dist" corepack pnpm exec playwright test Test/browser/grid.spec.mjs --repeat-each=6 --reporter=line
wc -c "$grid_report_dir"/dist/*
```

The six-repeat browser gate rotates full/delta/hybrid execution order so every
strategy occupies each position twice. Each
operation latency is measured synchronously inside the page around native
`button.click()`. Playwright correctness assertions run after the timed click.
Mount timing covers generated mount from the checked empty state and is separate
from the measured Create action.

For the clean build sample, a local no-hardlinks clone was used:

```sh
clean_report_dir="$(mktemp -d)"
git clone --no-hardlinks . "$clean_report_dir/repo"
cd "$clean_report_dir/repo"
/usr/bin/time -p lake build leanrx_data_grid_js
/usr/bin/time -p lake exe leanrx_data_grid_js -- "$clean_report_dir/dist"
```

## Native reference and cost-model measurements

`lake exe leanrx_grid_bench -- 20` was run five consecutive times after a build.
The latency column is the median elapsed time divided by twenty traces.
Allocation units are deterministic model units: one projected-row allocation or
delta payload row, not allocator-profiler bytes.

| Strategy | Median per trace | Allocation units | Derived work units | Region visits | Delta edits | Delta modes | Resets |
|---|---:|---:|---:|---:|---:|---:|---:|
| Full | 83.8 ms | 53,000 | 56,000 | 53,000 | 0 | 0 | 0 |
| Delta | 81.1 ms | 20,002 | 1,007 | 35,004 | 1,007 | 7 | 3 |
| Hybrid | 81.7 ms | 29,002 | 28,004 | 29,004 | 4 | 3 | 0 |

The model predicts much less allocation and derived work for explicit delta,
but native wall-clock samples are effectively tied. List traversal, delta
construction/checking, and the deliberately small sample obscure the modeled
reduction. This is a negative result: model counts alone do not establish
throughput superiority. `./scripts/check_grid_bench.sh` repeats the correctness
baseline with three iterations and locks deterministic counts while accepting
any non-negative elapsed time.

## Chromium latency and allocation observations

The table contains the median of six position-balanced samples in milliseconds:

| Strategy | Mount empty | Create 10k | Update one | Remove 1,000 | Swap two | Filter odd | Sort desc | Select |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Full | 0.3 | 18.1 | 5.3 | 6.1 | 12.7 | 7.1 | 7.1 | 2.9 |
| Delta | 0.4 | 16.8 | 1.1 | 9.4 | 0.8 | 7.9 | 7.4 | 0.4 |
| Hybrid | 0.4 | 17.0 | 0.9 | 6.9 | 0.7 | 7.1 | 7.3 | 0.4 |

Delta/hybrid materially improve the one-row update, two-row reorder, and
selection in this fixture. Explicit delta loses to full recomputation on the
1,000-row removal and does not improve filtering or sorting. The result is one
machine/browser/workload, not a universal cost law.

Chromium's sampling heap profiler ran across the seven operations and their
browser-side correctness observations with a 32 KiB sampling interval. Median
sampled allocation bytes were 2,103,032 full, 2,165,948 delta, and 2,234,426
hybrid. These are real sampled V8 allocations, but they are statistical and
include assertion work; they are not an exact allocator counter or CI threshold.
`performance.memory.usedJSHeapSize` was usually about 10 MB but reported roughly
40–47 MB for all strategies in some repetitions. That process-wide value is retained
as non-discriminating evidence rather than presented as per-strategy memory.

## Deterministic generated work

The browser gate locks these exact copied snapshots for the seven-operation
trace:

| Strategy | Standard derived evals | Standard changed derived | Standard sink evals | Standard DOM writes | Region mounts | Region updates | Region placements/moves | Region disposals | Full resets | Accepted delta ops | Validation units |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Full | 7 | 7 | 43,007 | 40,009 | 10,000 | 43,000 | 15,000 | 5,000 | — | — | — |
| Delta | 7 | 7 | 10,009 | 40,009 | 10,000 | 10,002 | 15,000 | 5,000 | 3 | 1,007 | 21,007 |
| Hybrid | 7 | 7 | 19,009 | 40,009 | 10,000 | 19,002 | 15,000 | 5,000 | 4 | 4 | 29,004 |

The separate Grid-specific snapshot records projection visits, key-search
visits, and removal-scan visits respectively:

| Strategy | Projection visits | Key-search visits | Removal-scan visits |
|---|---:|---:|---:|
| Full | 65,000 | 37,000 | 0 |
| Delta | 28,000 | 70,000 | 10,000 |
| Hybrid | 37,000 | 70,000 | 10,000 |

Standard transaction depth finishes at zero. Slot 3 counts one reference-style
projection evaluation per committed operation in this defining trace; structural
loop work stays in the separate snapshot. Slot 5 counts row-region sink-bundle
evaluations plus status sinks. Slot 6 counts only compiler-emitted `setText`,
`setProperty`, and `setAttribute` calls. DOM writes are identical because all
strategies create the same 10,000 rows and reach the same changed DOM; the
measured benefit is fewer retained-row sink evaluations and updates, not fewer
DOM writes. Validation units count accepted deltas plus items inspected in full
targets and are not an exact JavaScript instruction count. The placement column
reflects the ABI-8 region host, which moves only the retained rows outside one
longest order-preserving subsequence: the full strategy's swap and sort now cost
the same placements as the delta strategies (5,000 after the 10,000 mounts),
where the ABI-7 host's sibling walk paid 23,997 for the full strategy and
15,001 for the delta strategies.

## Size and build cost

The deterministic ABI-7 artifacts measured:

| Artifact | Bytes |
|---|---:|
| Readable generated module (all three exports) | 16,195 |
| Compact generated module (all three exports) | 13,680 |
| Manifest | 617 |
| Native expected full-row oracle | 178,484 |
| DOM + region + disposer hosts | 14,740 |
| Compact module plus shared hosts | 28,420 |

The generated module intentionally contains all variants, so these numbers do
not isolate one strategy's marginal bytes. The large expected oracle is a test
artifact, not shipped runtime code. A clean no-hardlinks checkout built
`leanrx_data_grid_js` in 13.03 s real time (126 jobs); subsequent artifact
generation took 2.07 s real time. These are machine-specific samples, not
budgets.

## Complexity and API burden

The current experiment contains 140 lines of pure delta semantics and
proof-carrying planning, 346 lines in the grid reference/cost model, 71 lines in
the sealed component contract, and 948 lines in the specialized
typed-JavaScript-AST emitter. M10 added 189 lines to the pre-existing 162-line
local region host, bringing that shared file to 351 lines. Focused M10 native,
fake-DOM, artifact, and browser test additions total about 637 lines before
scripts and compile-fail fixtures. The public
opt-in surface exposes the closed `ListDelta` vocabulary and proof-carrying
`PlannedDeltas`; ordinary static scalar/component applications do not need
either.

The generated Data Grid deliberately fixes the checked default cost model so
accepted browser configurations cannot carry parameters that the backend does
not lower. Native/generated agreement remains executable evidence inside the
TCB. The pure `runTrace` oracle still accepts alternative cost models for
research. `mapDelta`,
`filterDelta`, `keyBy`, `sortDelta`, folds, and joins still lack the individual
correctness connections required by the architecture.

## Decision

Structural delta remains an opt-in experimental library. It demonstrates
substantial retained-row work suppression and improves small keyed operations in
this fixture, but it does not reduce this trace's emitted DOM writes and the
evidence does not justify a first-class language or default compiler feature.
Full keyed reconciliation remains the default. A specialized backend may opt
into delta/hybrid only through a checked, disclosed cost model and reproducible
correctness/measurement gates.

Promotion requires multiple browsers/device classes and collection shapes,
isolated application allocation profiles, per-strategy/tree-shaken bundle
comparison, proofs for composed delta operators, and a cost model that predicts
the generated validation, search, and projection work observed here.
