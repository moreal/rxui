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

- Measured at: 2026-08-23 13:44:09 UTC
- LeanRx commit: `7f4dfbf0c693dae4fc9a44fda3a1d0d3c4427702` (ADR-0031) plus the
  uncommitted ADR-0032 benchmark-backend and page change (tree state: dirty;
  see ADR-0032 and the archived `repository-changes.patch`)
- Chrome mode: headless (headless is suitable for
  regression tracking; see the integration guide for why visible Chrome is
  preferred for publishable comparisons)
- Repetition count: upstream default
- Host: Darwin 25.6.0, arm64 (macOS)
- Node v22.23.2, Lean 4.33.0, Lake 5.0.0-src+d8b1897

Full raw JSON per benchmark, Chrome traces, the generated LeanRx framework
snapshot, the exact repository patch, and this environment metadata are
archived under `.tmp/js-framework-benchmark-results/20260823T134409Z/` (not
committed; regenerate with the command above).

Lower is better in every table below.

## CPU workloads

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Create 1,000 rows (ms) | 39.5 | 32.6 | 30.2 |
| Replace all 1,000 rows (ms) | 48.3 | 37.4 | 34.4 |
| Partial update, every 10th row, 4× CPU slowdown (ms) | 30.2 | 22.8 | 23.6 |
| Select row, 4× CPU slowdown (ms) | 10.8 | 6.6 | 6.5 |
| Swap rows, 4× CPU slowdown (ms) | 144.6 | 24.7 | 22.2 |
| Remove row, 2× CPU slowdown (ms) | 19.8 | 18.2 | 17.2 |
| Create 10,000 rows (ms) | 637.8 | 345.8 | 314.3 |
| Append 1,000 rows to 1,000 rows (ms) | 44.2 | 37.3 | 36.1 |
| Clear 1,000 rows, 4× CPU slowdown (ms) | 26.8 | 18.4 | 14.3 |

## Memory

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Memory after page load (MB) | 1.18 | 0.61 | 0.60 |
| Memory after adding 1,000 rows (MB) | 4.42 | 2.60 | 1.91 |
| Memory after adding then clearing rows (MB) | 1.87 | 0.69 | 0.70 |

## Startup and size

| Benchmark | React Hooks | Solid | **LeanRx** |
|---|---:|---:|---:|
| Uncompressed JS size (KB) | 190.30 | 11.50 | 9.70 |
| Compressed (Brotli) JS size (KB) | 51.40 | 4.50 | 3.40 |
| Startup time to first paint (ms) | 322.90 | 75.80 | 79.70 |

## Change from the previous run

The previous recorded run (commit `5b95540`, ADR-0030, same runner, headless,
the same three frameworks, measured 67 minutes earlier) measured LeanRx at
31.7 ms create 1,000, 35.1 ms replace, 24.6 ms partial update, 7.1 ms
select, 24.7 ms swap, 18.6 ms remove, 333.2 ms create 10,000, 37.4 ms
append, and 15.6 ms clear, with 10.60 KB uncompressed / 3.60 KB Brotli, 1.99
MB after adding 1,000 rows, and 74.1 ms to first paint. This run ships two
size-only changes and no host change (runtime ABI stays 15): ADR-0031 prunes
the flattened module to the host declarations reachable from the mount
statement (the six DOM-host functions this application never calls and
`uniqueId`'s counter leave it), and ADR-0032 routes the six buttons through
the structural `listenDelegatedCells` listener on a `setKey`-marked button
row, so the attribute adapter (`listenDelegated` and its key walk) and the
buttons' `data-lrx-action` attributes leave the module and the page. Nothing
the measured operations run changed: the paired local harness below puts
create 10,000 and create 1,000 within the day's control floor (two copies of
the same build differed by 0.12 ms under the protocol, so a 0.1 ms sign is
not resolvable today). The shipped application shrinks from 10.6 to 9.7 KB
uncompressed and 3.6 to 3.4 KB Brotli (local baseline 10,902 → 9,937 raw,
3,699 → 3,452 Brotli bytes; `main.mjs` 9,236 / 3,339 → 8,479 / 3,115 against
Solid's single 11,563 / 4,358-byte module, `index.html` 1,666 / 360 → 1,458
/ 337).

