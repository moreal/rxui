# ADR-0087: A persisted region's store is current at the end of every commit

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0086 collapsed the filter sweep's DOM pair and left persistence standing
alone at the top of a cached commit. Its OQ1 named two segments — the
`storageSet` host call and the persistence push/join loop — and ADR-0085 OQ1
had already stalled the obvious answer on one sentence: caching the *joined*
string needs position information a row tuple cannot carry.

Two ways out were on the table, and this round's job was to price both on the
ladder ADR-0085/0086 built and seal whichever the measurement points at.

- **(A) one flush per task instead of one per commit.** N dispatches inside
  one task would `join` and `storageSet` once, at the end.
- **(B) the segment array on the region record, patched by position.** Rows
  are already walked in scan order, so the position is free; the question is
  whether the `join` stays O(N) or a length accumulation buys an O(1) splice.

### The survey: split the commit, then measure

The clamp is unmoved — Chromium rounds `performance.now()` to 0.1 ms, larger
than every segment here — so the survey ablates: hand-edited copies of the
*generated* Toggle Lab module, each rung removing one more segment, driven
with 400 single-row dispatches over one seeded 10 000-row region, whole loop
timed and divided. Median of five runs, ms per commit:

| variant | `toggle` | `retype` |
| --- | ---: | ---: |
| L0 the emitted commit | 0.6705 | 0.5310 |
| L1 without the `storageSet` call | 0.4325 | 0.3022 |
| L2 without the `join` | 0.1983 | 0.0690 |
| L3 without the persistence sweep | 0.1583 | 0.0302 |

Differencing the ladder gives the shares, **and the first thing it does is
correct ADR-0086 OQ1**:

| segment | `toggle` | share | `retype` | share |
| --- | ---: | ---: | ---: | ---: |
| `storageSet` | 0.238 | 35.5% | 0.229 | 43.1% |
| the `join` | 0.234 | 34.9% | 0.233 | 43.9% |
| the cache check + push loop | 0.040 | **6.0%** | 0.039 | 7.3% |
| everything else | 0.158 | 23.6% | 0.030 | 5.7% |

ADR-0086 priced the push loop at 0.301 ms by differencing a ladder whose
rungs still carried the uncached filter sweep; measured on its own, against
the shipped emission, it is **0.040 ms** — a fifteenth of that, and the
smallest segment of the four. That number is the whole survey: axis B was
proposed to remove exactly this loop.

At 1000 rows the same three shares hold (L0 0.0725, L1 0.0458, L2 0.0215,
L3 0.0205 → `storageSet` 36.8%, `join` 33.5%, push loop 1.4%), so nothing
below depends on the row count.

### Axis A, measured: the saving is 1 − 1/N, and N is 1

A per-task flush was measured directly, by deferring the `join` and
`storageSet` out of all sixteen emitted commit blocks and flushing once every
N dispatches. 10 000 rows, `toggle`:

| dispatches per flush | ms per commit |
| ---: | ---: |
| 1 | 0.6750 |
| 2 | 0.4567 |
| 4 | 0.3160 |
| 8 | 0.2610 |
| 16 | 0.2375 |
| 400 | 0.1995 |

The curve is exactly `L2 + (join + storageSet)/N` — 0.198 + 0.472/N — to
three digits at every point. Deferral does not make the flush cheaper; it
makes it rarer, by the factor N, and it is free of any other cost: at N = 1
the deferred emission measures 0.6750 against the shipped 0.6705, inside the
run-to-run band, with the `queueMicrotask` schedule included.

So the whole question is N, and **N is 1**. A generated component reaches a
transaction through exactly one path — a listener registered by `mount` — and
every listener dispatches one transaction; nested transactions already
coalesce to one commit through the `tx[0]` depth counter, so a task carrying
one event carries one commit. The platform delivers one user event per task.
The route write is not a counterexample: `writeHash` fires `hashchange`
asynchronously, in its own later task, and a filter change touches no region
and persists nothing anyway.

N > 1 therefore requires a *synchronous programmatic* burst — `el.click()` in
a loop, or a test driver — and for that case deferral is a 3.4× on a workload
no user can produce. What it costs is a visibility contract, which is why the
contract below is written down rather than the deferral.

### Axis B, measured: the join survives, and the offset is not O(1)

Both rungs were hand-applied to the same generated module:

| variant | `toggle` | | `retype` | |
| --- | ---: | ---: | ---: | ---: |
| the emitted sweep | 0.6705 | | 0.5310 | |
| B1 segments on the record, joined per commit | 0.6398 | 1.05× | 0.4885 | 1.10× |
| B2 B1 + the joined string spliced by accumulated offset | 0.4412 | **1.52×** | 0.2313 | **2.30×** |

**B1 is the axis as proposed, and it is worth 5%.** It buys precisely the
0.040 ms the ladder priced, because the `join` it was meant to eliminate is
still there: a segment array is still N strings that must become one.

**B2 answers the O(1) question, and the answer is no.** Position gives the
segment *index*; splicing the joined string needs the byte *offset*, which is
a prefix sum over segment lengths. Every row edit changes its segment's
length, so a maintained offset table would be O(N) to repair on the same
commit that was supposed to become O(1) — B2 therefore accumulates the offset
on the spot, an O(position) numeric loop. It is a real 1.5–2.3×, and it is
still O(N): a cheap O(N) (integer adds and one flatten inside `storageSet`)
replacing an expensive one (10 000 pointer reads and a fresh 300 KB string).
The asymptotics do not move; only the constant does.

Every variant above was checked to write a **byte-identical** stored string
to the shipped emission over a mixed 60-dispatch toggle/retype sequence on
200 rows whose fields carry all three escaped separators, so the numbers
price the same work and not a shortcut.

