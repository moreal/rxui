# ADR-0088: One region walks its rows once per wake class

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0087 closed the persistence axis on two host-shaped costs of equal size
and left one open question that was never a contract question at all.
ADR-0086 OQ2, restated by ADR-0087 OQ2: **two counts and two selections over
one field each run their own `O(N)` pass over the same row table in the same
commit.** Toggle Lab's `toggle` commit walks `items` six times — `count:0`,
`count:1`, `attr:1`, `attr:3`, the filter sweep, the persistence sweep — and
three of those six spell the *identical* predicate, `done == "false"`.

The question this round had to answer is not whether the duplication exists.
It is what the duplicate key is, which is a codegen question, and what the
fusion may not cross, which is a contract one.

### The survey: build the rungs, then measure

Same harness as ADR-0085/0086/0087 — hand-edited copies of the *generated*
Toggle Lab module, 400 single-row dispatches over one seeded region, whole
loop timed and divided, Chromium's `performance.now()` still clamped at
0.1 ms so nothing smaller than a whole loop is trusted. Median of nine
in-page repetitions, median of seven page loads, ms per commit:

| rung | walks per `toggle` | 10k `toggle` | | 1000 `toggle` | |
| --- | ---: | ---: | ---: | ---: | ---: |
| the emitted commit | 6 | 0.7355 | | 0.0733 | |
| F1 identical predicates share a pass | 4 | 0.6367 | 1.155× | 0.0650 | 1.127× |
| F2 one pass per **wake class** | 3 | **0.6085** | **1.209×** | **0.0640** | **1.145×** |
| F3 F2 + the narrow class dragged in | 3 | 0.6490 | 1.133× | 0.0683 | 1.073× |
| F4 F2 + the two writer sweeps fused | 2 | 0.6045 | 1.199× | 0.0638 | 1.161× |

`retype` is the control, and it is flat on every rung: 0.5365 → 0.5323 at
10k, 0.0555 → 0.0553 at 1000. ADR-0084's per-event drain wake keeps a
keystroke out of every predicate scan, so there is nothing there to share —
which is exactly the shape of a harness that is measuring what it claims to.

Every rung was checked to write a **byte-identical** stored string, an
identical trace, identical `tx[5]`/`tx[6]`/`tx[8]`/`tx[9]` counters and an
identical rendered DOM against the shipped emission, over a mixed 60-dispatch
`toggle`/`retype`/`edit` sequence on 200 rows whose every field carries all
three escaped separators. The numbers price the same work.

**Three things fall out of that table, and two of them invert the premise.**

**F1 is the literal OQ2 proposal and it beats the ceiling the round was
given.** The pre-measurement quoted 1.11× for fusing five scans into one pass
and predicted the same-predicate-only rung would come in *under* it. It comes
in at 1.155×, above it. The ceiling was low because it was measured on a
fusion that crossed a class boundary — F3 below — and paid for the crossing.

**F2 is the best rung, and it is not the "same predicate" rule.** Adding the
`done == "true"` scan to the shared pass — a *different* predicate, in the
same wake class — buys another 0.028 ms. So sharing a traversal is worth
something on its own, and collapsing two spellings of one predicate into one
accumulator is worth something more; both are real, and they compose.

**F3 is the trade the round was told to name, and the measurement declines
it.** The editing hint reads `mode`, so ADR-0084 puts it in a narrower drain
class than the four `done` sweeps. Dragging it into the wide class to make
one pass out of five costs **0.040 ms at 10k** — it gives back 40% of the
whole opportunity and lands *below* the same-predicate rung. A fused pass
must run whenever any of its members is awake, so a class boundary crossed is
a class boundary erased: the narrow sweep's predicate is then evaluated on
every wake of the wide class, for nothing. This is the ADR-0083/0084 wake
narrowing being spent to buy a traversal that was already cheap.

**F4 is not worth its shape.** Fusing the post-reconcile filter sweep with
the persistence sweep is 1.199× against F2's 1.209× at 10k and 1.161× against
1.145× at 1000 — inside the band in both directions. It also cannot be
emitted as one loop: the two sweeps read different wake conditions (a filter
change runs one and not the other, a `retype` the reverse), so a fused
emission needs three code paths — both, filter-only, persist-only — to keep a
filter change from acquiring a `storage:{region}:write` it never had. Three
loop bodies for zero measured milliseconds.

## Decision

**A region's predicate scans are grouped by the wake flag they already read,
and a group with more than one member walks the row table once.**

> Every ADR-0050 predicate count and every ADR-0059/0060 predicate-count
> attribute selection over one region is a *predicate scan*. Two predicate
> scans **share a pass** exactly when they read the same wake flag — the
> ADR-0083/0084 flag their own read sets already select. Inside one pass,
> each **distinct** field equality gets one accumulator, so two slots
> spelling the same predicate share a cell and two spelling different ones
> share only the traversal. A pass is guarded on exactly its class's flag and
> emitted before the class's first consumer. Nothing fuses across a class
> boundary. A predicate-free total is a `length` read, not a scan: it joins
> no pass. The ADR-0051 filter sweep and the ADR-0063 persistence write-back
> run after the reconcile and are not fusion targets. A class with one member
> keeps its own inline loop, so a component with no duplication emits exactly
> what it emitted before.

