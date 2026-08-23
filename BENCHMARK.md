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

- Measured at: 2026-08-23 10:50:35 UTC
- LeanRx commit: `d5b1254e9ad7eb7246b5e4df9baa3d992f237372` plus the uncommitted
  ADR-0028 DOM-host and benchmark-backend change (tree state: dirty; see
  ADR-0028 and the archived `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T105035Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 38.2 | 32.4 | 30.4 |
| Replace all 1,000 rows (ms) | 51.3 | 36.2 | 33.4 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 27.1 | 20.7 | 20.9 |
| Select row, 4× CPU slowdown (ms) | 10.5 | 7.1 | 6.0 |
| Swap rows, 4× CPU slowdown (ms) | 155.1 | 25.7 | 21.5 |
| Remove row, 2× CPU slowdown (ms) | 21.2 | 18.6 | 17.3 |
| Create 10,000 rows (ms) | 656.7 | 353.4 | 323.9 |
| Append 1,000 rows to 1,000 rows (ms) | 45.7 | 37.3 | 36.9 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 27.6 | 18.9 | 15.1 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.60 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.70 | 1.97 |
| Memory after adding then clearing rows (MB) | 1.97 | 0.79 | 0.72 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 10.20 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 3.50 |
| Startup time to first paint (ms) | 317.70 | 74.50 | 72.30 |

## Change from the previous run

The previous recorded run (commit `aeb6bdf` plus the ADR-0027 keyed-region
host change that became `986a7f9`, same runner, headless, the same three
frameworks) measured LeanRx at 30.7 ms create 1,000, 33.6 ms replace, 18.9 ms
partial update, 6.4 ms select, 23.1 ms swap, 16.8 ms remove, 323.1 ms create
10,000, 36.6 ms append, and 16.2 ms clear, with 10.10 KB uncompressed / 3.50
KB Brotli, 2.01 MB after adding 1,000 rows, and 93.8 ms to first paint. This
run ships ADR-0028 (runtime ABI 14): the DOM host gains `nextText(node)`, the
Text node that follows a node in document order through one shared
`TreeWalker(SHOW_TEXT)`, and the benchmark backend mounts each row with two
`nextText` calls instead of four `firstChild`/`nextSibling` reads, so a row
allocates three DOM wrappers (`tr` and its two text slots) instead of six
(the cells and the link between them were wrapped only to be stepped over);
the Lean model, the region host, and every other operation are unchanged.
Create 10,000 script falls 27.4 → 24.9 ms (15 samples, σ 0.5; Solid 36.7 →
35.5), the one row this change targets, and create 1,000 script 2.7 → 2.5,
replace 5.4 → 5.3, and append 3.0 → 2.9 move the same way; the totals are
the table relayout either way and moved with the run's paint drift (create
10,000 323.1 → 323.9 with paint 285.2 → 288.1 while Solid's paint went 313.7
→ 305.8; create 1,000 30.7 → 30.4; replace 33.6 → 33.4; append 36.6 → 36.9).
The throttled rows drifted as they do: partial update 18.9 → 20.9 (script
1.14 → 1.33 ± 0.39, median 1.10; Solid 22.7 → 20.7, so the row is a coin
flip again), select 6.4 → 6.0, swap 23.1 → 21.5 (script 0.43 → 0.51, paint
19.5 → 18.6; Solid 23.3 → 25.7), remove 16.8 → 17.3, clear 16.2 → 15.1;
every CPU row except partial update (20.9 against 20.7) is below Solid's.
Memory after adding 1,000 rows falls 2.01 → 1.97 MB (Solid 2.70), the three
thousand wrappers the rows no longer allocate; after page load it is 0.60 →
0.60 MB and after clearing 0.71 → 0.72. The shipped application grows from
10.1 to 10.2 KB uncompressed at 3.5 KB Brotli (local baseline 10,380 →
10,486 raw, 3,540 → 3,585 Brotli bytes, of which `main.mjs` is 8,820 / 3,225
against Solid's single 11,563 / 4,358-byte module), the cost of the helper.
First paint is one `performance.getEntriesByType("paint")` sample per
framework and moved 93.8 → 72.3 ms while Solid moved 78.9 → 74.5 ms; across
the last six runs LeanRx measured 77.6, 77.8, 81.3, 68.6, 93.8, and 72.3 ms
against Solid's 81.3, 81.5, 76.8, 73.1, 78.9, and 74.5 ms, so the row does
not separate the two.

## Where the remaining time goes

Profiled locally on 2026-08-23 after ADR-0027 and before ADR-0028 (the same
sampling profiler, now with one page per implementation kept open and the
profiled clicks alternated between them so drift is paired, 24 clicks each):
the create-10,000 handler costs LeanRx 23.4–23.9 ms against vanilla's
22.3–22.5, and the whole difference is garbage collection (about +1.3 to +2
ms) plus `cloneNode` (+0.6 ms, the two `data-lrx-action` attributes); every
other self time is level, and dropping the per-row handle array measured
−0.3 ms, within noise. The young-generation volume on both sides is the DOM
wrappers: a row mount read `firstChild`/`nextSibling` four times to reach
the id cell's text and the select link's text, so every row allocated six
wrappers (`tr`, `td`, text, `td`, `a`, text) that survive while the node is
in the document, and vanilla does the same. ADR-0028 reaches the two text
nodes with a shared `TreeWalker(SHOW_TEXT)` (`nextText`, three binding calls,
no wrapper for the elements stepped over): the handler measures 22.2 ms with
garbage collection down about 1.7 ms, the paired harness below puts create
10,000 1.24 ms below the previous host (every round negative) and 0.15 ms
below vanilla, create 1,000 0.12 ms and replace 0.08 ms below the previous
host, and append now 0.09 ms above vanilla (0.2 before); replace remains
0.28 ms above vanilla (the dispose pass and the region's per-row entries over
a bulk clear that vanilla does with one `textContent` write). A walker
created per row instead of one shared walker costs 1.0 ms more and was
rejected; a stateful "continue from the last result" form measured the same
as the stateless `nextText(node)` and the stateless one was adopted. A swap's
two DOM moves were re-checked and are final: one move shifts every row
between the two positions, and exchanging the rows' contents instead of the
nodes would fail the upstream keyed node-identity check.

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
back (8,421 / 3,089 bytes), ADR-0027 adds the monotone-key check and the
lazily built index (8,714 / 3,180 bytes), and ADR-0028 adds the text-slot
walker (8,820 / 3,225 bytes). What remains is code: the keyed region host, the DOM
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
