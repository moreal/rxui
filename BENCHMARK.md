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

- Measured at: 2026-08-23 06:55:01 UTC
- LeanRx commit: `19d9fe07be10a82991b00ef6b50001c899320445` plus the uncommitted
  ADR-0025 printer and backend changes (tree state: dirty; see ADR-0025 and the
  archived `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T065501Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.5 | 32.1 | 30.3 |
| Replace all 1,000 rows (ms) | 47.0 | 36.9 | 33.8 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 28.3 | 21.5 | 20.8 |
| Select row, 4× CPU slowdown (ms) | 10.6 | 8.0 | 6.3 |
| Swap rows, 4× CPU slowdown (ms) | 149.1 | 25.5 | 23.2 |
| Remove row, 2× CPU slowdown (ms) | 19.7 | 18.3 | 17.8 |
| Create 10,000 rows (ms) | 673.5 | 355.3 | 330.8 |
| Append 1,000 rows to 1,000 rows (ms) | 46.3 | 38.6 | 36.8 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 27.8 | 20.1 | 15.2 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.60 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.69 | 1.94 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.79 | 0.71 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 9.10 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 3.10 |
| Startup time to first paint (ms) | 327.90 | 76.80 | 81.30 |

## Change from the previous run

The previous recorded run (commit `89c3920` plus the ADR-0024 compactor
changes that became `19d9fe0`, same runner, headless, the same three
frameworks) measured LeanRx at 31.1 ms create 1,000, 33.9 ms replace, 22.0 ms
partial update, 6.6 ms select, 24.6 ms swap, 17.4 ms remove, 330.6 ms create
10,000, 37.8 ms append, and 15.2 ms clear, with 9.60 KB uncompressed / 3.20 KB
Brotli and 77.8 ms to first paint. This run ships the ADR-0025 build: the
JavaScript AST printer (`LeanRx/Backend/JsPrinter.lean`) now emits
parentheses only where operator precedence requires them and prints
`x = x + e` as `x += e`, and the benchmark backend omits the `return null`
statements that ended handlers whose results nothing reads; the hosts in
`runtime/`, the compactor, the runtime ABI, and the Lean models are
unchanged, and no function is tree-shaken. The shipped application shrinks
from 9.6 to 9.1 KB uncompressed and from 3.2 to 3.1 KB Brotli (local baseline
9,788 → 9,341 raw, 3,247 → 3,217 Brotli bytes, of which `main.mjs` is 7,675 /
2,857 against Solid's single 11,563 / 4,358-byte module). The executed
statements are the same minus one `return` per handler, so the CPU rows again
measure drift of this headless runner, and in this run every one of them is
below Solid's: create 1,000 31.1 → 30.3 ms (Solid 31.7 → 32.1), replace 33.9
→ 33.8 (Solid 39.1 → 36.9), partial update 22.0 → 20.8 (Solid 23.5 → 21.5;
script 1.27 against 1.93 ms), select 6.6 → 6.3 (Solid 8.3 → 8.0), swap 24.6 →
23.2 (15 samples, 23.2 ± 2.2 ms, median 22.5, against Solid's 25.5 ± 2.9 ms,
median 25.4; script 0.99 against 2.07 ms, paint 19.3 against 20.3 ms — the
two means are again within one standard deviation of each other, so this row
remains a coin flip between the two), remove 17.4 → 17.8 (Solid 18.6 → 18.3),
create 10,000 330.6 → 330.8 (Solid 357.3 → 355.3; script 28.3 against 35.7
ms), append 37.8 → 36.8 (Solid 38.1 → 38.6; script 3.03 against 4.42 ms,
paint 32.4 against 32.7 ms), and clear 15.2 → 15.2 (Solid 19.5 → 20.1). First
paint is one `performance.getEntriesByType("paint")` sample per framework
and moved 77.8 → 81.3 ms while Solid moved 81.5 → 76.8 ms and React Hooks
318.0 → 327.9 ms; across the last three runs LeanRx measured 77.6, 77.8, and
81.3 ms against Solid's 81.3, 81.5, and 76.8 ms, so the two are not separable
by this row. Memory after page load is 0.58 → 0.60 MB for LeanRx and 0.61 →
0.61 MB for Solid, and after adding 1,000 rows 2.04 → 1.94 MB (Solid 2.70 →
2.69).

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

Size was the one category where LeanRx trailed Solid until the ADR-0024 run (20.2 KB
against 11.5 KB uncompressed, 5.3 against 4.5 KB Brotli before ADR-0023;
17.1 / 4.2 KB after it). Measured on 2026-08-23 over the shipped files
before ADR-0023: the region host's documentation comments were about 2.9 KB
raw and 1.0 KB Brotli of the total and the `leanrx_host.mjs` disposer was
served uncompressed because it was below the upstream server's 1 KiB Brotli
threshold; ADR-0022 removed both, ADR-0023 flattened the page into one
module, ADR-0024 compacts that module in Lean (whitespace, comments,
short identifiers, dot member access) to 8,122 raw / 2,887 Brotli bytes,
below both esbuild's bundle-and-minify of the same files (about 8,786 /
3,124, measured as a reference, not adopted) and Solid's module, and
ADR-0025 prints the generated part without redundant parentheses, with
compound assignments, and without effect-only `return null` statements
(7,675 / 2,857 bytes). What remains is code: the keyed region host, the DOM
host with the disposer, the generated module, and `index.html` (1.7 KB /
0.36 KB, excluded from the upstream size score, which counts JavaScript
only); the next size step would be tree-shaking host functions this
application never calls, which the "Reading these numbers" note below
deliberately does not do.

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
