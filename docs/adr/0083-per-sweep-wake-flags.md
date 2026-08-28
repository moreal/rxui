# ADR-0083: A region's wake flags are derived from its sweeps' read sets

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0082 narrowed *one* sweep. A region's touched flag —
`regions[i][3] || regions[i][4]["length"] !== 0` — folds two events into
one predicate: the row set changed, or a `row` update queued a position for
the drain. Only the first can move a sweep that reads no row field, or one
whose fields the drain never writes. ADR-0082 acted on that for the filter
table and left the three sweeps beside it — the ADR-0050 counts, the
ADR-0058/0059/0060 emptiness and checked selections, and the ADR-0063
persistence write-back — waking on the uniform flag, with the browser
witness pinning the boundary in the *opposite* direction: it asserted that
a `mark` drain still re-evaluates Twin Lab's row total.

That boundary is where this round starts. The question is whether the
per-sweep read set is a total rule, what narrowing it moves, and what it is
worth.

### The read sets, from the spec

Each sweep's read set is fixed by the surface that declares it:

| sweep | read set |
| --- | --- |
| `{count r}` — the row total | the row array's `length`; **no field** |
| `{count r (f == "x")}` — the predicate count | `f` |
| `hidden={count r == 0}` — the ADR-0058 emptiness subject | the row array's `length`; **no field** |
| `hidden={count r (f == "x") == 0}`, `checked={…}` — ADR-0059/0060 | `f` |
| `filter r by s := when … (f == "x")` | every arm predicate's subject fields |
| `persist r := "key"` | **every** field of the row |

The ADR-0062 label count rides its own count's read set: the string it
picks is a function of that number alone. A trimmed or composed filter
subject counts every field it projects (`fieldRefs`), as ADR-0082 already
had it.

The write set is unchanged: the assignment targets of every declared `row`
update stage, the ADR-0052 key arms included.

### The classification is total

Every other path that changes a region raises the **dirty** bit instead of
queueing a position, so it is on the structural side by construction. Read
off the emitted dispatches: an `append` pushes and sets `regions[i][3] =
true`; an event `remove` and an ADR-0050 predicate removal rebuild the row
array and set it; an ADR-0053 guard *hit* takes the remove branch and sets
it; an ADR-0050/0061 broadcast writes every row and sets it; hydration
pushes the decoded rows and sets it. The pending array is pushed in exactly
one place — the guard-miss arm of a row stage, beside the `row_item[f] =
…` assignments that define the write set. The drain then re-runs
`updateItem` on the retained handle: row roots are neither remounted nor
moved, so everything a previous sweep wrote by position is still on the row
it would rewrite.

So the rule is decidable from the spec alone, and the persistence sweep's
"never" falls out of it rather than being spelled: its read set is every
field, the write set is a subset of the fields and non-empty whenever a
drain path exists, so the two are never disjoint.

### What narrowing moves, measured first

Statically, across the tree: Twin Lab's `left` (drain writes `label`; a row
total and a `flag` predicate count; filter over `flag`) narrows *every*
sweep and stops binding a touched flag at all. Mix Lab's `crew` and Toggle
Lab's `items` (drain writes `done` among others) split: the `done`
predicate counts and selections and the filter keep the touched flag while
the row totals and emptiness subjects move behind the structural bit. Mix
Lab's `pins`, and every region with no drain path, are unchanged — their
pending slot is provably empty, so the two flags are one value. Holding the
surface fixed, the generated modules move by −1184 bytes (Twin — one
`const` fewer per transaction function), +1452 (Mix) and +3072 (Toggle);
no manifest changes. Twin Lab's witness cell adds another +9184 on top of
that, which is a lab edit and not the rule's cost.

The counters move with them: a Toggle Lab keystroke inside a row editor
stops incrementing `tx[5]` once (the row total) and `tx[8]` three times
(the three emptiness subjects); a Twin Lab `mark` stops incrementing
`tx[5]` twice. No `tx[6]`/`tx[9]` write counter moves — the values those
sweeps recompute were equal to their cache, which is the whole point.

Then the price. Two A/B pairs, each a hand-edited copy of the *generated*
module differing only in which flag the count block reads, mounted with N
rows and driven with 450 (Twin) / 200 (Mix) single-row drains; median ms
per commit in Chromium:

