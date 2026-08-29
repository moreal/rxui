# ADR-0101: What a filter costs the browser

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0100 closed the bulk threshold and left two open questions pointing at
the same page, both about numbers no compiler decision had yet been shown to
reach:

> **The layout that dwarfs all of this, restated with a control.** […] Hiding
> five thousand of ten thousand rows costs 1 282 ms of forced style and
> layout. […] What a compiler could still reach is the *shape* of what it
> writes: `hidden` on five thousand `<li>` elements is five thousand style
> invalidations, where one class on the container plus a CSS rule would be
> one.

> **The route write's O(N) fragment cost.** […] at ten thousand rows that
> assignment alone is 20 ms — more than the entire commit around it.

Both are here answered, and both answers are declines. The first is declined
because the proposed shape is measurably a wash; the second because ADR-0100
named the wrong mechanism, and the right one is not reachable from the
routing vocabulary at all.

### The harness

ADR-0099's, at ADR-0100's settings: probes inserted mechanically into the
*generated* Toggle Lab module with an exact-count assertion on both ends,
COOP/COEP so the clock is 5 µs, a seed that settles through one real
untimed commit, and keys pinned to 1..N so a re-seed is a retained
reconcile. Two things were added.

**A phase split.** The forced style and layout is taken apart with a CDP
trace (`disabled-by-default-devtools.timeline`), pairing the renderer's
`B`/`E` events per thread — `UpdateLayoutTree`, `Layout`, `PrePaint`,
`Paint` — rather than reading one wall-clock number.

**A distribution.** The seed now lays its *k* done rows out either as a
contiguous prefix, which is what ADR-0099 and ADR-0100 seeded, or spread one
in every `N/k`. This turned out to be the whole finding.

Two harness facts are worth stating, because both are repeats.

**A probe anchor went stale again, and the assertion caught it again.**
ADR-0100 replaced ADR-0097's per-row drain loop with one `removeMany` call,
so the `removeDrain` probe's *open* anchor matched **zero** times against a
close anchor that still matched sixteen. What makes this the assertion's
case rather than the run time's is where the surviving insertion lands: it
is *inside* the drain's `if (queue.length !== 0)`, which a filter flip never
enters, so every table in this round would have come out complete and
correct while the drain's closing read referred to a `const` its opening
half never declared — and the first `removeIf` anyone measured afterwards
would have thrown a `ReferenceError` in a page whose exceptions nobody
reads. That is two rounds
in a row where the count check was the only thing between a rename and a
wrong table.

**A re-seed must reset the ADR-0086 display cells, not just the row table.**
The cells ride the row tuples (ADR-0086), so a re-seed that installs *fresh*
tuples into a region whose retained DOM nodes are still `hidden` from the
previous flip leaves every cell saying "shown" over a node that is not. The
sweep then writes nothing, the flip measures a fraction of its cost, and the
first version of this round's table read `1 000/500` at 220 px of body
height — every row hidden — with no error anywhere. The seed now walks the
container once, untimed, and puts the DOM and the cells into the same state.

### The 1 282 ms, split

Real emission, ten thousand rows, five thousand hidden, ADR-0100's seed
(the done rows are a contiguous prefix). Medians; the dispatch and the
forced style-and-layout after it returns are timed apart.

| segment | ms |
| --- | ---: |
| dispatch (whole `showActive` event) | 23.68 |
| — of which the ADR-0051 sweep | 1.82 |
| forced style + layout | **1 280.21** |

The phases are summed over the whole traced span — three repetitions of
hide-then-show, 4 285 ms of forced time in total — because the trace does
not attribute a renderer phase to one of the two flips:

| phase | ms over the span | share |
| --- | ---: | ---: |
| `UpdateLayoutTree` (style recalc) | 3 897.52 | **91.0%** |
| `Layout` | 333.85 | 7.8% |
| `PrePaint` | 55.75 | 1.3% |
| `Paint` | 32.61 | 0.8% |

ADR-0100's numbers reproduce exactly — 1 280 against 1 282, a sweep of 1.8
against 2.56 — and the split says the cost is **style recalc**, not layout
and not paint. Layout is 7.8% of it and painting a screenful is under one
percent.

