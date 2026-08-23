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

- Measured at: 2026-08-23 10:00:25 UTC
- LeanRx commit: `aeb6bdf661b1dd81e347e4cfcf4ba19510a854e7` plus the uncommitted
  ADR-0027 keyed-region host change (tree state: dirty; see ADR-0027 and the
  archived `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T100025Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.7 | 31.8 | 30.7 |
| Replace all 1,000 rows (ms) | 46.8 | 36.0 | 33.6 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 27.5 | 22.7 | 18.9 |
| Select row, 4× CPU slowdown (ms) | 10.8 | 7.5 | 6.4 |
| Swap rows, 4× CPU slowdown (ms) | 153.5 | 23.3 | 23.1 |
| Remove row, 2× CPU slowdown (ms) | 19.7 | 17.5 | 16.8 |
| Create 10,000 rows (ms) | 664.3 | 362.8 | 323.1 |
| Append 1,000 rows to 1,000 rows (ms) | 45.2 | 39.4 | 36.6 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 28.0 | 19.9 | 16.2 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.60 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 2.01 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.79 | 0.71 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 10.10 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 3.50 |
| Startup time to first paint (ms) | 333.70 | 78.90 | 93.80 |

## Change from the previous run

The previous recorded run (commit `65130a6` plus the ADR-0026 region-host and
backend changes that became `aeb6bdf`, same runner, headless, the same three
frameworks) measured LeanRx at 29.9 ms create 1,000, 33.1 ms replace, 19.3 ms
partial update, 5.3 ms select, 20.3 ms swap, 16.9 ms remove, 325.0 ms create
10,000, 35.8 ms append, and 14.7 ms clear, with 9.90 KB uncompressed / 3.40 KB
Brotli and 68.6 ms to first paint. This run ships the ADR-0027 keyed region
host (runtime ABI unchanged): keys that are all numbers, all bigints, or all
strings and strictly increasing or decreasing are validated as distinct
without the key index, which is now built only when a retained key is found
away from its position and dropped when nothing is retained, so the
benchmark's creates and appends (model rows in id order) never hash a key; the
Lean models, the backend, and every other operation are unchanged. Create
10,000 script falls 28.1 → 27.4 ms (Solid 34.6 → 36.7) for 325.0 → 323.1 ms
total (Solid 345.6 → 362.8), the one row this change targets; it is the only
CPU row that moved against the run's drift, which was slower this time for
every framework (Solid's create 1,000 31.0 → 31.8, replace 35.7 → 36.0,
partial update 20.0 → 22.7, swap 23.5 → 23.3, append 37.5 → 39.4, clear 18.5
→ 19.9). LeanRx moved with it: create 1,000 29.9 → 30.7 (script 2.7 → 2.7),
replace 33.1 → 33.6 (script 5.4 → 5.4), partial update 19.3 → 18.9, select
5.3 → 6.4, swap 20.3 → 23.1 (script 0.40 → 0.43, paint 17.6 → 19.5; Solid
script 1.97 → 1.95, paint 19.3 → 18.7, so the row is the table relayout and a
coin flip again), remove 16.9 → 16.8, append 35.8 → 36.6 (script 3.0 → 3.0),
and clear 14.7 → 16.2; every CPU row is below Solid's. The shipped
application grows from 9.9 to 10.1 KB uncompressed and from 3.4 to 3.5 KB
Brotli (local baseline 10,087 → 10,380 raw, 3,449 → 3,540 Brotli bytes, of
which `main.mjs` is 8,714 / 3,180 against Solid's single 11,563 / 4,358-byte
module), the cost of the monotone check and the lazy index. First paint is
one `performance.getEntriesByType("paint")` sample per framework and moved
68.6 → 93.8 ms while Solid moved 73.1 → 78.9 ms and React Hooks 309.0 →
333.7 ms; across the last five runs LeanRx measured 77.6, 77.8, 81.3, 68.6,
and 93.8 ms against Solid's 81.3, 81.5, 76.8, 73.1, and 78.9 ms, so the row
does not separate the two. Memory after page load is 0.60 → 0.60 MB for
LeanRx and 0.53 → 0.61 MB for Solid, and after adding 1,000 rows 2.03 → 2.01
MB (Solid 2.70 → 2.70).

## Where the remaining time goes

Profiled locally on 2026-08-23 before ADR-0027 (Chrome DevTools sampling
profiler at 50 µs through Playwright, started and stopped around each
create-10,000 click with the clearing click unprofiled, 24 clicks, warm JIT;
a diagnostic, not the upstream runner): the click handler costs LeanRx 24.7
ms against vanilla's 22.5, and the self times that differ are garbage
collection (11.8 against 9.7 ms, the survivor volume of the per-row entry,
handle, row array, BigInt, and key string), the keyed region's `update` (0.85
ms, almost all of it the key index), and `cloneNode` (13.1 against 12.4 ms,
the two `data-lrx-action` attributes the row template carries). Storing the
row handle as node properties, keeping the BigInt key itself as the node's
key, and both together changed nothing in a paired comparison. ADR-0027
removes the index work: with the monotone check and the lazily built index
the handler measures 23.7 ms and the paired harness below puts create 10,000
0.9 ms and create 1,000 and replace about 0.1 ms below the previous host,
the other operations unchanged; against vanilla the remaining paired gaps are
create 10,000 1.3 ms, replace 0.35, append 0.2, create 1,000 0.16, partial
update 0.04, swap 0.01, and clear 0. Removing the two per-row action
attributes from the template would recover about 0.4 ms of the create-10,000
gap (measured by deleting them, which breaks the row clicks) but needs the
delegated listener to resolve actions structurally instead of by attribute,
a change to the DOM host's contract that was not made; a disjoint-key-range
shortcut for a replacement with fresh ids measured 0.1 ms on replace for 103
Brotli bytes and was not adopted either.

Measured locally on 2026-08-23 before ADR-0027 (Playwright-driven headless
Chromium, no CPU throttling, `performance.now()` around the click handler; a
paired harness that loads LeanRx and the upstream vanilla implementation
alternately and takes several measured clicks per page, so a difference of
0.1 ms is resolvable where fresh-page medians drift by about 0.5 ms between
runs; a diagnostic, not the upstream runner): creating 10,000 rows costs
LeanRx about 2.4 ms more script than vanilla once the JIT is warm (about 3 ms
from a fresh page, the upstream condition). That harness could not see the
key index (removing the index insertion changed nothing visible there, and in
isolation the index costs about 0.5 ms per 10,000 BigInt keys while the
per-row entry objects cost nothing measurable; the profile above, with more
clicks per page, puts it at 0.8 ms). The rest is the DOM shape and the id
representation — giving
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
(7,675 / 2,857 bytes), ADR-0026 adds the two targeted region operations
back (8,421 / 3,089 bytes), and ADR-0027 adds the monotone-key check and the
lazily built index (8,714 / 3,180 bytes). What remains is code: the keyed region host, the DOM
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
