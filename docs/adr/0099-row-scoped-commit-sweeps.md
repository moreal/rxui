# ADR-0099: A commit walks the rows a transaction moved

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0097 and ADR-0098 took the keyed reconcile out of both single-row paths,
and ADR-0098 closed by naming what that left standing:

> **The per-commit O(N) sweeps.** With the reconcile gone from both
> single-row paths, a ten-thousand-row structural commit is 5.3 ms of which
> none is the region host: the ADR-0088 predicate pass, the ADR-0051 filter
> sweep and the ADR-0063 write-back each walk the whole table for a change
> that touched one row.

This ADR measures those three, folds two of them, and declines the third with
the number that says why.

### The harness, and the boundary it draws

`performance.now()` probes inserted mechanically into the *generated* Toggle
Lab module — one around every loop over a row table, one around the `join`,
one around the `storageSet`, one around the whole commit body — driven with
40 to 300 real dispatches per cell over a region seeded through the ADR-0063
persist format, medians of five page loads. The page is served with
COOP/COEP so Chromium's clock is 5 µs rather than the default 100 µs clamp,
without which every segment below reads zero.

The probe measures **the commit body**: from the transaction shell's
`tx[0] === 0` to its `transaction:commit`. That is a narrower boundary than
ADR-0097 and ADR-0098 used, and the difference is worth stating rather than
leaving as an unexplained factor of six. At ten thousand rows a single-row
append's dispatch returns in **0.86 ms**; forcing the style and layout it
dirtied to completion after every dispatch costs **10.37 ms**. The commit is
about 8% of what a user waits for on a click into a ten-thousand-row list,
and the other 92% is the browser laying the list out — which no compiler
decision here reaches, and which one real interaction pays once per frame
however many dispatches it contains. Every number below, and every ratio in
the result, is commit-scoped.

### Where the time is

Milliseconds, one commit, medians of five page loads:

| rows | action | predicate | filter | encode | `join` | `storageSet` | drain | **commit** |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 | `append` | 0.136 | 0.070 | 0.135 | 0.266 | 0.257 | 0.018 | **0.893** |
| 10 000 | `remove` | 0.168 | 0.051 | 0.074 | 0.276 | 0.264 | 0.027 | **0.873** |
| 10 000 | `toggle` | 0.069 | 0.029 | 0.046 | 0.291 | 0.237 | 0.004 | **0.685** |
| 10 000 | `retype` | 0 | 0 | 0.046 | 0.287 | 0.226 | 0.003 | **0.562** |
| 1 000 | `append` | 0.017 | 0.010 | 0.013 | 0.032 | 0.028 | 0.007 | **0.108** |
| 1 000 | `remove` | 0.022 | 0.010 | 0.011 | 0.032 | 0.032 | 0.007 | **0.117** |
| 1 000 | `toggle` | 0.011 | 0.008 | 0.011 | 0.028 | 0.028 | 0.002 | **0.090** |
| 1 000 | `retype` | 0 | 0 | 0.011 | 0.028 | 0.027 | 0.001 | **0.069** |
| 100 | `append` | 0.006 | 0.006 | 0.005 | 0.005 | 0.006 | 0.008 | **0.040** |
| 100 | `remove` | 0.007 | 0.004 | 0.003 | 0.004 | 0.006 | 0.004 | **0.031** |
| 100 | `toggle` | 0.003 | 0.004 | 0.004 | 0.003 | 0.006 | 0.001 | **0.023** |
| 100 | `retype` | 0 | 0 | 0.005 | 0.003 | 0.005 | 0.001 | **0.015** |

`retype` is the control ADR-0084 built: a keystroke writes `draft`, which no
predicate and no filter arm reads, so both of the foldable sweeps are already
asleep for it and only the write-back runs.

**The finding inverts the round's premise.** The two sweeps this ADR was
asked to fold are 23% of a ten-thousand-row `append` commit and 25% of a
`remove`; the one it was asked to justify keeping is **74%** of the append,
62% of the remove, 84% of the `toggle` and 99.6% of the `retype`. The
opportunity is real and it is not where the question assumed.

