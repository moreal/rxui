# ADR-0102: Taking a filtered row out of the container

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0101 measured what a filter costs the browser and declined every lowering
it priced, leaving one open question and the number that makes it one:

> **The detach lowering, priced but not taken.** Removing a filtered row from
> its container instead of hiding it is 76× at ten thousand rows and ends the
> run-length law entirely […] The round it needs is a host round: a region
> that knows which of its rows are attached, an `insertAt` anchor that skips
> the detached ones, and an `ownsWholeParent` that still recognises its own
> container.

The 76× was measured on half a flip. ADR-0101 timed the *hide* direction and
timed it on the easy shape: a contiguous prefix pulled out with `node.remove()`
and put back before one anchor. A filter is an arbitrary subset, and a filter
that hides also un-hides, so the number that decides this is the round trip
with the anchor search in it.

## The measurement

Framework-free first, on the Toggle Lab row shape (four cells, one checkbox,
two buttons), ten thousand and one thousand rows, `k` deselected either as a
contiguous prefix or spread one in every `N/k`. The write and the forced
style-and-layout after it are timed apart, in **both** directions, and every
cell re-asserts that the container holds every row in table order before it is
believed. Medians of three to five.

| N/k | shape | hide write | hide forced | show write | show forced | round |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 10 000 / 1 000 prefix | `hidden` | 0.25 | 53.21 | 0.18 | 22.45 | 76.09 |
| | detach | 2.27 | 7.63 | 0.33 | 22.35 | **32.58** |
| 10 000 / 5 000 prefix | `hidden` | 1.35 | 1 096.06 | 0.87 | 84.13 | 1 182.41 |
| | detach | 11.19 | 3.86 | 1.62 | 84.50 | **101.15** |
| 10 000 / 5 000 spread | `hidden` | 1.60 | 23.31 | 1.05 | 86.17 | 112.12 |
| | detach | 12.93 | 3.61 | 1.51 | 82.45 | **100.50** |
| 10 000 / 10 000 | `hidden` | 2.51 | 4 360.62 | 1.06 | 179.88 | 4 544.06 |
| | detach | 21.97 | 0.06 | 3.15 | 172.33 | **197.50** |

**The show direction is a wash and the hide direction is everything.** Putting
five thousand rows back costs 84 ms of forced style and layout whether they
were `hidden` or detached — they start rendering again either way, and that is
the cost — while *taking* five thousand adjacent rows out of rendering costs
1 096 ms as layout-less siblings and 3.9 ms as absent ones. So the round trip
is **11.7×** at that cell, 23× when every row is deselected, 2.3× at a
thousand rows deselected of ten thousand, and **1.12× in the spread case**,
where ADR-0101's law had already made hiding cheap. Nothing loses. Paired,
ABBA inside every pass, against an A/A control of 0.912–1.048×, the same eight
cells read 1.03–21.62×.

### The anchor search is the whole implementation risk

Re-showing `k` rows is `k` `insertBefore` calls, and each one needs the node
its row goes before. Three ways of finding it, same cells:

| N/k | forward scan | backward scan | one descending pass |
| --- | ---: | ---: | ---: |
| 10 000 / 1 000 prefix | 4.05 | 0.33 | 0.40 |
| 10 000 / 5 000 prefix | **98.28** | 1.62 | 1.54 |
| 10 000 / 10 000 | **383.14** | 3.15 | 2.97 |

Looking *forward* for the first still-displayed row is O(N) per call whenever
a long run is out — which is exactly the case worth optimising — and it costs
more than the 1 096 ms it was meant to save at the largest cell. Looking
*backward* for the nearest already-displayed row is O(1) amortised against an
ascending sweep, because after the sweep places row `i` the row `i+1` finds it
immediately, and a run of rows that stay out is crossed once by the first
placement after it. It ties a batched descending pass over the whole table
(1.62 against 1.54, 3.15 against 2.97) without needing the sweep to hand the
host a batch, so the export stays one call per row, exactly like the write it
replaces.

### The real emission, paired

