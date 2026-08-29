# ADR-0105: Drawing fewer rows than a filter selects

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0104 removed the ADR-0063 history write from the front of a filter flip and
left one question standing, which ADR-0103 had raised and ADR-0104 restated as
the largest term at every `k`:

> **Showing fewer rows than the filter selects.** […] What it costs is that a
> region's rows stop being *the* rows — every count, every sweep and every
> `childAt`-free positional export is written against a table that is entirely
> rendered — so it is a language round, and a large one.

This round prices it. It measures the flip's commit again first, because the
term in front of it is gone and the ranking behind it may have moved; then it
checks the sentence above against the code, one file and one function at a
time; and it closes ADR-0104's first open question, which was the smallest
thing left.

**The premise of the open question turns out to be false**, and the two ADRs
that falsified it are ADR-0099 and ADR-0102 — the round's own predecessors.
Nothing in the emission reads the container as the row table any more. So the
decline below is not a contract argument. It is arithmetic, and the arithmetic
is the reason.

### The harness

ADR-0099's, at ADR-0101's settings, unchanged: probes cut mechanically into the
*generated* Toggle Lab module with an exact-count assertion on both anchors,
COOP/COEP so the clock is 5 µs, keys pinned so a re-seed is a retained
reconcile, and the seed walking the table to put every ADR-0086 display cell and
the DOM into the same all-shown state before a timed flip starts. Twelve probes,
and **all twelve matched exactly sixteen times on the first run** — the third
round running in which no anchor had rotted, against the three before ADR-0103
that were each caught by the assertion.

Two harness notes. Every cell is read against an A/A control that is a second
page of the *same* dist, so the band is this round's own; the whole-dispatch
cells sit at 0.966–1.083× and the sub-millisecond probe segments spread to
0.875–1.255×, which is the sub-millisecond band ADR-0104 also had. And the
window measurements below drive the region handle's `setDisplayed` directly
rather than through a filter, because the point of the round is to price the
mechanism, not an emission that does not exist.

## The measurement

### 1. A filter flip's commit is exactly two terms

Both directions, every probe, ten thousand rows, ADR-0104's emission.
Milliseconds; `resid` is `commit − route − sweep`.

| N / k | dir | commit | route | | sweep | | resid | |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 / 100 | hide | 4.360 | 3.880 | **89.0%** | 0.455 | 10.4% | 0.025 | 0.6% |
| 10 000 / 100 | show | 3.795 | 3.680 | **97.0%** | 0.110 | 2.9% | 0.005 | 0.1% |
| 10 000 / 1 000 | hide | 7.100 | 3.930 | **55.4%** | 3.170 | 44.6% | 0.000 | 0.0% |
| 10 000 / 1 000 | show | 3.800 | 3.250 | **85.5%** | 0.540 | 14.2% | 0.010 | 0.3% |
| 10 000 / 5 000 prefix | hide | 19.475 | 3.675 | 18.9% | 15.520 | **79.7%** | 0.280 | 1.4% |
| 10 000 / 5 000 prefix | show | 4.155 | 1.765 | 42.5% | 2.385 | **57.4%** | 0.005 | 0.1% |
| 10 000 / 5 000 spread | hide | 21.375 | 3.360 | 15.7% | 17.615 | **82.4%** | 0.400 | 1.9% |
| 10 000 / 5 000 spread | show | 4.495 | 2.210 | 49.2% | 2.275 | **50.6%** | 0.010 | 0.2% |
| 10 000 / 10 000 | hide | 34.075 | 3.295 | 9.7% | 30.420 | **89.3%** | 0.360 | 1.1% |
| 10 000 / 10 000 | show | 4.555 | 0.180 | 4.0% | 4.370 | **95.9%** | 0.005 | 0.1% |
| 1 000 / 500 | hide | 1.915 | 0.460 | 24.0% | 1.460 | **76.2%** | −0.005 | −0.3% |
| 1 000 / 1 000 | hide | 3.390 | 0.460 | 13.6% | 2.945 | **86.9%** | −0.015 | −0.4% |

**The reconcile, the write-back and all three drains are exactly 0.000 in every
one of the fourteen cells**, along with the ADR-0099 rescan and the event body:
a filter flip raises no dirty bit, queues no removal, counts no append and
stages no row update, so nothing in the commit runs except the route write and
the sweep. The residue either side of them is −0.4% to +2.2%. ADR-0103's
question — what share is the sweep, the reconcile, the write-back — has a
three-part answer and two parts of it are zero.