### How it grows: in rows, in changed rows, and in neither

Forced style+layout in milliseconds, real emission, medians. `k` is the
number of rows the flip hides; the two columns are the same *k* rows laid
out as one contiguous run or spread one in every `N/k`. The trace counters
agree with the row counts at every cell — `filter:{region}:read:N` beside
`filter:{region}:written:k`, so the sweep is provably writing exactly the
rows whose ADR-0086 cell moved and no others.

| rows | k | contiguous | spread |
| ---: | ---: | ---: | ---: |
| 100 | 1 | 0.19 | 0.17 |
| 100 | 50 | 0.45 | 0.35 |
| 100 | 100 | 1.02 | 1.01 |
| 1 000 | 1 | 0.65 | 0.71 |
| 1 000 | 100 | 1.50 | 1.06 |
| 1 000 | 500 | **14.65** | **2.55** |
| 1 000 | 1 000 | 52.90 | 53.19 |
| 10 000 | 1 | 10.56 | 9.88 |
| 10 000 | 100 | 10.95 | 9.96 |
| 10 000 | 1 000 | **61.63** | **15.24** |
| 10 000 | 5 000 | **1 263.11** | **28.17** |
| 10 000 | 10 000 | 5 023.53 | 5 031.38 |

**The 1 282 ms is not the price of hiding five thousand rows.** It is the
price of hiding five thousand *adjacent* rows. The same five thousand,
scattered, cost **28.17 ms — 44.8× less** — and the two columns agree again
at *k* = *N*, where "scattered" and "contiguous" are the same one run.

The sweep itself is flat in all of this: 0.4 ms, 2.2 ms and 23.7 ms of
dispatch at one hundred, one thousand and ten thousand rows, whatever *k* is
and however the rows are laid out, because it reads every row and writes the
ones that moved.

### The law

Same five thousand hidden rows of ten thousand, framework-free, laid out as
`5 000/R` contiguous runs of length `R`:

| R | 1 | 10 | 25 | 100 | 500 | 1 000 | 2 500 | 5 000 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| forced (ms) | 23.6 | 22.7 | 28.5 | 42.9 | 128.7 | 233.0 | 549.7 | 1 083.4 |

which is `21.2 + 4.25·10⁻⁵ · k · R` to within 1% over the whole range where
the run term dominates — predicting 42.5, 127.5, 233.7, 552.5 and 1 083.7
against the last five columns — and within 2.2 ms in absolute terms at every
smaller *R*, where what is left is the floor of laying a ten-thousand-row
list out at all.

The cost of making a row not render is proportional to the number of
*layout-less siblings between it and the next rendered one*, so it is linear
in the rows
hidden and linear again in the length of the run they sit in — quadratic
only in the single case where the run is the whole set, which is exactly the
case ADR-0099's seed produced and ADR-0100 reported.

Neither factor is a compiler's to choose. `k` is the predicate and `R` is the
data.

## Decision

**The sealed filter keeps writing `hidden` per row.** Nothing in the
emission changes, no host export is added, and `runtimeAbi` stays 19.

### The container class, declined with a paired control

The proposal was to give each row a static attribute derived from its
`field == "literal"` predicate and hide the selection with one class on the
container plus a CSS rule. Measured against today's per-row `hidden` on a
byte-identical DOM — paired, **ABBA inside every pass**, five to nine
passes, per-cell minima, medians of the pass values — with an **A/A control**
(the per-row write against itself) run first in every cell:

| cell | A/A | per-row `hidden` | container class | ratio |
| --- | ---: | ---: | ---: | ---: |
| 10 000 rows, 5 000 hidden, contiguous | 0.999× | 1 077.07 | 1 080.06 | 0.997× |
| 10 000 rows, 5 000 hidden, spread | 1.001× | 21.68 | 21.29 | 1.018× |
| 10 000 rows, 1 000 hidden | 1.009× | 52.28 | 53.10 | 0.985× |
| 10 000 rows, all hidden | 0.999× | 4 331.93 | 4 332.25 | 1.000× |
| 1 000 rows, 500 hidden | 0.995× | 12.29 | 12.38 | 0.993× |
| 1 000 rows, all hidden | 0.995× | 45.01 | 45.13 | 0.998× |
| 100 rows, 50 hidden | 1.021× | 0.24 | 0.25 | 0.960× |