Two dists of the generated Toggle Lab — the previous commit's per-row `hidden`
sweep against this round's — one page each plus a second page of the baseline
as the **A/A control**, ABBA inside every pass, per-cell minima, medians of the
pass values. What is timed is the whole flip in both directions: the dispatch
and the forced style and layout after it returns, so the ADR-0051 sweep, the
ADR-0050 counts, the ADR-0063 write-back and the route write are all inside
every number.

| cell | A/A | per-row `hidden` | detach | ratio |
| --- | ---: | ---: | ---: | ---: |
| 10 000 rows, all deselected | 1.103× | 5 946.93 | 297.72 | **19.97×** |
| 10 000 rows, 5 000 contiguous | 1.024× | 1 421.98 | 172.22 | **8.26×** |
| 1 000 rows, all deselected | 1.006× | 79.35 | 26.81 | **2.96×** |
| 1 000 rows, 500 contiguous | 1.007× | 30.33 | 16.26 | **1.86×** |
| 10 000 rows, 1 000 contiguous | 1.017× | 127.09 | 76.10 | **1.67×** |
| 10 000 rows, 5 000 spread | 0.907× | 182.38 | 162.46 | 1.12× |
| 1 000 rows, 500 spread | 0.998× | 17.73 | 16.11 | 1.10× |
| 100 rows, 50 contiguous | 0.985× | 2.23 | 2.06 | 1.09× |

The A/A control is **0.907–1.103×** here rather than the framework-free
0.912–1.048×, because the real flip carries the ADR-0063 write-back and its
`localStorage` cost, which ADR-0098 already found is what widens a paired
cell's band. Read against it, the three cells at the bottom are *inside* their
own control — the scattered distributions ADR-0101's law already made cheap,
and the hundred-row list where nothing costs anything — and the five above are
real, from 1.67× to nearly twenty. The shape of the result is the same as the
framework-free one with the rest of a commit added on top: **the win is the
run length, and the run length is the data.**

## Decision

**A deselected row leaves its container.** The sweep's write becomes the keyed
region handle's new `setDisplayed(index, key, displayed)`, `runtimeAbi` moves
19 → 20, and the identity that ADR-0092, ADR-0094 and ADR-0097/0098/0100 all
rest on — a row's position in the row table is its position among the
container's children — is not abandoned but **moved into the host**, which is
the only place that holds both halves of it.

### What the host owes, entry point by entry point

A row is displayed exactly when its node is in the parent. Nothing in the
region caches that, because the DOM already says it; `hiddenRows` is a counter
and it is only ever read as the O(1) test for whether any of the work below is
needed at all.

- **`setDisplayed(index, key, displayed)`** checks the key at the position
  (`LRX-REGION-003`, the same check `removeAt` and `removeMany` carry), returns
  without a write when the row is already in the asked-for state, and otherwise
  detaches the node or inserts it before the *displayed* anchor its position
  names — the nearest displayed row before it, falling forward to the first
  displayed row after it, falling to the marker. No callback runs and no metric
  moves: a selection is not a mount, an update, a placement or a disposal, and
  every existing region-metric assertion still reads what it read.
- **`insertAt`** anchors on the first displayed row at or after `index` instead
  of on `current[index].node`, which may be detached. An append — the only
  insertion the language emits — hits the marker on the first step, so the
  common path is unchanged.
- **`removeAt`/`removeMany`** need nothing: `detach` is already
  `parentNode`-guarded, and `ownsWholeParent` already returns false when the
  parent is short of a row, so the bulk clear turns itself off while any row is
  out and turns itself back on when none is. The one addition is keeping the
  counter honest across a removal.
- **`update`** — the full reconcile, whose prefix and suffix scans, whose
  longest-increasing placement and whose owned-parent clear all read the
  parent's children *as* the row table — puts every detached row back at its
  table position first and takes the same survivors out again after. One
  descending pass carries the anchor, so the restore is one walk of the table
  however many rows are out, and no forced layout can intervene between the two
  halves because they are in one call. `placeInOrder` and `rebuild` are
  untouched.