So the ranking is between two terms, and it has moved. ADR-0103 measured the
route write at 2.06 µs per row displayed and found "the sweep only overtakes it
once half the table moves". ADR-0104 divided that term by 5.9. Walking `k`
across the crossover, hide direction, ten thousand rows:

| k | commit | route | sweep | larger |
| ---: | ---: | ---: | ---: | --- |
| 500 | 5.250 | 3.550 | 1.895 | route |
| 750 | 5.860 | 3.495 | 2.360 | route |
| 1 000 | 6.930 | 3.605 | 3.130 | route |
| 1 250 | 7.270 | 3.520 | 3.850 | **sweep** |
| 1 500 | 7.950 | 3.505 | 4.495 | sweep |
| 2 000 | 9.360 | 3.435 | 5.995 | sweep |
| 3 000 | 13.255 | 4.200 | 9.155 | sweep |

The route write is flat at 3.29–3.93 ms, which is ADR-0104's
`0.34 µs · rows + 0.15 ms` at ten thousand rows; the sweep fits
**`0.15 ms + 3.03 µs · k`** to within 1.5% at every `k` from 100 to 10 000. They
cross at `k` ≈ 1 120. **The crossover moved from half the table to eleven
percent of it** — which is the shape ADR-0104 predicted for itself: it lowered a
term that does not grow with `k`, so it matters most to the flips that move the
fewest rows, and past 11% the sweep was always going to be the larger of the
two.

### 2. And neither of them is what the flip costs

The commit is not the click. Taking the same dispatches with the forced style
and layout after them, and summing both directions into the round trip:

| N / k | round trip | style + layout | | commit | | sweep | | route | |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 / 100 | 25.16 | 16.48 | **65.5%** | 8.15 | 32.4% | 0.56 | 2.2% | 7.56 | 30.1% |
| 10 000 / 1 000 | 46.82 | 35.87 | **76.6%** | 10.90 | 23.3% | 3.71 | 7.9% | 7.18 | 15.3% |
| 10 000 / 5 000 prefix | 135.50 | 111.74 | **82.5%** | 23.63 | 17.4% | 17.91 | 13.2% | 5.44 | 4.0% |
| 10 000 / 5 000 spread | 138.46 | 112.85 | **81.5%** | 25.87 | 18.7% | 19.89 | 14.4% | 5.57 | 4.0% |
| 10 000 / 10 000 | 252.29 | 213.69 | **84.7%** | 38.63 | 15.3% | 34.79 | 13.8% | 3.48 | 1.4% |
| 1 000 / 500 | 13.62 | 11.21 | **82.3%** | 2.38 | 17.5% | 1.65 | 12.1% | 0.73 | 5.4% |
| 1 000 / 1 000 | 24.77 | 20.89 | **84.3%** | 3.89 | 15.7% | 3.32 | 13.4% | 0.58 | 2.4% |

**Style and layout is the largest term in every cell**, from 65.5% at a hundred
rows moved to 84.7% with the whole table moved, and almost all of it is the show
direction: at 10 000 / 5 000 the hide leg dirties 3.70 ms and the show leg
108.03. Fitted over the same cells, the real emission's show direction is

```
style + layout = 0.67 µs · N + 20.6 µs · k
```

which is ADR-0103's framework-free `1.045 µs · N + 14.83 µs · k` measured on the
module that actually ships — least squares over the four `k` cells, worst
residual 6.1% at the smallest of them. A Toggle Lab row costs **20.6 µs** to
put into the document, not 14.83, and a row merely resident costs less than
ADR-0103's fit said. Every number below uses the emission's own figure.

So ADR-0104's closing sentence stands and this is the number under it: what is
left of a filter flip is the rows being in the document, and it is four fifths
of the click.

### 3. What a window would break, one function at a time

ADR-0103 named three things that assume a fully rendered table. All three were
checked against the current source rather than argued about.

**Counts do not read the container.** `LeanRx/Backend/Component.lean`, the
`unless counts.isEmpty` block: a total count compiles to
`regions[i][1]["length"]` — the row *table*'s length — and a predicate count to
a read of the ADR-0099 accumulator cell. Neither mentions the parent. ADR-0099
took the last container walk out of this path a round before ADR-0103 named it.

**The sweep already runs over rows that are not in the container.** Same file,
the `if let some filter := filter?` block: it walks the row table by index and
calls `handle.setDisplayed(position, key, selected)`. That is ADR-0102's export,
whose entire purpose is a row that is in the table and not in the parent, and
the ADR-0086 display cell it compares against is keyed on row identity rather
than on child position.