The CPU rows moved with the run, which drifted faster for every framework:
create-10,000 script 24.6 → 23.6 ms (15 samples, σ 0.2) for 314.3 ms total
with paint 296.6 → 279.9, while Solid's script moved 36.3 → 34.9 and its
paint 312.2 → 299.4 in the same run, so LeanRx's share of Solid's script is
0.68 in both runs (the ratio, not the absolute row, is the comparable
signal); create 1,000 script 2.43 → 2.39, replace 5.33 → 5.24, append 2.82
→ 2.71, and the throttled rows create 1,000 total 31.7 → 30.2 (Solid 33.1 →
32.6), replace 35.1 → 34.4 (Solid 38.9 → 37.4), select 7.1 → 6.5 (Solid 8.8
→ 6.6), swap 24.7 → 22.2 (Solid 27.9 → 24.7), remove 18.6 → 17.2 (Solid
19.4 → 18.2), clear 15.6 → 14.3 (Solid 20.0 → 18.4) all drifted the same
way. Partial update 24.6 → 23.6 reads above Solid's 22.8 this time (script
1.37 against 1.67, paint 18.5 against 17.7; the row is paint-bound and has
flipped between the two in earlier runs: 20.9 against 20.7, 21.2 against
23.1, 24.6 against 25.1). Memory after adding 1,000 rows reads 1.99 → 1.91
MB (Solid 2.70 → 2.60), after clearing 0.79 → 0.70, after page load 0.60 →
0.60. First paint moved 74.1 → 79.7 ms while Solid moved 77.2 → 75.8 ms;
across the last nine runs LeanRx measured 77.6, 77.8, 81.3, 68.6, 93.8,
72.3, 75.3, 74.1, and 79.7 ms against Solid's 81.3, 81.5, 76.8, 73.1, 78.9,
74.5, 70.7, 77.2, and 75.8 ms, so the row does not separate the two.

## Where the remaining time goes

Measured locally on 2026-08-23 after ADR-0028 (the paired harness below, now
with a forced garbage collection before each measured click: the
create-10,000 samples had split into two modes about 4 ms apart — ≈18 ms
when no major collection landed in the click and ≈22 ms when one did — which
round medians straddle, and the forced collection makes every click the
same case; two copies of one build then differ by 0.01 ms): representing the
row ids as Numbers instead of BigInts (ADR-0029) is worth 0.26 ms per
create-10,000 click (9 of 10 rounds negative), 0.11 ms per replace, and
nothing on create 1,000; the paired profile puts the difference in
`buildData` (the allocation per id), the monotone-key comparisons, and the
per-mount `String()` rendering, with garbage collection unchanged. The last
structural difference to vanilla's row markup was the two `data-lrx-action`
attributes per cloned row: resolving the row's action from the cell that
contains the click (ADR-0030, `listenDelegatedCells`) removes them and
measures −0.63 ms per create-10,000 click under the same protocol (every
round negative), −0.04 on create 1,000, −0.05 on replace and append, 0 on
select, and +0.01 ms on remove. A cloned row now differs from vanilla's only
by the `setKey` expando, and under the same protocol LeanRx's create-10,000
click measures 0.67 ms below the upstream vanilla implementation's (9 of 10
rounds), so the create path has no remaining gap to close there. ADR-0031
and ADR-0032 changed no code the measured clicks run; under the same
protocol they read +0.11 / −0.08 ms on create 10,000 in two orderings and
−0.04 on create 1,000 while two copies of one build differed by 0.12 ms that
session (against 0.01 earlier), so the control floor must be re-measured
before a 0.1 ms sign is read.

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
lazily built index (8,714 / 3,180 bytes), ADR-0028 adds the text-slot
walker (8,820 / 3,225 bytes), ADR-0029's Number ids trim two bytes
(8,818 / 3,224 bytes), and ADR-0030 adds the structural click listener
(9,236 / 3,339 bytes), and ADR-0031 drops the host declarations nothing
reachable from the mount statement references — six DOM-host functions this
application never calls and `uniqueId`'s counter — from the flattened module
(8,942 / 3,251 bytes), and ADR-0032 routes the six buttons through the
structural listener on a `setKey`-marked button row so the attribute adapter
(`listenDelegated` with its key walk) leaves the module too (8,479 / 3,115
bytes); printing `!(a === b)` as `a !== b` and returning from the row search
at the first match trim 32 raw / 11 Brotli more (8,447 / 3,104 bytes). What
remains is code: the keyed region host, the DOM host functions
the application reaches with the disposer, the generated module, and
`index.html` (1.5 KB / 0.34 KB, excluded from the upstream size score, which
counts JavaScript only).

## Reading these numbers

- CPU and memory numbers are single-run means from an automated headless
  Chrome session on one developer machine; treat them as a snapshot for
  regression tracking, not a definitive cross-framework ranking. Re-run
  `corepack pnpm benchmark:compare` in visible Chrome, idle machine, for
  publishable comparisons.
- Size numbers reflect the complete fetched application (see the [local byte
  baseline](docs/performance/js-framework-benchmark.md#deterministic-local-gate)):
  since ADR-0023 one flattened module holding the region and DOM host
  declarations the application reaches (ADR-0031 drops the unreachable ones
  at build time), compacted (ADR-0024); the structural-delta,
  conditional/positional, and form-event hosts are shipped only by artifacts
  that import them, and no other example's hosts are pruned.
- A regression in one category is not offset by an improvement in another;
  read CPU, memory, and size as independent signals.