**Every cell is inside its own A/A band.** One class write is 0.01 ms against
1.3 ms of per-row property writes, and the 1.29 ms it saves buys nothing,
because the write was never the cost: what costs is that five thousand
elements stop rendering, and they stop rendering identically whether a
stylesheet or a property said so. The mount side is the same answer — one
extra static attribute per row costs **1.025× / 0.999× / 0.996×** at one
hundred, one thousand and ten thousand rows, inside the same band, so the
attribute would have been free and still bought nothing.

What it would have cost is worth recording even though it lost. The row
attribute is a function of a row field, so the reconcile and `updateAt`
would have to rewrite it on every field write — a per-row DOM write added to
the *update* path to remove one from the *filter* path — and the rule itself
would live in a stylesheet this compiler does not emit, cannot check, and
has no vocabulary to seal, which puts the filter's meaning outside the
elaborator for the first time. The ADR-0086 display cell would survive as
the attribute's cache, `childAt(container, i)` would survive unchanged, and
row identity, focus and the ADR-0086 cells would all be untouched: the
losses are real but small, and they are moot, because the win is zero.

### Detaching wins, and this ADR does not take it

The one shape that is not a wash is removing the filtered rows from the
container. Framework-free, ten thousand rows of the Toggle Lab row shape,
five thousand hidden as one run — write and forced style+layout, timed
apart:

| shape | write | forced | total |
| --- | ---: | ---: | ---: |
| per-row `hidden` (today) | 1.29 | 1 099.7 | 1 100.9 |
| one container class + CSS rule | 0.01 | 1 080.1 | 1 080.1 |
| replaced by comment placeholders | 232.4 | 3.5 | 235.9 |
| removed from the container | 11.2 | 3.3 | **14.5** |

**76× at that cell**, and 4 323 → 22.2 ms — **195×** — when every row is
filtered out. (The three scripts that produced this round's cells agree on
the shared cell to within 2%: 1 099.7, 1 083.4 and 1 077.1 ms for the same
per-row flip.)

Two things stop this ADR from taking it. The first is the placeholder row:
the shape that would have *kept* the region's positional identity — a
layout-less node standing in each hidden row's place, so
`childAt(container, i)` still means what it means — pays the same law, just
in the mutation instead of the recalc (232 ms of `replaceWith`). A
layout-less sibling is a layout-less sibling whichever kind of node it is,
so there is no cheap way to detach a row and keep its position.

The second is what that position is load-bearing for. ADR-0092's key-ordered
table, ADR-0094's caller-array order contract and ADR-0097/0098/0100's
`removeAt`, `insertAt` and `removeMany` all address a row by its position in
the row table *because that is also its position among the container's
children*. Detaching filtered rows breaks the identity: `insertAt`'s anchor
is `entries[position].node` and may be detached, `ownsWholeParent`'s
one-write clear never holds, and the sweep's `childAt` navigation stops
meaning anything. That is a host round with an ABI event in it, not a
sweep round, and it is stated as this ADR's first open question rather than
smuggled into it.

### Hiding the container, declined on a conflict rather than a number

When a filter matches *nothing*, hiding the container instead of every row
is one write against *N*: ten thousand rows cost **4 386.40 ms** row by row
and **31.59 ms** as one container — **139×**. It is declined anyway, and not
on the number. The wrapper already has exactly one declared writer of its
`hidden` property — ADR-0058's `hidden={count items == 0}`, whose subject is
*structural* emptiness and which ADR-0058 states explicitly does not follow
the filter — and a second writer of the same property on the same element is
precisely what ADR-0045's duplicate-attribute rejection exists to prevent.
Taking the 139× means giving the sweep a way to write an attribute a
selection owns, which is a larger hole than the case is worth: it is
reachable only when the filter matches no row at all.