**There is no container-positional export left.** `rowNavigate` folds
`childAt` from **the row's own root node**, not from the parent, and the
region record's container slot — which the ADR-0051 sweep used to navigate
from — was deleted by ADR-0102, which moved that navigation into the handle
and shifted every slot behind it down by one. The comment recording that is
still in `Component.lean`.

Two more that ADR-0103 did not name and that also hold: `hiddenIfEmpty` and
`checkedIfEmpty` read the count, hence the table; and the ADR-0063 write-back
walks the table.

On the host side, `runtime/leanrx_region.mjs` was written for this in ADR-0102.
`update()` calls `restoreDisplayed()` before it reconciles and takes the same
survivors out after, so `placeInOrder`, `rebuild` and `ownsWholeParent` see the
whole table however many rows are out; `removeAt` and `removeMany` are
`parentNode`-guarded; `ownsWholeParent` simply returns false while rows are
out, so the bulk clear turns itself off — and ADR-0103 measured that clear at
0.974×, a loss, so turning it off costs nothing.

The restore bracket is the one thing that could have been expensive, so it was
measured rather than assumed. A broadcast — the reconcile path — dispatched
with `k` of ten thousand rows out of the container:

| k out | reconcile | forced layout after | commit |
| ---: | ---: | ---: | ---: |
| 0 | 9.645 | 0.20 | 44.445 |
| 1 000 | 9.560 | 0.16 | 38.235 |
| 2 500 | 9.880 | 0.15 | 34.090 |
| 5 000 | 11.895 | 0.16 | 29.850 |
| 10 000 | 12.580 | 0.02 | 18.560 |

**0.29 µs per row out, and no style or layout at all.** Putting ten thousand
rows back and taking them out again inside one commit costs 2.9 ms of DOM writes
and nothing else, because nothing reads layout in between — which is exactly
what ADR-0102's "one descending pass, no forced layout possible in between"
promised and is now measured. Walking the table itself is free: an idle sweep
that writes nothing is 0.03 ms at ten thousand rows and 0.055 at twenty
thousand, about 3 ns a row.

**So the minimal non-breaking form exists, and it is not minimal — it already
ships.** A window is `setDisplayed` applied to more rows. The row stays in the
table, keeps its node, its handle, its listeners and every property written into
it; only the document changes. Nothing in the host, the record, the ABI or the
count/sweep/export machinery needs to move. What is missing is one thing and it
is small: `RegionFilter`'s sealed predicate table maps a state value to a
*row-field* predicate, and a window needs one that also reads the row's
position.

The other reading of "window" — a region that never mounts the rows outside it —
does break everything, and it is worth writing down what. `entry.node` is
dereferenced without a null guard in `placeInOrder`, `rebuild`,
`restoreDisplayed`, `displayAnchor`, `insertAnchor`, `swapAt`, `insertAt`,
`removeAt`, `removeMany`, `setDisplayed` and `dispose` — eleven sites, and the
only guarded one is the `entry.node !== null` inside `update()` that exists for
an entry between its creation and its mount. `updateAt` fails a step earlier, on
the `entry.handle` that `mountItem` produces. And `mountItem` itself would have
to become re-entrant during a sweep, since the sweep is what would decide that a
row now needs mounting.

That version is a language round. The version that is actually on the table is
not.

### 4. What a window would cost

Which makes it arithmetic. Driving the handle directly, ten thousand rows,
window of fifty, one step moving `m` rows out and `m` rows in, timed with the
forced style and layout the arrivals cost:

| m | wall | writes | style + layout | per row moved |
| ---: | ---: | ---: | ---: | ---: |
| 1 | 0.065 | 0.015 | 0.055 | **65.0 µs** |
| 5 | 0.140 | 0.015 | 0.125 | 28.0 µs |
| 10 | 0.265 | 0.035 | 0.235 | 26.5 µs |
| 25 | 0.615 | 0.075 | 0.535 | 24.6 µs |
| 50 | 1.450 | 0.380 | 1.090 | 29.0 µs |

and the two edges of the window, from and back to a fully shown list:

| window | down to the window | back to all shown |
| ---: | --- | --- |
| 50 | 29.96 (29.86 write + 0.10 layout) | 224.54 (3.61 + 220.82) |
| 100 | 29.60 (29.49 + 0.12) | 214.73 (3.41 + 211.07) |
| 250 | 29.19 (28.99 + 0.20) | 212.71 (3.44 + 209.40) |