| rows | Twin `left`: touched | narrowed | Mix `crew`: touched | narrowed |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 0.0080 | 0.0071 | 0.059 | 0.059 |
| 1000 | 0.0151 | 0.0109 | 0.464 | 0.485 |
| 5000 | 0.0344 | 0.0247 | 2.850 | 2.878 |
| 10000 | 0.0584 | 0.0371 | — | — |

The two columns are the whole finding. In Twin Lab the narrowed sweeps are
the region's *remaining* O(N) work — what is left after them is the
dispatch's key→position scan — so removing the predicate count's scan is a
36% cut at 10k rows. In Mix Lab a persistence write-back, a filter sweep,
and two `done` predicate scans all still wake, and what the narrowing skips
is two `rows.length` comparisons: the difference is inside the noise, and
the narrowed column is nominally *slower*.

Unlike the filter case, then, the dividend is not DOM. It is evaluations,
and it becomes time only where the sweeps that narrow were the O(N) work.

## Decision

**Every sweep over a region is guarded on the flag its own read set
selects.**

> A region's sweep is emitted behind `region_structural_{i}` when the
> region has a drain path and the sweep's read set is disjoint from the
> union of what that region's declared `row` update stages assign; behind
> `region_touched_{i}` otherwise. Adjacent sweeps of one kind that agree
> share one guarded block. A region binds each flag exactly when some sweep
> reads it.

One predicate, `sweepNarrows drainWrites reads`, decides all four sweep
kinds; the filter's ADR-0082 rule is now the instance of it where the read
set is `filterSubjectFields`. The flag set is therefore derived per region
rather than fixed by the feature list — Twin Lab's three regions bind the
structural flag alone, the touched flag alone, and the touched flag alone,
for three different reasons — and a reader who finds a `region_structural`
guard on one block and a `region_touched` guard on the next can derive
which is which from the declared counts, selections, filter and row events.

**Why per sweep and not per block.** Grouping a region's counts under the
union of their read sets would keep every existing artifact byte-identical
and still catch Twin Lab. It would also hide a fact the surface states: a
`{count crew}` cannot change when a row's `done` flips. The block is an
emission convenience; the read set is the contract. Adjacent agreeing
sweeps still share a block, so the extra guards appear only where the
sweeps genuinely disagree.

**Why narrow at all, given the Mix column.** Because the rule is what makes
the counters mean something: after this, `count:{r}:{i}:evaluated` in the
trace says *this value could have moved*, not *this region was poked*. The
time dividend is real where it is collectible (Twin's 36%) and absent where
it is not, and the ADR states both rather than generalizing the ADR-0082
measurement.

**Witness.** Twin Lab's `left` gains a second count cell —
`{count left (flag == "true")}` — beside its row total, so the region now
carries an O(N) sweep whose field its drain does not write. The browser
gate marks a displayed row and a hidden one and asserts zero
`count:left:0:evaluated`, zero `count:left:1:evaluated`, zero
`filter:left:evaluated`, `tx[5]` and `tx[8]` both unmoved, the row roots'
`hidden` byte-equal to what the last sweep left, and the count line still
reading what the last structural commit wrote; an `Add left` afterwards
wakes both counts in the one block they share and moves `tx[5]` by exactly
two. The artifact gate pins `region_structural_0` as `left`'s only flag —
`region_touched_0` is a *banned* string — and pins Toggle Lab's four
interleaved selection blocks and its split count block as the mixed case.

## Consequences

- The wake contract is one sentence over a read set instead of four
  per-feature rules, and ADR-0082's filter rule is a corollary.
- Three sweeps that provably cannot move on a drain no longer run on one:
  row totals, emptiness subjects, and any predicate subject whose field the
  region's row events never write.
- Generated modules with mixed read sets grow (Toggle Lab +2%); the one
  whose sweeps agree shrinks. The benchmark artifacts and their size gate
  are untouched — the js-framework-benchmark backend is hand-written and
  never reaches this path — and BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.

## Open questions

1. **The drain is not per field.** The write set is the union over *all* of
   a region's row events, so Toggle Lab's `retype` — which writes only
   `draft` — still wakes the `done` predicate scans, because some *other*
   row event writes `done`. Narrowing that needs the pending slot to carry
   which fields were written, which is a region-record change; nothing
   needs it yet.
2. **The sweep still has no per-row cache** (ADR-0082 OQ2, unmoved). A
   sweep that must run rewrites `hidden` on every row rather than the rows
   whose selection changed.
