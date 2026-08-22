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

- Measured at: 2026-08-22 13:55:46 UTC
- LeanRx commit: `05a0b1e2d865085fe9c8640b663183e25a20c564` plus the uncommitted
  ABI-10 runtime changes (tree state: dirty; see ADR-0020 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260822T135546Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.4 | 32.2 | 30.8 |
| Replace all 1,000 rows (ms) | 46.7 | 36.3 | 33.7 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 27.7 | 21.3 | 20.9 |
| Select row, 4× CPU slowdown (ms) | 10.4 | 7.5 | 6.2 |
| Swap rows, 4× CPU slowdown (ms) | 148.3 | 25.4 | 22.8 |
| Remove row, 2× CPU slowdown (ms) | 20.2 | 18.6 | 17.9 |
| Create 10,000 rows (ms) | 675.9 | 360.8 | 330.0 |
| Append 1,000 rows to 1,000 rows (ms) | 45.7 | 37.0 | 38.5 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 26.6 | 18.9 | 14.4 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.62 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 2.05 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.79 | 0.73 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 22.70 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 6.40 |
| Startup time to first paint (ms) | 316.30 | 80.40 | 63.00 |

## Change from the previous run

The previous recorded run (commit `314b6c1` plus the ABI-9 runtime changes
that became `05a0b1e`, same runner, headless, the same three frameworks)
measured LeanRx at 30.6 ms create 1,000, 35.1 ms replace, 20.2 ms partial
update, 7.5 ms select, 23.5 ms swap, 18.1 ms remove, 335.5 ms create 10,000,
36.8 ms append, and 14.9 ms clear, with 23.50 KB uncompressed / 6.30 KB Brotli
and 61.8 ms to first paint. The ABI-10 runtime (the model rows are the keyed
items and the region forwards the mount-local context to the row callbacks, so
a commit builds no per-row payload array; selecting a row re-runs exactly the
previously and newly selected rows through the region's `updateAt`; keys added
to an empty region are registered with one index insertion; and the
conditional/positional regions moved into a host module the benchmark does not
ship) brings select from 7.5 to 6.2 ms (script 1.7 → 0.8 ms, below Solid's
7.5 ms), replace from 35.1 to 33.7 ms, create 10,000 from 335.5 to 330.0 ms
(script 29.2 → 28.4 ms), swap from 23.5 to 22.8 ms, and clear from 14.9 to
14.4 ms; create 1,000, partial update (script 1.4 → 1.2 ms), and remove are
level within run-to-run noise. Append moved from 36.8 to 38.5 ms with its
script phase unchanged (3.0 → 3.1 ms) and its paint phase up 1.5 ms, which is
within the paint noise of this headless runner. The shipped application is
23.5 → 22.7 KB uncompressed (Brotli 6.3 → 6.4 KB: the added keyed-region code
compresses less well than the removed comment-heavy unkeyed regions); first
paint (61.8 → 63.0 ms) and memory (1.99 → 2.05 MB after adding 1,000 rows)
are within noise, with Solid and React Hooks moving by similar amounts in the
same run.

## Where the remaining time goes

Measured locally on 2026-08-22 (Playwright-driven headless Chromium, no CPU
throttling, `performance.now()` timers inside the region host and the
application, medians of seven fresh-page runs; a diagnostic, not the upstream
runner): creating 10,000 rows spends about 1.7 ms building the model rows,
0.8 ms validating keys (the key-index insert that rejects a repeated key
before any DOM mutation), 26 ms cloning the row template and writing its two
texts, 2.5 ms inserting the rows into the detached `tbody`, and 2.6 ms
re-attaching the `tbody`. The vanilla JavaScript implementation's row loop
spends the same 26 ms in clone plus text writes, so LeanRx's remaining script
gap to it (about 3 ms per 10,000 rows) is the key validation plus per-row
bookkeeping; clearing costs the same as vanilla's `textContent = ""`, and a
swap's placement search is about 0.03 ms of its 0.12 ms handler (the two DOM
moves are the rest). Two candidates were measured and rejected the same day:
a two-row-exchange shortcut in keyed placement (about 0.03 ms per swap for
630 more bytes of shipped host), and lowering the every-tenth-row update
through `updateAt` for the 100 changed rows (0.03 ms faster locally but
0.3 ms more script under the upstream runner's 4× CPU slowdown, where the
100-call path runs less optimized than the 1,000-row region loop; confirmed by
a focused upstream A/B with vanilla as the control).

## Reading these numbers

- CPU and memory numbers are single-run means from an automated headless
  Chrome session on one developer machine; treat them as a snapshot for
  regression tracking, not a definitive cross-framework ranking. Re-run
  `corepack pnpm benchmark:compare` in visible Chrome, idle machine, for
  publishable comparisons.
- Size numbers reflect the complete fetched application (see the [local byte
  baseline](docs/performance/js-framework-benchmark.md#deterministic-local-gate)),
  including LeanRx's shared region-runtime host rather than a tree-shaken
  lower bound; the structural-delta and conditional/positional hosts are
  shipped only by artifacts that import them.
- A regression in one category is not offset by an improvement in another;
  read CPU, memory, and size as independent signals.