### Three contract-free shapes, all inside the noise

Before spending any contract, the `join` was attacked where it costs nothing
to attack — the emission. 10 000 rows, `toggle`, against L0 = 0.6705:
accumulating the string in the sweep loop with `+` instead of building an
array (C1) measures 0.6560; index-assigning into a preallocated array instead
of `push` (C2) measures 0.6680; `map` then `join` off the row table (C3)
measures 0.6753. All three are inside the run-to-run band. `Array.join` is
already the best available shape for "turn N strings into one", and the
push loop feeding it is 6% of the commit. There is no free win here.

## Decision

**The store is current at the end of every commit, and that is a contract
rather than an implementation detail.**

> A persisted region's `storageSet` runs inside the commit sweep of every
> region-touching transaction, synchronously, before the dispatch that opened
> the transaction returns. Nothing is deferred, batched, or coalesced across
> transactions. Therefore: a read of the key — by this component's own
> hydration, by another component, by another tab, or by the same task
> immediately after a dispatch — observes what the last *completed* commit
> wrote. N dispatches inside one task write N times, each with the value
> current at that commit, and a re-read between any two of them sees the
> earlier one. Nesting is the one thing that does coalesce, and it coalesces
> the commit and not the flush: transactions nested through `tx[0]` produce
> one commit and therefore one write.

The consequence worth naming is the one a deferred flush would have taken
away: **a tab closed at any moment loses nothing that a returned dispatch
wrote.** There is no window between "the event handler returned" and "the
store holds it", so no unload hook, no `beforeunload` flush, and no
lost-write recovery path is owed by any component that persists a region.

**Why not axis A.** Its saving is `(1 − 1/N) × (join + storageSet)` and N is
1 for every interaction a user can produce. What it would buy in exchange for
the contract above is 0.005 ms of noise on the only workload that occurs.
The 3.4× at N = 400 is a property of the measuring loop, not of the program
being measured — which is exactly why the survey measured the curve instead
of the endpoint.

**Why not axis B.** B1 is 5%, which is not an ADR. B2 is 1.5–2.3× and is
declined on what it costs, which ADR-0085 already enumerated and this round
re-confirms from the other side. ADR-0085's cell is keyed on **row identity**
and has **two** invalidation sites — the row stage and the broadcast — and the
three paths that rebuild the row array without writing a field (`remove`, the
ADR-0050 predicate removal, the ADR-0053 guard hit) are cache-preserving *by
construction*. A joined string is keyed on **position**, so all three become
invalidation sites, and so do `append`, the row-stage drain, the broadcast and
hydration: **seven**, against two. It also wants two new region record slots
on every persisted region, where ADR-0085 and ADR-0086 each moved none — Mix
Lab's nine-slot `crew` beside its eight-slot `pins` is pinned precisely
because a slot number means something different in each. And a cell that
disagrees with the row table is not a stale pixel, as ADR-0086's `shown` would
be: it is a wrong string in localStorage, discovered on the next reload. The
measured 1.5× is not worth five invalidation sites, two record slots, and
that failure mode, on a table the benchmark does not even build.

**What stays open, honestly.** The floor is now two host-shaped costs of
almost equal size: `storageSet` (0.238 ms at 10k) is the browser's, and the
`join` (0.234 ms) is the price of "one region's table is one string". Neither
narrows without giving up either the visibility contract above or identity
keying. This ADR stops the line here and says so.

**Witness.** Toggle Lab's browser gate drives the contract on three rows, not
ten thousand. One `page.evaluate` clicks Add item three times *synchronously*
— three dispatches in one task, the shape axis A would have collapsed — and
re-reads `localStorage` between the clicks: the store holds one row, then
two, then three, and the trace holds three `storage:items:write` entries
beside three `transaction:commit`. A fourth click in the same task that
changes a *filter* adds a `transaction:commit` and no `storage:items:write`,
because the region was untouched. A second gate closes the loop the contract
promises: after a burst, disposing and re-mounting hydrates every row the
burst wrote, so nothing a returned dispatch wrote was pending anywhere. The
artifact gates for all three persisted labs additionally ban the deferral
primitives outright — `queueMicrotask`, `setTimeout`, `requestAnimationFrame`,
`Promise` — so the emission cannot acquire a flush point behind the contract's
back.

## Consequences

- No generated module changes. Every artifact in the repository is
  byte-identical, the benchmark size gate and every manifest included, and
  BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.
- `PersistSpec` and the language guide now carry the visibility contract, so
  a future round that wants deferral has to change a stated contract rather
  than an unstated habit.
- Three artifact gates gain a four-entry banned list; a deferral primitive in
  a persisted lab's emission now fails `check_component_codegen.sh`.
- ADR-0086 OQ1's attribution of 0.301 ms to the push loop is superseded by
  the 0.040 ms measured here.

## Open questions

1. **`storageSet` and the `join` are the floor, at 35% each.** Both are O(N)
   in the row table on every region-touching commit, and neither narrows
   under identity keying. Moving either needs the position-keyed cache this
   ADR declines, or a storage host that takes something other than one string
   — which would be an ABI question, not a codegen one.
2. **The four predicate scans are unnarrowed** (ADR-0086 OQ2, unmoved). Two
   counts and two selections over one field still each run their own O(N)
   pass in one commit; on the now-smaller commit they are a larger share of
   a smaller number.
3. **The key→position scan is O(N) per dispatch** (ADR-0084 OQ2, ADR-0085
   OQ2, ADR-0086 OQ3, unmoved), and still owed the whole
   append/remove/broadcast/hydrate invalidation matrix in exchange.