### The write-back's two terms, separated

ADR-0096 priced the write-back on a Toggle Lab row, where the row count and
the byte count move together and cannot be told apart. Varying them
independently — arrays of *R* segments of *W* bytes, joined and stored
directly — separates them:

| segments | bytes | `join` | `storageSet` | `join`/row | `storageSet`/byte |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 | 90 kB | 0.130 | 0.060 | 13.0 ns | 0.67 ns |
| 10 000 | 250 kB | 0.215 | 0.155 | 21.5 ns | 0.62 ns |
| 10 000 | 970 kB | 0.475 | 0.835 | 47.5 ns | 0.86 ns |
| 20 000 | 180 kB | 0.230 | 0.125 | 11.5 ns | 0.69 ns |
| 20 000 | 1.94 MB | 1.095 | 2.080 | 54.8 ns | 1.07 ns |
| 1 000 | 385 kB | 0.130 | 0.325 | 130 ns | 0.84 ns |

`storageSet` is **0.6–1.1 ns per byte with no row term at all** — a
thousand-segment 385 kB payload and a ten-thousand-segment 250 kB payload
cost in proportion to their bytes and not to their segments. ADR-0096's
0.85 ns/byte re-verifies. The `join` splits **≈10 ns per row plus
≈0.39 ns per byte**: the row term is about half what ADR-0096's collinear fit
attributed to it and the byte term about four times as large, which is what a
collinear fit gets wrong and in the direction it gets it wrong. At Toggle
Lab's 30.7 bytes per row the two terms are within a few percent of each
other, which is why "18 ns/row plus a negligible byte term" fit the data it
was fit on.

So of the 0.657 ms a ten-thousand-row append spends on the write-back,
**0.34 ms is bytes** — the `storageSet` plus the `join`'s byte term — and
0.24 ms is rows: the `join`'s row term plus the loop that builds the segment
array.

## Decision

**A commit walks the rows the transaction moved.** Two of the three sweeps
fold to that; the third keeps its N, and the measurement says why.

### The predicate accumulator, adopted

A region's ADR-0050 predicate counts and its ADR-0059/0060 predicate-count
selections stop scanning and start **reading cells the region keeps**: one
cell per distinct field equality any of them spells, in the region record's
last slot, behind the ADR-0098 append counter. A region whose aggregates are
all row totals has no cells and its record keeps the length it had.

Every path that moves a row *by name* moves the cells at its own site, from
the row it already has in hand:

- an ADR-0098 `append` adds the new row's contribution, read back off the
  tail the push just extended;
- an ADR-0097 removal — the sealed `remove` action or an ADR-0053 guard hit —
  subtracts the dropped row's, ahead of the `splice`;
- an ADR-0043 row stage subtracts the old tuple's contribution and adds the
  new one, for exactly the cells its own write set can move. That restriction
  is not a new analysis: it is the read/write meet ADR-0084 already computes
  to decide which wake flag each sweep gets, so a `retype` that writes
  `draft` emits no delta at all and an `edit` that writes `mode` emits only
  the `mode` cell's.

Every path that rebuilds the table *wholesale* raises the dirty bit and is
answered by one rescan in the commit — an ADR-0050 broadcast, an ADR-0050
predicate removal, an ADR-0063 hydration, and any removal that fell back.
The rescan is ADR-0088's shared pass, surviving in the one place a traversal
is still owed: one loop over the table filling every cell.

Two properties make the accumulator safe rather than clever.

**The rescan is guarded on the dirty bit alone**, not on any sweep's wake
flag. The cells are region state, so they have to be true whether or not
anything reads them this commit; tying their maintenance to a consumer's wake
condition would make them a cache of something with no owner. It is
consequently the *same block in all sixteen transaction functions*, which is
how a reader can check it.

**The rescan assigns rather than accumulates.** A site that applied a delta
earlier in the same transaction and then raised the dirty bit — the removal
that falls back — is corrected rather than doubled, so the fallback owes
nothing beyond the bit it already raises.