Now the trade, at the cell ADR-0103 costed: ten thousand rows, a filter
selecting five thousand, a window of fifty.

- **The gain is real and larger than the estimate.** The show direction puts
  fifty rows into the document instead of five thousand: `0.15 ms + 50 × 3.03 µs`
  of sweep and `0.67 µs · N + 50 × 20.6 µs` of layout, about **8 ms** against
  the measured **112.16**. ADR-0103 costed this at 74 ms; on the real emission
  it is **105**.
- **The hide direction gets worse.** It must take 9 950 rows out instead of
  5 000, which is the 29.96 ms measured above against **23.34**.
- **One-time, the flip wins 3.6×**: 135.50 ms of round trip becomes about 38.
- **Then the user scrolls.** Every row crossing the window edge is 24.6–29.0 µs,
  and 65.0 µs when the window moves one row at a time, because each step forces
  its own style and layout pass. Scrolling the five thousand selected rows past
  the viewport once costs **about 130 ms**, in roughly a hundred separate
  0.65–1.45 ms interruptions — arriving inside a scroll, where the budget is
  16 ms a frame and the user is looking at the thing that is late.

The comparison is not against a smaller number. It is against **no number**: a
list the browser has already laid out scrolls without entering script, without a
commit, and without re-running style and layout for content that has not
changed. That half is the platform's behaviour rather than a measurement of
this harness — a headless scroll is not a user's — but it is not in doubt, and
it is the half a window has to beat. So the window's total is `38 + 130 = 168 ms` against `135.5`, and the
130 is owed again on every scroll while the rendered list still owes nothing.

**The window does not remove the `20.6 µs · k`. It moves it** — out of a click
the user has already accepted as a wait, and into a scroll, one row at a time,
forever. On this repository's largest list it also makes the total larger.

## Decision

**No window, and the reason is the arithmetic and not the contract.** Nothing in
the emission changes for it: no host export, no record slot, no predicate, no
statement order, and `runtimeAbi` stays 20.

Three things are recorded rather than built:

- **A filter flip's commit is the route write and the sweep and nothing else** —
  the reconcile, the write-back and all three drains measure exactly zero in
  both directions at every cell — and after ADR-0104 the sweep overtakes the
  route write at `k` ≈ 11% of `N` rather than at half the table.
- **Neither is the flip's largest term.** Style and layout is 65.5–84.7% of the
  round trip, almost all of it the show direction, and the emission's own law is
  `0.67 µs · N + 20.6 µs · k`, which replaces ADR-0103's framework-free
  `1.045 µs · N + 14.83 µs · k` for anything reasoning about this module.
