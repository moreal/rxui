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

- Measured at: 2026-08-22 15:52:14 UTC
- LeanRx commit: `90a714645d8e8fca4e5dc624bbafd80fb767c84f` plus the uncommitted
  ABI-11 runtime changes (tree state: dirty; see ADR-0021 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260822T155214Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.2 | 31.4 | 30.4 |
| Replace all 1,000 rows (ms) | 46.6 | 36.2 | 33.7 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 25.6 | 21.3 | 19.8 |
| Select row, 4× CPU slowdown (ms) | 10.2 | 7.4 | 6.1 |
| Swap rows, 4× CPU slowdown (ms) | 154.7 | 24.4 | 26.9 |
| Remove row, 2× CPU slowdown (ms) | 19.6 | 18.8 | 17.9 |
| Create 10,000 rows (ms) | 691.4 | 357.4 | 331.5 |
| Append 1,000 rows to 1,000 rows (ms) | 45.1 | 38.9 | 36.4 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 27.8 | 20.6 | 15.2 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.17 | 0.52 | 0.53 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.69 | 1.97 |
| Memory after adding then clearing rows (MB) | 1.95 | 0.70 | 0.73 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 21.50 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 6.30 |
| Startup time to first paint (ms) | 321.50 | 72.50 | 73.50 |

## Change from the previous run

The previous recorded run (commit `05a0b1e` plus the ABI-10 runtime changes
that became `1100c15`, same runner, headless, the same three frameworks)
measured LeanRx at 30.8 ms create 1,000, 33.7 ms replace, 20.9 ms partial
update, 6.2 ms select, 22.8 ms swap, 17.9 ms remove, 330.0 ms create 10,000,
38.5 ms append, and 14.4 ms clear, with 22.70 KB uncompressed / 6.40 KB Brotli
and 63.0 ms to first paint. The ABI-11 runtime (ADR-0021) moves the five typed
control-event adapters out of the DOM host into `leanrx_form_events.mjs`, a
module that only the form applications import, so the benchmark's DOM host
shrinks from 3,861 to 2,647 bytes and the shipped application from 22.7 to
21.5 KB uncompressed (Brotli 6.4 → 6.3 KB). The generated module and the
region host are byte-identical to the previous run, so the CPU rows measure
run-to-run drift of this headless runner rather than a code change: create
1,000 30.8 → 30.4 ms, replace level at 33.7 ms, partial update 20.9 → 19.8 ms,
select 6.2 → 6.1 ms, remove level at 17.9 ms, create 10,000 330.0 → 331.5 ms,
append 38.5 → 36.4 ms (paint 33.7 → 32.0 ms, now below Solid's 38.9 ms), and
clear 14.4 → 15.2 ms with Solid moving 18.9 → 20.6 ms in the same run. Swap
reads 22.8 → 26.9 ms because one of its fifteen samples took 62.8 ms (56.1 ms
of paint); the other fourteen average 24.3 ms and the median is 23.9 ms against
Solid's 24.0 ms median, with LeanRx's script phase (1.05 ms) still below
Solid's (1.89 ms); a focused re-run of the swap workload alone for LeanRx and
Solid one minute later (`--framework keyed/solid --benchmark 05_`, archived
under `20260822T155431Z`) measured 20.4 ± 1.0 ms against 22.9 ± 1.4 ms.
First paint moved 63.0 → 73.5 ms while Solid moved 80.4 → 72.5 ms and React
Hooks 316.3 → 321.5 ms (first paint varies by about ±10 ms between runs of
this runner); memory after adding 1,000 rows is 2.05 → 1.97 MB.

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

Size is the one category where LeanRx is clearly behind Solid (21.5 KB against
11.5 KB uncompressed, 6.3 against 4.5 KB Brotli). Measured on 2026-08-23 over
the shipped files: the region host's documentation comments account for about
2.9 KB raw and 1.0 KB Brotli of the total (stripping every host comment at
bundle time would leave 19.5 KB / 5.5 KB), the `leanrx_host.mjs` disposer is
served uncompressed because it is below the upstream server's 1 KiB Brotli
threshold, and printer-level changes to the generated module (dot-notation
member access, shorter function names) would save under 0.5 KB raw and under
60 bytes Brotli. Closing the remaining gap therefore means either a minifier
or bundle-time comment stripping, both of which change the stance that the
shipped hosts are the repository's host files; neither is decided here.

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