### The route write, closed with a different mechanism

ADR-0100 attributed the flip's other twenty milliseconds to `:target`
invalidation and named `history.replaceState` as the obvious candidate.
Both halves are wrong. Measured on a framework-free document of ten thousand
rows, medians of nine, layout clean going in:

| row content | `location.hash =` | `replaceState` | `pushState` |
| --- | ---: | ---: | ---: |
| text only | 0.315 | 0.150 | 0.145 |
| one `<span>` | 0.505 | 0.205 | 0.220 |
| one `<button>` | 0.605 | 0.235 | 0.230 |
| one `<input type="checkbox">` | **17.850** | **16.865** | **16.970** |

The same page with no rows at all costs 0.095 / 0.055 / 0.055. So the cost
is not the fragment and not the API: it is **linear in the number of
stateful form controls in the document**, about 1.7 µs each, which is the
browser saving form-control state into the session-history entry, and every
history write pays it. A Toggle Lab row carries one checkbox, so a ten
thousand row region makes *every* route write cost 17 ms — and would make it
cost 17 ms if ADR-0063 had never written a hash at all, the moment anything
touched history.

`replaceState` therefore buys **0.95×** and costs the back-button contract,
which is not a trade. `pushState` buys the same 0.95× and keeps more than
expected — measured, a `pushState` fires neither `hashchange` nor
`popstate`, and a later `history.back()` over it fires **both**, with the
restored fragment, so ADR-0063's `listenHash` would still see every
traversal and would stop seeing only its own echo. It is declined on the
number regardless: 5% is not an ADR, and the contract it would change is the
one ADR-0081 sealed.

## Consequences

- **No emission changes.** `runtimeAbi` stays 19, no host export is added or
  removed, no region record slot moves, and every generated module in the
  repository is byte-identical to the one the previous commit produced. The
  js-framework-benchmark size baseline and the scalar manifest are
  unchanged, and BENCHMARK.md is untouched. Five files change: this ADR, the
  DECISIONS.md row, the DOGFOOD record, the language guide's filter-cost
  paragraph (which stated the `:target` attribution as fact) and the
  dynamic-regions note (which gains the sentence saying a filtered row is
  hidden and never detached, and what that is holding up).
- **The declines are recorded as numbers, not as arguments.** Three
  candidates were priced and three were rejected: the container class at
  0.960–1.018× against an A/A control of 0.995–1.021×, `replaceState` and
  `pushState` at 0.95×, and the container-hide at a real 139× that costs a
  second writer of an attribute a selection owns.
- **ADR-0100's headline number is corrected in place.** 1 282 ms is the cost
  of hiding five thousand *adjacent* rows; the same five thousand scattered
  cost 28 ms. Any future round quoting the filter flip's forced layout has
  to quote the distribution with it.
- **The route write's O(N) belongs to the row template.** It is one
  checkbox per row that makes a history write cost 17 ms at ten thousand
  rows, not the hash, not `:target` and not ADR-0063. A region whose rows
  carry no form control pays 0.15 ms for the same write.

## Open questions

1. **The detach lowering, priced but not taken.** Removing a filtered row
   from its container instead of hiding it is 76× at ten thousand rows and
   ends the run-length law entirely, and the placeholder that would have
   preserved `childAt(container, i)` pays the same law in the mutation. The
   round it needs is a host round: a region that knows which of its rows are
   attached, an `insertAt` anchor that skips the detached ones, and an
   `ownsWholeParent` that still recognises its own container — with
   ADR-0094's order contract restated over "displayed position" and
   ADR-0092's key table left alone.
2. **A row template that costs the document.** The checkbox that makes every
   history write O(N) is the same row template ADR-0089 fixed the arity of.
   Nothing in the vocabulary lets a component say a row's controls are not
   worth restoring, and nothing should without a reason better than one
   benchmark's 17 ms.
3. **The write-back is still the largest term.** ADR-0100's third open
   question is untouched: a `removeIf` at ten thousand rows is now a commit
   whose largest single term is the persistence write-back, and this round
   measured nothing that changes it.
