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

- Measured at: 2026-08-22 11:28:17 UTC
- LeanRx commit: `41974a795e72774aaf00695414f081cecae9c2bc` plus the uncommitted
  ABI-8 runtime changes (tree state: dirty; see ADR-0018 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260822T112817Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 37.7 | 31.5 | 31.3 |
| Replace all 1,000 rows (ms) | 47.0 | 37.1 | 34.8 |
| Partial update, every 10th row ×16 (ms) | 24.1 | 23.2 | 21.3 |
| Select row (ms) | 10.2 | 7.7 | 8.2 |
| Swap rows (ms) | 152.3 | 24.4 | 23.4 |
| Remove row (ms) | 21.5 | 18.1 | 18.7 |
| Create 10,000 rows (ms) | 674.5 | 349.1 | 345.7 |
| Append 1,000 to 10,000 rows ×2 (ms) | 44.6 | 37.4 | 37.2 |
| Clear rows ×8 (ms) | 26.7 | 19.2 | 15.3 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.60 | 0.61 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 1.95 |
| Memory after adding then clearing rows (MB) | 1.95 | 0.79 | 0.74 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 27.60 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 6.80 |
| Startup time to first paint (ms) | 312.70 | 76.80 | 71.20 |

## Change from the previous run

The previous recorded run (commit `2963b85`, same runner, headless, the full
`popular` preset) measured LeanRx at 33.4 ms create 1,000, 37.0 ms replace,
24.1 ms partial update, 9.4 ms select, 140.3 ms swap, 21.2 ms remove,
382.1 ms create 10,000, 44.1 ms append, and 21.7 ms clear, with 22.50 KB
uncompressed / 5.40 KB Brotli. The ABI-8 runtime (minimal keyed placement,
bulk clear of an owned parent, template-cloned rows) removes the swap outlier
and trims every other CPU workload; the shipped host grew by about 5 KB
uncompressed / 1.4 KB Brotli, which is recorded rather than offset against the
CPU gains.

## Reading these numbers

- CPU and memory numbers are single-run means from an automated headless
  Chrome session on one developer machine; treat them as a snapshot for
  regression tracking, not a definitive cross-framework ranking. Re-run
  `corepack pnpm benchmark:compare` in visible Chrome, idle machine, for
  publishable comparisons.
- Size numbers reflect the complete fetched application (see the [local byte
  baseline](docs/performance/js-framework-benchmark.md#deterministic-local-gate)),
  including LeanRx's shared full region-runtime host rather than a tree-shaken
  lower bound.
- A regression in one category is not offset by an improvement in another;
  read CPU, memory, and size as independent signals.
