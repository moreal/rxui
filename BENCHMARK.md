# Benchmark

Results from the pinned upstream [`js-framework-benchmark`](https://github.com/krausest/js-framework-benchmark)
runner (`chrome150`, commit `fa15a77d73dca6dfc0a97ce8c4d6c0797726fa75`), comparing LeanRx against
vanilla JavaScript, React Hooks, Preact Hooks, Vue, Solid, and Svelte keyed
implementations of the same table application. See
[the integration guide](docs/performance/js-framework-benchmark.md) for what is
measured and how to reproduce it.

## How this was measured

```sh
corepack pnpm benchmark:compare -- --headless
```

- Measured at: 2026-08-22 05:37:41 UTC
- LeanRx commit: `2963b85c83d40d5941e6475338a481fc512693ff` (tree state: clean)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, and this exact environment metadata are archived under
`.tmp/js-framework-benchmark-results/20260822T053741Z/` (not committed; regenerate
with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | vanilla | React Hooks | Preact Hooks | Vue | Solid | Svelte | **LeanRx** |
|---|---:|---:|---:|---:|---:|---:|---:|
| Create 1,000 rows (ms) | 29.5 | 37.9 | 38.9 | 36.5 | 31.8 | 31.3 | 33.4 |
| Replace all 1,000 rows (ms) | 35.1 | 50.0 | 46.5 | 41.7 | 38.9 | 39.1 | 37.0 |
| Partial update, every 10th row ×16 (ms) | 22.4 | 26.5 | 36.9 | 24.4 | 21.4 | 21.2 | 24.1 |
| Select row (ms) | 6.6 | 10.3 | 24.2 | 8.5 | 10.5 | 11.9 | 9.4 |
| Swap rows (ms) | 26.9 | 152.0 | 42.6 | 31.3 | 31.0 | 33.0 | 140.3 |
| Remove row (ms) | 18.1 | 21.3 | 29.0 | 23.5 | 19.6 | 19.5 | 21.2 |
| Create 10,000 rows (ms) | 330.5 | 670.5 | 425.3 | 409.5 | 354.1 | 354.8 | 382.1 |
| Append 1,000 to 10,000 rows ×2 (ms) | 36.4 | 45.0 | 47.8 | 42.9 | 38.7 | 39.5 | 44.1 |
| Clear rows ×8 (ms) | 14.5 | 27.3 | 20.1 | 20.4 | 19.6 | 17.1 | 21.7 |

## Memory

| Benchmark | vanilla | React Hooks | Preact Hooks | Vue | Solid | Svelte | **LeanRx** |
|---|---:|---:|---:|---:|---:|---:|---:|
| Memory after page load (MB) | 0.55 | 1.18 | 0.66 | 0.86 | 0.61 | 0.63 | 0.59 |
| Memory after adding 1,000 rows (MB) | 1.89 | 4.42 | 3.34 | 3.76 | 2.70 | 2.82 | 1.95 |
| Memory after adding then clearing rows (MB) | 0.66 | 1.97 | 0.84 | 1.18 | 0.79 | 0.97 | 0.74 |

## Startup and size

| Benchmark | vanilla | React Hooks | Preact Hooks | Vue | Solid | Svelte | **LeanRx** |
|---|---:|---:|---:|---:|---:|---:|---:|
| Uncompressed JS size (KB) | 11.30 | 190.30 | 14.60 | 63.70 | 11.50 | 34.30 | 22.50 |
| Compressed (Brotli) JS size (KB) | 2.50 | 51.40 | 5.70 | 22.80 | 4.50 | 12.20 | 5.40 |
| Startup time to first paint (ms) | 72.00 | 332.50 | 84.30 | 140.40 | 82.90 | 125.60 | 70.40 |

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