**The duplicate key is the wake class, not the predicate.** That is the whole
contract, and it is the conservative choice *and* the fast one, which is
unusual enough to be worth stating: F2 beats F3 by 0.040 ms precisely because
it refuses to widen. The rule needs no cost model — grouping on a flag the
emission already computes cannot make any sweep wake more often than it did,
so it cannot make any commit slower, on any component, for any workload. Its
worst case is a class with one member, which is the previous emission.

**What is shared is the traversal, never the cache.** Every slot keeps its
own cache cell, its own compare, its own write, its own
`count:{r}:{i}:evaluated` / `attr:{i}:{a}:evaluated` label and its own
`tx[5]`/`tx[6]`/`tx[8]`/`tx[9]` increment, in the order it had them. The pass
emits no trace entry of its own. The trace, the counters, the stored string
and the rendered DOM of every existing lab are byte-identical across this
change — the survey verified that directly rather than assuming it, and the
artifact gates now pin the shape.

**Why the filter and persistence sweeps stay out, beyond the measurement.**
They are *writers*, and they run after the reconcile because they navigate
`childAt(container, i)` and read cells the reconcile may have rebuilt around.
The predicate scans run before it. A single pass over the whole commit would
therefore have to move the counts' `evaluated` entries after
`region:{r}:update`, which is an observable reordering — the one thing this
round was not allowed to spend. The measurement says there was nothing to buy
with it anyway.

**What this does not touch.** No host change and no validator change:
`runtimeAbi` stays 17. No region record slot moves — Mix Lab's nine-slot
`crew` beside its eight-slot `pins` is untouched for the fourth ADR running.
No row tuple cell is added: ADR-0085's `serial` and ADR-0086's `shown` are
the whole per-row cache inventory, and this ADR adds nothing to it, because a
shared pass is per commit and dies with the commit.

**Witness.** Toggle Lab's browser gate counts traversals on three rows, not
ten thousand, by installing a counting `Symbol.iterator` on `Array.prototype`
around one synchronous dispatch — an instrument that fires only on an array
whose first element is a seven-cell row tuple behind a numeric key, so the
pending-position array, the hydration split and the region runtime's entry
list stay invisible to it. A `toggle` walks **4**: the dispatch's key scan,
the drain-class-0 pass, the filter sweep, the write-back. Before this ADR the
same click walked 7. A `retype` walks 2 — key scan and write-back, ADR-0084's
control, unmoved. A `dblclick` walks 3: the editing hint evaluates through its
*own* loop under drain class 1 while the drain-class-0 pass stays asleep,
which is the no-crossing rule made observable on three rows. A filter click
walks 1, the filter sweep alone. An `Add item` walks 3 — outside the region's
dispatch function no class can be told apart, so all five predicate scans read
the touched flag and collapse into one pass — and a `completeAll` broadcast
walks 4, its own write loop ahead of the same three. The artifact gates pin
the emitted passes in both labs that changed: Toggle Lab's three-cell pass in
the shared-flag blocks and its two-cell pass beside the untouched
drain-class-1 loop in the dispatch, and Mix Lab's one-cell pass shared by a
count and a selection that spell one predicate.

## Consequences

- A `toggle` on a 10 000-row Toggle Lab region costs 0.609 ms instead of
  0.736 ms (**1.21×**); at 1000 rows, 0.0640 instead of 0.0733 (1.15×). A
  `retype` keystroke is unchanged at 0.53 ms — it enters no pass.
- Two generated modules change, and both get **smaller**: Toggle Lab
  176 528 → 169 042 bytes (−4.2%) and Mix Lab 96 021 → 94 185 (−1.9%). One
  loop replaces N. Every other artifact in the repository is byte-identical,
  Twin Lab included — its three regions carry at most one predicate scan per
  wake class each.
- The benchmark artifacts and their size gate are untouched: the
  js-framework-benchmark backend is hand-written and counts nothing.
  BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.
- ADR-0062's "no scan sharing: ADR-0050 already re-scans per position" is
  superseded. A count label still rides its own count's read set — that part
  stands — but two count positions with one read set and one predicate now
  share one accumulator instead of two passes.
- **The ADR-0082‥0088 performance line is closed.** Every remaining segment
  of a Toggle Lab commit is either a host call (`storageSet`), the price of a
  stated contract (the `join`, one region's table is one string; the
  key→position scan, identity keying), or already `O(written)` rather than
  `O(N)` (the filter sweep, the write-back). Nothing left on this axis moves
  without giving up a contract that has been written down and measured.

## Open questions

1. **The key→position scan is `O(N)` per dispatch** (ADR-0084 OQ2, ADR-0085
   OQ2, ADR-0086 OQ3, ADR-0087 OQ3, unmoved). It is now the *only* remaining
   `O(N)` walk in a `toggle` commit that no contract requires — the shared
   pass, the filter sweep and the write-back each earn theirs. It is still
   owed the whole append/remove/broadcast/hydrate invalidation matrix in
   exchange, and ADR-0085 priced that exchange at 1.5× against seven
   invalidation sites.
2. **`storageSet` and the `join` are the floor, at 35% each** (ADR-0087 OQ1,
   unmoved). Neither narrows under identity keying and the per-commit
   visibility contract.
3. **A pass is per commit, so it is not a cache.** Two commits inside one
   task each build their own accumulators. That is deliberate — a cross-commit
   accumulator would need the invalidation matrix ADR-0085 and ADR-0087 both
   declined — but it is the only sense in which the duplication this ADR
   removes still exists.
