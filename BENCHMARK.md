# Benchmark

Results from the pinned upstream [`js-framework-benchmark`](https://github.com/krausest/js-framework-benchmark)
runner (`chrome150`, commit `fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75`), comparing LeanRx against
the React Hooks and Solid keyed implementations of the same table application.
See [the integration guide](docs/performance/js-framework-benchmark.md) for what
is measured and how to reproduce it; the `popular` preset additionally measures
vanilla JavaScript, Preact Hooks, Vue, and Svelte, which this refresh skipped to
keep the run short.

## How this was measured

```sh
./scripts/run_js_framework_benchmark.sh --framework keyed/react-hooks --framework keyed/solid --headless --no-results
```

- Measured at: 2026-08-22 12:41:22 UTC
- LeanRx commit: `314b6c1884f8ff52d98732b634197289b37c8d18` plus the uncommitted
  ABI-9 runtime changes (tree state: dirty; see ADR-0019 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260822T124122Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 39.0 | 33.3 | 30.6 |
| Replace all 1,000 rows (ms) | 48.6 | 37.9 | 35.1 |
| Partial update, every 10th row ×16 (ms) | 27.3 | 23.7 | 20.2 |
| Select row (ms) | 10.5 | 7.5 | 7.5 |
| Swap rows (ms) | 152.7 | 24.5 | 23.5 |
| Remove row (ms) | 21.0 | 18.5 | 18.1 |
| Create 10,000 rows (ms) | 683.1 | 352.5 | 335.5 |
| Append 1,000 to 10,000 rows ×2 (ms) | 45.2 | 37.9 | 36.8 |
| Clear rows ×8 (ms) | 27.2 | 20.0 | 14.9 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.62 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 1.99 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.79 | 0.74 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 23.50 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 6.30 |
| Startup time to first paint (ms) | 318.60 | 79.40 | 61.80 |

## Change from the previous run

The previous recorded run (commit `41974a7` plus the ABI-8 runtime changes,
same runner, headless, the same three frameworks) measured LeanRx at 31.3 ms
create 1,000, 34.8 ms replace, 21.3 ms partial update, 8.2 ms select, 23.4 ms
swap, 18.7 ms remove, 345.7 ms create 10,000, 37.2 ms append, and 15.3 ms
clear, with 27.60 KB uncompressed / 6.80 KB Brotli and 71.2 ms to first paint.
The ABI-9 runtime (row keys as node properties instead of attributes, a
template cloned from a node built once in `mount`, key-index validation that
matches retained keys by position, and a detached bulk rebuild of an owned
parent) trims create 10,000 by about 10 ms (script 32.6 → 29.2 ms, paint
301.3 → 294.4 ms), brings select level with Solid, and improves or holds every
other CPU workload within run-to-run noise. Moving the opt-in structural-delta
adapter into its own host module removes 4.1 KB uncompressed / 0.5 KB Brotli
from the shipped application, which also lowers first paint; memory is
unchanged within noise.

## Reading these numbers

- CPU and memory numbers are single-run means from an automated headless
  Chrome session on one developer machine; treat them as a snapshot for
  regression tracking, not a definitive cross-framework ranking. Re-run
  `corepack pnpm benchmark:compare` in visible Chrome, idle machine, for
  publishable comparisons.
- Size numbers reflect the complete fetched application (see the [local byte
  baseline](docs/performance/js-framework-benchmark.md#deterministic-local-gate)),
  including LeanRx's shared region-runtime host rather than a tree-shaken
  lower bound; the structural-delta host is shipped only by artifacts that
  import it.
- A regression in one category is not offset by an improvement in another;
  read CPU, memory, and size as independent signals.
