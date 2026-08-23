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

- Measured at: 2026-08-23 03:57:49 UTC
- LeanRx commit: `9ae4b951087843863820f95ecfdd9166ff691657` plus the uncommitted
  ADR-0023 build changes (tree state: dirty; see ADR-0023 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T035749Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.8 | 32.2 | 30.6 |
| Replace all 1,000 rows (ms) | 47.5 | 35.8 | 33.4 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 25.4 | 23.7 | 18.6 |
| Select row, 4× CPU slowdown (ms) | 10.1 | 8.1 | 6.4 |
| Swap rows, 4× CPU slowdown (ms) | 144.7 | 25.3 | 21.2 |
| Remove row, 2× CPU slowdown (ms) | 20.0 | 18.0 | 18.2 |
| Create 10,000 rows (ms) | 643.9 | 347.8 | 326.5 |
| Append 1,000 rows to 1,000 rows (ms) | 45.1 | 38.7 | 35.3 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 26.8 | 18.5 | 15.0 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.14 | 0.58 | 0.55 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 1.93 |
| Memory after adding then clearing rows (MB) | 1.89 | 0.70 | 0.71 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 17.10 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 4.20 |
| Startup time to first paint (ms) | 317.80 | 81.30 | 77.60 |

## Change from the previous run

The previous recorded run (commit `8bf0153` plus the ABI-12 runtime changes
that became `9ae4b95`, same runner, headless, the same three frameworks)
measured LeanRx at 30.8 ms create 1,000, 34.0 ms replace, 20.5 ms partial
update, 5.9 ms select, 23.6 ms swap (24.1 ms median), 17.9 ms remove,
330.2 ms create 10,000, 36.7 ms append, and 15.1 ms clear, with 20.20 KB
uncompressed / 5.30 KB Brotli, five fetched files, and 74.5 ms to first
paint. This run ships the ADR-0023 build: `lake exe
leanrx_js_framework_benchmark` now flattens the application into one
`main.mjs` (the DOM host and the keyed region host inlined from `runtime/`
with their comments, blank lines, indentation, and `export` keywords dropped,
then the generated declarations without import/export statements, then the
mount statement), so the page fetches two files instead of five; no host
function is tree-shaken, no identifier is renamed, and no minifier is
involved. The shipped application shrinks from 20.2 to 17.1 KB uncompressed
and from 5.3 to 4.2 KB Brotli (local baseline 20,684 → 17,480 raw, 5,415 →
4,277 Brotli bytes, of which `main.mjs` is 15,814 / 3,917 against Solid's
single 11,563 / 4,358-byte module); the compressed size row is now below
Solid's 4.5 KB, and the uncompressed row is the only upstream row where
LeanRx still trails it. The host and generated code are byte-identical apart
from whitespace, comments, and module syntax, so the CPU rows again measure
run-to-run drift of this headless runner: create 1,000 30.8 → 30.6 ms (Solid
32.2 → 32.2), replace 34.0 → 33.4 (Solid 36.5 → 35.8), partial update 20.5 →
18.6 (Solid 22.9 → 23.7), select 5.9 → 6.4 (Solid 8.4 → 8.1), swap 23.6 →
21.2 (15 samples, 21.2 ± 1.7 ms, median 20.4 ms, against Solid's 25.3 ± 3.1
ms, median 24.5 ms; LeanRx's script phase is 1.09 ms against Solid's 2.09
ms), remove 17.9 → 18.2 (18.2 ± 2.2 ms, median 18.0 ms, against Solid's 18.0
± 1.0 ms, median 18.1 ms; LeanRx's script phase is 0.49 ms against Solid's
0.77 ms, the difference is paint), create 10,000 330.2 → 326.5 (Solid 356.5 →
347.8), append 36.7 → 35.3 (Solid 38.9 → 38.7), and clear 15.1 → 15.0 (Solid
19.7 → 18.5). First paint moved 74.5 → 77.6 ms while Solid moved 79.0 → 81.3
ms and React Hooks 319.1 → 317.8 ms (first paint varies by about ±10 ms
between runs of this runner, more than three fewer localhost requests can
show); memory after page load is
0.61 → 0.55 MB for LeanRx and 0.61 → 0.58 MB for Solid in the same run, and
after adding 1,000 rows 2.06 → 1.93 MB (Solid 2.70 → 2.70). An earlier
attempt at this run was discarded: the upstream runner hit a transient
puppeteer "detached Frame" error while loading Solid's select benchmark,
retried for about two hours, and exited with "run was not completely
successful" without archiving.

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
