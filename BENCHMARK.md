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

- Measured at: 2026-08-23 08:17:11 UTC
- LeanRx commit: `65130a6a9028cbb51aa8708dd1041441b4ad7a95` plus the uncommitted
  ADR-0026 region-host and backend changes (tree state: dirty; see ADR-0026 and
  the archived `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T081711Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 37.8 | 31.0 | 29.9 |
| Replace all 1,000 rows (ms) | 45.9 | 35.7 | 33.1 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 25.2 | 20.0 | 19.3 |
| Select row, 4× CPU slowdown (ms) | 9.4 | 7.4 | 5.3 |
| Swap rows, 4× CPU slowdown (ms) | 148.9 | 23.5 | 20.3 |
| Remove row, 2× CPU slowdown (ms) | 19.9 | 17.6 | 16.9 |
| Create 10,000 rows (ms) | 649.7 | 345.6 | 325.0 |
| Append 1,000 rows to 1,000 rows (ms) | 44.5 | 37.5 | 35.8 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 26.8 | 18.5 | 14.7 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.53 | 0.60 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 2.03 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.77 | 0.71 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 9.90 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 3.40 |
| Startup time to first paint (ms) | 309.00 | 73.10 | 68.60 |

## Change from the previous run

The previous recorded run (commit `19d9fe0` plus the ADR-0025 printer and
backend changes that became `65130a6`, same runner, headless, the same three
frameworks) measured LeanRx at 30.3 ms create 1,000, 33.8 ms replace, 20.8 ms
partial update, 6.3 ms select, 23.2 ms swap, 17.8 ms remove, 330.8 ms create
10,000, 36.8 ms append, and 15.2 ms clear, with 9.10 KB uncompressed / 3.10 KB
Brotli and 81.3 ms to first paint. This run ships the ADR-0026 build (runtime
ABI 13): the keyed region host gains `swapAt` and `removeAt`, and the benchmark
backend lowers a swap through `swapAt` (two DOM moves and two update callbacks
instead of reconciling all 1,000 rows) and a removal through `removeAt` (one
disposal instead of 999 update callbacks and a key-index pass); the Lean
models and every other operation are unchanged. Swap falls 23.2 → 20.3 ms
(script 0.99 → 0.40 ms, paint 19.3 → 17.6; Solid 25.5 → 23.5, script 2.07 →
1.97, so the row is no longer a coin flip) and remove 17.8 → 16.9 ms (script
0.40 → 0.27; Solid 18.3 → 17.6). The other CPU rows moved together with Solid
by this run's drift: create 1,000 30.3 → 29.9 (Solid 32.1 → 31.0), replace
33.8 → 33.1 (36.9 → 35.7), partial update 20.8 → 19.3 (21.5 → 20.0; script
1.27 → 1.24), select 6.3 → 5.3 (8.0 → 7.4), create 10,000 330.8 → 325.0
(355.3 → 345.6; script 28.3 → 28.1 against 34.6), append 36.8 → 35.8 (38.6 →
37.5), and clear 15.2 → 14.7 (20.1 → 18.5); every CPU row is below Solid's.
The shipped application grows from 9.1 to 9.9 KB uncompressed and from 3.1 to
3.4 KB Brotli (local baseline 9,341 → 10,087 raw, 3,217 → 3,449 Brotli bytes,
of which `main.mjs` is 8,421 / 3,089 against Solid's single 11,563 /
4,358-byte module), the cost of the two new region operations. First paint is
one `performance.getEntriesByType("paint")` sample per framework and moved
81.3 → 68.6 ms while Solid moved 76.8 → 73.1 ms and React Hooks 327.9 → 309.0
ms; across the last four runs LeanRx measured 77.6, 77.8, 81.3, and 68.6 ms
against Solid's 81.3, 81.5, 76.8, and 73.1 ms, so the two are not separable
by this row. Memory after page load is 0.60 → 0.60 MB for LeanRx and 0.61 →
0.53 MB for Solid, and after adding 1,000 rows 1.94 → 2.03 MB (Solid 2.69 →
2.70).

## Where the remaining time goes

Measured locally on 2026-08-23 (Playwright-driven headless Chromium, no CPU
throttling, `performance.now()` around the click handler; a paired harness
that loads LeanRx and the upstream vanilla implementation alternately and
takes several measured clicks per page, so a difference of 0.1 ms is
resolvable where fresh-page medians drift by about 0.5 ms between runs; a
diagnostic, not the upstream runner): creating 10,000 rows costs LeanRx about
2.4 ms more script than vanilla once the JIT is warm (about 3 ms from a fresh
page, the upstream condition). That gap is not the key index: removing the
index insertion entirely changes nothing visible, and in isolation the index
costs about 0.5 ms per 10,000 BigInt keys while the per-row entry objects cost
nothing measurable. It is the DOM shape and the id representation — giving
vanilla LeanRx's row markup costs it 1.35 ms (the string key and its
`String()` rendering about 0.9 ms, BigInt ids another 0.5 ms on top, the two
`data-lrx-action` attributes per row about 0.3 ms; the empty text nodes
nothing) — plus diffuse bookkeeping below the harness's resolution. Direct
DOM property access instead of the host wrappers, fusing the mount and insert
loops, smaller entry objects, a row handle stored as node properties, plain
counted loops, and writing the BigInt to the text node without `String()`
(slower: the binding converts it again) all measured as noise. A swap's two
DOM moves are the floor: `Node.moveBefore` measures the same as
`insertBefore`, and the time to the next frame is the table relayout either
way. What did measure was the per-commit reconciliation around narrow
operations — swap 0.14 ms against vanilla's 0.04, remove 0.19 against 0.12,
while append (2.46 against 2.19), update (0.21 against 0.17), select, clear,
and create 1,000 were level or within noise — so ADR-0026 lowers swap and
remove through the keyed region's `swapAt` and `removeAt` (swap 0.05 ms,
remove 0.085 ms locally; an append-only region operation gained nothing and
was not adopted). Earlier candidates measured and rejected remain so: a
two-row-exchange shortcut in keyed placement, lowering the every-tenth-row
update through `updateAt` for the 100 changed rows (0.03 ms faster locally
but 0.3 ms more script under the upstream runner's 4× CPU slowdown), and
detaching the owned `tbody` during a pure append.

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
(7,675 / 2,857 bytes), and ADR-0026 adds the two targeted region operations
back (8,421 / 3,089 bytes). What remains is code: the keyed region host, the DOM
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