- **ADR-0103's open question 2 rested on a premise its own predecessors had
  already removed.** Counts read the row table (ADR-0099's accumulator), the
  sweep is written for rows outside the container (ADR-0102's `setDisplayed`),
  and the container-positional export was deleted by ADR-0102. A windowed region
  is not a language round; it is a predicate that reads a row's position, and it
  is declined on 24.6–65.0 µs per row crossing the window edge against a
  one-time 105 ms.

**And the hand-written backends now say what they own.** ADR-0104's open
question 1 asked whether the bespoke emitters were worth changing or worth
deleting, and the answer is changing: they are the differential oracle the
checked pipeline is measured against, and the divergence ADR-0104 §3 measured —
a traversal restoring a value *after* the mount has written the owned one, so
the DOM disagrees with the cell that owns it — is a correctness fact about them
too, on any traversal a user makes, whether or not they write a route.

The rule is ADR-0104's, unchanged: **an element declares ownership exactly when
the program writes its `value` or `checked`.** Applied to every hand-written
backend rather than only to the two the open question named, because the other
two make the same claim and leaving them out would reopen the same question:

- **Temperature** (2): both inputs, whose `value` each conversion rewrites from
  the opposite field.
- **Validated Form** (3): `name` and `age` (ADR-0038 text bindings) and `terms`
  (a `checked` binding).
- **TodoMVC** (3): the row checkbox and the row editor, rewritten from the item
  on every row update, and the static new-todo field the add handler clears.
- **Notes** (1): the `<textarea>` the restore effect writes back from `state[0]`
  — the one shape the checked pipeline cannot emit, so the rule reaches a
  `<textarea>` for the first time.

`LeanRx/Backend/FormDom.ownedState` is the one spelling all four share, so the
claim reads identically to `StaticAttr.ownedState`'s in the checked pipeline,
and it is emitted in the same place: last static attribute, directly before the
property write it declares ownership of.

**The boundary is a property write and not a tag.** Issue Browser's query field
is given a literal value once at mount and never written again — the program
reads it off the event and stores nothing it would have to put back — so there
is no cell for a restored value to contradict and the claim is not made. Data
Grid writes only `disabled`, which the browser does not restore. Dependent Tabs
and the benchmark write neither. These carry the same negative Nest Lab carries
on the checked side.

## Consequences

- **Four bundles change, one module each, and every line is an addition.**
  TodoMVC 14 181 → 14 375 (+194: three declarations and, because this backend
  counts its own mount attributes, two `metrics[6] += 1` beside the two
  row-scoped ones), ValidatedForm 9 928 → 10 078 (+150, three), Temperature
  Converter 8 192 → 8 301 (+109, two), Notes 5 044 → 5 094 (+50, one). **No
  existing line moved in any of them.** The other fifteen bundles are
  byte-identical — Counter, Diamond, Echo, Filter, Branch, **Toggle**, Nest,
  Mix, Twin, Dependent Tabs, Issue Browser, Data Grid, the docs site, the
  expression playground and the js-framework-benchmark bundle — so **the size
  baseline does not move**, and every manifest including every `graphHash` is
  unchanged, because an attribute is not part of the reactive graph. The four
  runtime host modules are untouched and `runtimeAbi` stays 20.
- **The witnesses are counts, and one of them is a metric.** Four artifact gates
  pin every emitted sequence *and* assert the exact number of declarations —
  TodoMVC 3, Validated Form 3, Temperature 2, Notes 1 — so a fifth would mean the
  rule had started paying for a control the program does not own. The Issue
  Browser gate carries the hand-written negative: its module contains no
  `autocomplete` at all and its uncontrolled query input is pinned in place.
  Four browser tests walk the DOM count and take it back to zero through
  disposal; TodoMVC's follows it through two row mounts, the edit branch and a
  delete. And TodoMVC's existing DOM-write assertion moves **203 → 209**: that
  run mounts six row branches and each now writes one more attribute, which is
  the change made visible in the counter it belongs in rather than smuggled past
  it.
- **The guide and the dynamic-regions note gain this round's laws.** Both
  carried ADR-0103's `1.045 µs · N + 14.83 µs · k` as the flip's remaining cost;
  both now carry the emission's own `0.67 µs · N + 20.6 µs · k`, the
  two-term commit with its 11%-of-`N` crossover, the share style and layout
  actually takes, and the window's price.
- **Twelve probes, sixteen sites each, first run, third round running.**

## Open questions

1. **The sweep is now the whole commit and it is one write per row.** At
   `k` = `N` the sweep is 89.3% of the hide commit and fits
   `0.15 ms + 3.03 µs · k`, of which ADR-0103's detach law says
   `450 ns/row + 126 ns/node` — about 1.9 µs for Toggle Lab's eleven-node row —
   is the browser's. The remaining ~1.1 µs a row is the host's: the display cell
   compare, the key check, and `displayAnchor`'s backward walk. Whether that
   1.1 µs is reducible is unmeasured; it is 11 ms at ten thousand rows, 4.4% of
   the round trip, which is under the bar this round used, and it is the only
   part of the sweep a compiler owns.
2. **A window is one predicate away and the number that would change the
   verdict is the row's.** The decline above is 24.6–29.0 µs per row crossing
   the edge against 20.6 µs to render one, so the recurring cost is *the render*
   plus about 5 µs of host. A row template cheap enough to render — ADR-0104
   measured 5.83 µs for a row of text against 15.32 for Toggle Lab's — moves the
   scroll cost down proportionally without moving the one-time gain, and a list
   long enough that the browser cannot lay it out at all moves it the other way
   by fiat. Both are the author's numbers, not the compiler's, which is why this
   ADR declines to emit a window rather than declaring one unprofitable.
3. **`<textarea>` is now reachable by the rule and still not by the language.**
   Notes is the first module to declare ownership of one, through its own
   emitter. `HtmlTag` still has no `textarea` and no `select`, so ADR-0104's
   second open question stands with one more data point: the rule generalises to
   both, and the checked pipeline can emit neither.
4. **`swapAt` and the filter still cannot meet.** ADR-0102's second open
   question, fourth round standing: no emission puts a swap and a filter on one
   region, so the displayed-anchor branch is exercised only by the host gate.
