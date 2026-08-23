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

- Measured at: 2026-08-23 06:09:34 UTC
- LeanRx commit: `89c39204bd4fdc6bfd952e22b0d1d5eab34455d4` plus the uncommitted
  ADR-0024 compactor changes (tree state: dirty; see ADR-0024 and the archived
  `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T060934Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 37.7 | 31.7 | 31.1 |
| Replace all 1,000 rows (ms) | 48.2 | 39.1 | 33.9 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 28.4 | 23.5 | 22.0 |
| Select row, 4× CPU slowdown (ms) | 10.1 | 8.3 | 6.6 |
| Swap rows, 4× CPU slowdown (ms) | 156.1 | 23.7 | 24.6 |
| Remove row, 2× CPU slowdown (ms) | 20.6 | 18.6 | 17.4 |
| Create 10,000 rows (ms) | 649.5 | 357.3 | 330.6 |
| Append 1,000 rows to 1,000 rows (ms) | 46.3 | 38.1 | 37.8 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 27.5 | 19.5 | 15.2 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.58 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 2.04 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.78 | 0.71 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 9.60 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 3.20 |
| Startup time to first paint (ms) | 318.00 | 81.50 | 77.80 |

## Change from the previous run

The previous recorded run (commit `9ae4b95` plus the ADR-0023 build changes
that became `89c3920`, same runner, headless, the same three frameworks)
measured LeanRx at 30.6 ms create 1,000, 33.4 ms replace, 18.6 ms partial
update, 6.4 ms select, 21.2 ms swap, 18.2 ms remove, 326.5 ms create 10,000,
35.3 ms append, and 15.0 ms clear, with 17.10 KB uncompressed / 4.20 KB
Brotli and 77.6 ms to first paint. This run ships the ADR-0024 build: the
flattened `main.mjs` now passes through a dependency-free Lean compactor
(`LeanRx/Backend/JsCompact.lean`) that drops comments and unneeded
whitespace, writes `x["name"]` as `x.name`, and renames every top-level
binding and every binding inside a top-level function to a short name,
rejecting at build time any construct it does not model; the readable hosts
in `runtime/`, the AST printer, the runtime ABI, and the Lean models are
unchanged, and no function is tree-shaken. The shipped application shrinks
from 17.1 to 9.6 KB uncompressed and from 4.2 to 3.2 KB Brotli (local
baseline 17,480 → 9,788 raw, 4,277 → 3,247 Brotli bytes, of which `main.mjs`
is 8,122 / 2,887 against Solid's single 11,563 / 4,358-byte module), so both
size rows are now below Solid's; no upstream row remains where LeanRx trails
Solid by more than run-to-run noise. The compacted code executes the same
statements in the same order, so the CPU rows again measure drift of this
headless runner: create 1,000 30.6 → 31.1 ms (Solid 32.2 → 31.7), replace
33.4 → 33.9 (Solid 35.8 → 39.1), partial update 18.6 → 22.0 (Solid 23.7 →
23.5; LeanRx's script phase is 1.47 ms against Solid's 1.87 ms, the rest is
paint), select 6.4 → 6.6 (Solid 8.1 → 8.3), swap 21.2 → 24.6 (15 samples,
24.6 ± 2.0 ms, median 24.0 ms, against Solid's 23.7 ± 1.9 ms, median 23.8
ms; LeanRx's script phase is 1.08 ms against Solid's 2.11 ms, the difference
is paint, 20.3 against 18.8 ms, and the two means are within one standard
deviation of each other), remove 18.2 → 17.4 (Solid 18.0 → 18.6), create
10,000 326.5 → 330.6 (Solid 347.8 → 357.3), append 35.3 → 37.8 (Solid 38.7 →
38.1; script 3.05 against 4.33 ms, paint 33.1 against 32.4 ms), and clear
15.0 → 15.2 (Solid 18.5 → 19.5). First paint moved 77.6 → 77.8 ms while Solid
moved 81.3 → 81.5 ms and React Hooks 317.8 → 318.0 ms; memory after page
load is 0.55 → 0.58 MB for LeanRx and 0.58 → 0.61 MB for Solid in the same
run, and after adding 1,000 rows 1.93 → 2.04 MB (Solid 2.70 → 2.70).

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

Size was the one category where LeanRx trailed Solid until this run (20.2 KB
against 11.5 KB uncompressed, 5.3 against 4.5 KB Brotli before ADR-0023;
17.1 / 4.2 KB after it). Measured on 2026-08-23 over the shipped files
before ADR-0023: the region host's documentation comments were about 2.9 KB
raw and 1.0 KB Brotli of the total and the `leanrx_host.mjs` disposer was
served uncompressed because it was below the upstream server's 1 KiB Brotli
threshold; ADR-0022 removed both, ADR-0023 flattened the page into one
module, and ADR-0024 compacts that module in Lean (whitespace, comments,
short identifiers, dot member access) to 8,122 raw / 2,887 Brotli bytes,
below both esbuild's bundle-and-minify of the same files (about 8,786 /
3,124, measured as a reference, not adopted) and Solid's module. What remains
is code: the keyed region host, the DOM host with the disposer, the generated
module, and `index.html` (1.7 KB / 0.36 KB, excluded from the upstream size
score, which counts JavaScript only); the next size step would be
tree-shaking host functions this application never calls, which the
"Reading these numbers" note below deliberately does not do.

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
