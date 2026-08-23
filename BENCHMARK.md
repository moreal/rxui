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

- Measured at: 2026-08-23 00:22:54 UTC
- LeanRx commit: `8bf0153c8d897f4812dff6db2498e62f4b421d1f` plus the uncommitted
  ABI-12 runtime changes (tree state: dirty; see ADR-0022 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T002254Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.5 | 32.2 | 30.8 |
| Replace all 1,000 rows (ms) | 47.4 | 36.5 | 34.0 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 29.4 | 22.9 | 20.5 |
| Select row, 4× CPU slowdown (ms) | 10.8 | 8.4 | 5.9 |
| Swap rows, 4× CPU slowdown (ms) | 151.8 | 25.3 | 23.6 |
| Remove row, 2× CPU slowdown (ms) | 20.5 | 18.9 | 17.9 |
| Create 10,000 rows (ms) | 697.1 | 356.5 | 330.2 |
| Append 1,000 rows to 1,000 rows (ms) | 45.3 | 38.9 | 36.7 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 28.1 | 19.7 | 15.1 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.17 | 0.61 | 0.61 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 2.06 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.79 | 0.72 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 20.20 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 5.30 |
| Startup time to first paint (ms) | 319.10 | 79.00 | 74.50 |

## Change from the previous run

The previous recorded run (commit `90a7146` plus the ABI-11 runtime changes
that became `8bf0153`, same runner, headless, the same three frameworks)
measured LeanRx at 30.4 ms create 1,000, 33.7 ms replace, 19.8 ms partial
update, 6.1 ms select, 26.9 ms swap (23.9 ms median), 17.9 ms remove,
331.5 ms create 10,000, 36.4 ms append, and 15.2 ms clear, with 21.50 KB
uncompressed / 6.30 KB Brotli and 73.5 ms to first paint. The ABI-12 runtime
(ADR-0022) deletes `leanrx_host.mjs` — an 867-byte module that the upstream
server served uncompressed because it is below its 1 KiB Brotli threshold,
13.5% of the compressed application — by moving `makeDisposer` unchanged into
the DOM host the page already fetches, and condenses the region and DOM hosts'
multi-line comments to the terse style of the other hosts (the contract prose
moved to the internals document). The page now fetches five files instead of
six, and the shipped application shrinks from 21.5 to 20.2 KB uncompressed and
from 6.3 to 5.3 KB Brotli (local baseline 22,047 → 20,684 raw, 6,422 → 5,415
Brotli bytes); Solid's 4.5 KB Brotli is now 0.8 KB away instead of 1.8 KB.
The generated module differs only by one import specifier and the region host
only by comments, so the CPU rows again measure run-to-run drift of this
headless runner: create 1,000 30.4 → 30.8 ms (Solid 31.4 → 32.2), replace
33.7 → 34.0 (Solid 36.2 → 36.5), partial update 19.8 → 20.5 (Solid 21.3 →
22.9), select 6.1 → 5.9 (Solid 7.4 → 8.4), remove level at 17.9, create
10,000 331.5 → 330.2, append 36.4 → 36.7, and clear 15.2 → 15.1 (Solid 20.6 →
19.7). Swap reads 26.9 → 23.6 ms because this run had no outlier sample (15
samples, 23.6 ± 1.4 ms, median 24.1 ms, against Solid's 25.3 ± 1.5 ms, median
24.9 ms); LeanRx's script phase is 1.15 ms against Solid's 2.04 ms. First
paint moved 73.5 → 74.5 ms while Solid moved 72.5 → 79.0 ms and React Hooks
321.5 → 319.1 ms (first paint varies by about ±10 ms between runs of this
runner); memory after page load is 0.53 → 0.61 MB for LeanRx and 0.52 → 0.61
MB for Solid in the same run, and after adding 1,000 rows 1.97 → 2.06 MB
(Solid 2.69 → 2.70).

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
moves are the rest). Three candidates were measured and rejected: a
two-row-exchange shortcut in keyed placement (about 0.03 ms per swap for
630 more bytes of shipped host), lowering the every-tenth-row update through
`updateAt` for the 100 changed rows (0.03 ms faster locally but 0.3 ms more
script under the upstream runner's 4× CPU slowdown, where the 100-call path
runs less optimized than the 1,000-row region loop; confirmed by a focused
upstream A/B with vanilla as the control), and detaching the owned `tbody`
during a pure append of 1,000 rows onto 1,000 (2026-08-23: the re-attach
re-styles every existing row, 23 → 39 ms to the next frame locally; only the
empty-parent rebuild benefits from detaching).

Size is the one category where LeanRx is still behind Solid (20.2 KB against
11.5 KB uncompressed, 5.3 against 4.5 KB Brotli). Measured on 2026-08-23 over
the shipped files before this run: the region host's documentation comments
were about 2.9 KB raw and 1.0 KB Brotli of the total and the `leanrx_host.mjs`
disposer was served uncompressed because it was below the upstream server's
1 KiB Brotli threshold; ADR-0022 removed both (the comments are condensed in
the repository host files, not stripped at bundle time, so the shipped hosts
remain the repository's host files). What remains is code: the generated
module (7.2 KB raw / 1.75 KB Brotli), the keyed region host (8.4 KB / 2.2 KB),
the DOM host with the disposer (3.3 KB / 1.0 KB), `index.html` (1.7 KB /
0.36 KB), and the 114-byte `main.mjs`. Printer-level changes to the generated
module (dot-notation member access, shorter function names) would save under
0.5 KB raw and under 60 bytes Brotli; the next real step would be a minifier,
which is a new build dependency and is not decided here.

## Reading these numbers

- CPU and memory numbers are single-run means from an automated headless
  Chrome session on one developer machine; treat them as a snapshot for
  regression tracking, not a definitive cross-framework ranking. Re-run
  `corepack pnpm benchmark:compare` in visible Chrome, idle machine, for
  publishable comparisons.
- Size numbers reflect the complete fetched application (see the [local byte
  baseline](docs/performance/js-framework-benchmark.md#deterministic-local-gate)),
  including LeanRx's shared region-runtime host rather than a tree-shaken
  lower bound; the structural-delta, conditional/positional, and form-event
  hosts are shipped only by artifacts that import them.
- A regression in one category is not offset by an improvement in another;
  read CPU, memory, and size as independent signals.