What this replaces is ADR-0088's grouping, not its insight. Sharing one
traversal between the counts and the selections was worth 1.15–1.21× on a
`toggle`; having no traversal is worth more, and the wake-class flags survive
because what they now gate is the compare and the DOM write — which is all
they were ever worth.

### The row-scoped filter sweep, adopted

The ADR-0051 sweep keeps its wake flag, its sealed table and its ADR-0086
displayed-state cell, and changes what it iterates. It visits:

- the ADR-0043 pending positions, and
- the ADR-0098 appended tail, `[length - n, length)`,

unless the transaction raised the dirty bit or changed the filter's own state
field, in which case it visits `[0, length)`. The full sweep is the tail walk
with the whole table as the tail, which is how the emission spells it: one
cursor, seeded at `length - n` on the narrow path and at `0` on the wide one.

Nothing else can have moved a row's selection. A removal takes its row out
and shifts survivors whose fields did not change and whose DOM nodes were
never touched, so it needs no visit and gets none — the sweep wakes, reads
zero rows and writes zero. A state change flips every row at once and is the
`changed` disjunct. A broadcast or a predicate removal is the dirty bit.

The positions are exactly as valid as the two drains that consume them, and
for the same reason: `childAt(container, i)` addresses the container's *i*-th
child, the drains run first, and only after them do the row table and the
host agree. The three values the narrow path needs are snapshotted beside the
wake flags, before the drains empty what they name — the dirty bit the
reconcile is about to clear, the pending array the drain *replaces* rather
than empties, and the append count the drain zeroes.

### The write-back, declined

The ADR-0063 encode loop, `join` and `storageSet` keep walking every row, and
three measurements say why.

**Two-thirds of it is bytes and no row-scoping reaches bytes.** The payload
is the whole table by contract (ADR-0096), one key holding one value, and
0.34 ms of the 0.66 ms is proportional to it.

**The row third costs a positionally-keyed cache, which ADR-0087 already
priced and declined.** A segment array kept on the record would delete the
build loop and the `join`'s row term — 0.24 ms of a 0.89 ms commit — in
exchange for maintaining it at every append, removal, broadcast, predicate
removal and hydration. ADR-0087 measured that trade at 1.5–2.3× and declined
it because a disagreeing cell is a *wrong string in storage* rather than a
stale pixel; ADR-0085's cell survives that objection only because it is keyed
on row identity. Nothing in ADR-0097 or ADR-0098 changes the objection, and
the 0.24 ms is not what changes it either.

**The one layout that would make the write-back row-scoped is two orders of
magnitude worse.** One key per row turns a single-row change into a 30-byte
write: **0.015 ms** against the whole table's 0.235 ms, a 16× win, and it is
the wrong trade by a mile. `setItem` costs **7.2 µs per call** with no regard
for size, so writing all ten thousand keys costs **71.65 ms**, and Toggle
Lab's toolbar has two buttons that write every row. A broadcast would go from
0.66 ms to 71.65 ms — 109× — and hydration would read the table back in
2.39 ms of ten thousand `getItem` calls instead of one. The whole-table write
is the shape that is *flat in the number of rows a transaction changed*, and
against a store with a per-call floor that flatness is the whole value.

So the write-back's N is not an oversight and not a deferral. It is what a
single-valued store costs, priced from both sides.

## Consequences