- **`swapAt`** places each of the two nodes that is displayed at the anchor its
  new position names, and leaves a detached one detached. The path is behind
  `hiddenRows === 0`, so the js-framework-benchmark backend — which inlines the
  whole keyed host and is the only caller of `swapAt` — takes the same two
  moves it always did.

`childAt(container, i)` is no longer used by the filter path, and with it goes
**the region record's filter slot**: ADR-0051 put the container element on the
record so the sweep could navigate from the context alone, and the handle has
had the container since it was constructed. The ADR-0075 child inventory, the
ADR-0097 drops queue, the ADR-0098 append counter and the ADR-0099 accumulator
each move down one slot, and a filtered region's record is one shorter.

### What this changes that is not a number

**A deselected row is unreachable.** The delegated listener is on the
container, so nothing dispatches for a row the filter is not showing — a user
could never reach a `hidden` row either, but a script could, and the twin and
toggle gates each had one test that did. The tests now drive the row through
the filter that shows it, and one of them asserts the new fact directly:
clicking a detached row's own Remove button moves nothing at all.

**A row root's `hidden` property is no longer written by anything.** Row scope
still has no `hidden` selection to conflict with, so nothing is unsealed; what
changes is that the ADR-0086 cell now caches a *selection* rather than the last
value of a DOM property.

**Everything a detached row carries survives.** It keeps its handle, its node,
its listeners, its ADR-0060 reflected `checked` and its ADR-0085 serialization
cell, and it comes back as the same node object at its own table position —
which the gates assert by identity, not by text.

## Consequences

- **`runtimeAbi` moves 19 → 20** with twenty-six mechanical references: the
  version constant, seventeen artifact gates, six Lean backend tests, the
  scalar manifest string and the CLI doctor's line. `setDisplayed` is declared
  in the ADR-0094 contract surface (`H3`) taking no caller array, and the host
  gate grows a section for it.
- **The js-framework-benchmark size baseline moves again.** That backend
  inlines the whole keyed host, so `main.mjs` grows 9 345 → **10 351** raw
  bytes (+10.8%, brotli 3 400 → 3 638, gzip 3 751 → 4 032) for an export it
  never calls, plus the anchor helpers and the reconcile's restore bracket that
  its own `update` and `swapAt` now carry behind a zero test.
- **Three generated modules change** — Toggle, Mix and Twin, exactly the three
  labs that declare a filter. Toggle Lab's gets **58 bytes smaller** (201 336 →
  201 278), because the record lost a slot and the sweep lost a `childAt` call
  at every one of its thirty-two sites; Mix Lab's grows 23 bytes and Twin Lab's
  273, where the same slot arithmetic saves less than the row key the new call
  carries costs. Every other generated module is byte-identical.
  `leanrx_region.mjs` changes in all eight bundles that ship it — Branch, Grid,
  Issue Browser, Mix, Nest, Todo, Toggle and Twin — growing 15 658 → 20 644
  bytes. **Every manifest changes**, by the `runtimeAbi` field alone, plus
  `graphHash` for the three modules whose text moved; the graph JSONs of the
  labs whose Lean doc comments this round rewrote move by source line and byte
  offset only.
- **The measurement stands on the round trip, not on the flip.** Any future
  round quoting this one has to quote both directions: hiding is where the
  browser charges and showing is where both shapes pay the same.

## Open questions

1. **The show direction is now the largest term and nothing here touched it.**
   Putting five thousand rows back costs 84 ms of forced style and layout and
   172 ms for ten thousand, identically in both shapes, because that is what
   rendering them costs. Whether a region can show fewer of them — a window, a
   budget, an incremental reveal — is a language question this ADR does not
   open, and the number that would justify it is the one above.
2. **`swapAt` and the filter cannot meet, and the host is written as though
   they could.** No emission puts a swap and a filter on one region, so the
   displayed-anchor branch in `swapAt` is exercised only by the host gate. It is
   there because a shared host that is correct only for the callers that exist
   today is a trap, but it is untested by any generated program.
3. **The write-back is still the largest term of a commit.** ADR-0100's third
   open question is untouched for the third round running.