- Paired A/B against the pre-change emission, both variants in one browser
  process, **ABBA inside every cell of every pass** over twelve passes,
  medians of per-cell medians, every node lookup hoisted out of the timed
  step. An **A/A control** — the same dist against a byte copy of itself —
  runs first and reads **0.951–1.041×** across all sixteen cells, which is
  the bias floor the numbers below are read against.

  | cell | before | after | ratio |
  | --- | ---: | ---: | ---: |
  | 10 000 `append` | 0.857 | 0.656 | **1.31×** |
  | 10 000 five appends | 4.001 | 3.003 | **1.33×** |
  | 10 000 `remove` | 0.781 | 0.597 | **1.31×** |
  | 10 000 `toggle` | 0.715 | 0.580 | **1.23×** |
  | 1 000 `append` | 0.117 | 0.091 | **1.29×** |
  | 1 000 `remove` | 0.061 | 0.044 | **1.40×** |
  | 1 000 `toggle` | 0.077 | 0.065 | **1.19×** |
  | 10 000 `retype` | 0.562 | 0.576 | 0.98× |
  | 10 000 filter flip | 20.51 | 20.34 | 1.01× |
  | 10 000 broadcast | 16.65 | 15.99 | 1.04× |
  | 10 000 hydrate | 48.22 | 50.52 | 0.96× |

  The three controls are the three cases the decision keeps: `retype` touches
  neither folded sweep, the filter flip is the sweep's own wide path, and the
  broadcast is the accumulator's rescan. All three sit inside the A/A band,
  which is the statement that the folds took nothing from the paths they were
  not meant to touch.

- **The witness is a count of rows, not a count of loops.** Two new trace
  entries: `predicate:{region}:read:{n}`, pushed by the rescan and absent
  when the accumulator answered; and `filter:{region}:read:{n}`, pushed
  beside the existing `written` entry. Read together with ADR-0088's
  `Symbol.iterator` walk counter, one Toggle Lab test now pins every case at
  three rows: a `toggle` walks once and reads one row (three walks before), a
  `dblclick` and a keystroke walk once and read none, a filter click walks
  *zero* times and reads all three, an `append` walks once and reads one, a
  broadcast walks three times and reads four and four, and a removal walks
  once and reads **zero**.
- A second test hammers the accumulator's whole invalidation matrix —
  append, toggle, edit, a commit with a draft, a guard-hit removal, a sealed
  removal, a broadcast, a predicate removal and a hydration across a reload —
  and after each one checks all three cells against the row set recomputed
  from the *DOM*: the `items left` count and its ADR-0062 label, the
  clear-completed button's `hiddenIfEmpty`, the toggle-all box's
  `checkedIfEmpty` and the editing hint. A stored accumulator's failure mode
  is a number that is wrong forever rather than a pixel that is stale for one
  frame, and that is the test that would see it.
- **No host change and no new export**, so `runtimeAbi` stays **18**, every
  manifest is byte-identical, the ADR-0094 host surface is untouched and the
  **js-framework-benchmark size gate does not move** — that backend has its
  own emission and never sees this one.
- The ADR-0093 row-order audit is untouched and was the reason for one
  emission choice: an `append` reads its new row back off the table's tail
  rather than binding the pushed literal to a name, because R2 requires a
  push's argument to *be* an array literal headed by the region's own key
  counter, and an element read is a row binding the audit already follows.
- Generated modules change wherever a region has a predicate aggregate or a
  filter: Toggle Lab, Mix Lab, Twin Lab. Every other generated module is
  unchanged, and all fifteen artifact gates pass.

## Open questions

1. **The layout that dwarfs all of this.** A ten-thousand-row append's
   commit is 0.86 ms and the style and layout it dirties are 9.5 ms. Nothing
   in the commit reaches that, but the *row template* might: the sweep now
   writes `hidden` on exactly the rows that moved, and whether a row's
   attribute writes are batched, ordered or deferred relative to the frame is
   a question this line of ADRs has never asked.
2. **The write-back's row third, if the cache ever becomes identity-keyed.**
   ADR-0085's serialization cell is safe because it hangs off the row. A
   *segment array* is positional and therefore is not. The 0.24 ms is only
   reachable by something that keeps the row's serialization and its position
   in the same place, and nothing in the record does today.
3. **The bulk threshold, still open from both ends.** ADR-0097 declined
   `removeIf`, ADR-0098 declined hydration, and this ADR declines neither
   because it touches neither — but the accumulator's rescan is now a third
   O(N) thing gated on the same dirty bit, so whatever threshold answers that
   question will have three subjects rather than two.
