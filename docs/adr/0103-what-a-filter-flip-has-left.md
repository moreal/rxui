# ADR-0103: What is left of a filter flip

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0102 took the deselected rows out of the container and closed with the
number that says what it did not touch:

> **The show direction is now the largest term and nothing here touched it.**
> Putting five thousand rows back costs 84 ms of forced style and layout and
> 172 ms for ten thousand, identically in both shapes, because that is what
> rendering them costs.

Three terms are left on the new emission and this ADR prices all three. Every
one is a decline, and the round's finding is a fourth term nobody had named:
on a ten-thousand-row list the largest thing a filter flip's *commit* does is
no longer the sweep.

### The harness

ADR-0099's, at ADR-0101's settings: `performance.now()` probes inserted
mechanically into the *generated* Toggle Lab module with an exact-count
assertion on both anchors, COOP/COEP so the clock is 5 µs, keys pinned to
1..N so a re-seed is a retained reconcile, and every framework-free cell
re-asserting that the container holds every row in table order before the
number is believed. The probe set grows to ten — a `route` probe around the
ADR-0063 history write and two inside the write-back — and **all ten matched
exactly sixteen times on the first run**, the first of the last four rounds
in which no anchor had rotted (ADR-0100 caught two, ADR-0101 one, and
ADR-0102's record slots moved under all nine).

One harness fact is new and it is ADR-0101's, made worse. A re-seed must put
the DOM and the ADR-0086 display cells into the same state, and ADR-0102
raised the price of forgetting: a stale cell used to leave a row `hidden`
while the cell said shown, and now it leaves the row **out of the document**
while the cell says shown. The reconcile's restore-and-re-detach bracket
faithfully puts it back out, so the container silently holds half a table, the
sweep writes nothing, and every cell in the round reads a fraction of its
cost. The seed now walks the table and calls `setDisplayed(index, key, true)`
on every row.

## The measurement

### 1. The show direction is the floor, and the floor is a mount

The question is whether re-showing a detached row is "what rendering a row
costs" or something more. The contrast is the same final DOM reached two ways:
`k` rows are taken out of a list of `N`, and then either **those same nodes go
back** or **`k` brand-new clones go into the same `k` places**, through the
same backward-scan anchor, with the same number of `insertBefore` calls and
the cloning outside the timed span. Framework-free, Toggle Lab's row shape,
paired with ABBA inside every pass, per-cell minima, medians of the pass
values, against an A/A control read first:

| N / k | A/A | reattach | fresh mount | ratio |
| --- | ---: | ---: | ---: | ---: |
| 1 000 / 500 | 0.958× | 7.78 | 7.68 | 1.013× |
| 1 000 / 1 000 | 1.009× | 15.10 | 15.17 | 0.996× |
| 10 000 / 1 000 | 0.966× | 23.18 | 22.81 | 1.016× |
| 10 000 / 5 000 prefix | 0.988× | 82.16 | 84.24 | 0.975× |
| 10 000 / 5 000 spread | 0.979× | 85.07 | 86.15 | 0.987× |
| 10 000 / 10 000 | 0.999× | 154.51 | 155.20 | 0.996× |

**Every cell is inside its own A/A band.** Putting a row the filter took out
back into the document costs exactly what mounting a new one there costs: a
detached node carries no discount and no penalty, and the 84 ms and 172 ms
ADR-0102 measured are the price of rendering five and ten thousand rows.

The law, fitted over `N` from one thousand to twenty thousand and `k` from
two hundred and fifty to `N`, forced style and layout in milliseconds:

```
forced = 1.045 µs · N + 14.83 µs · k
```

| N | k | measured | predicted |
| ---: | ---: | ---: | ---: |
| 1 000 | 250 | 4.87 | 4.75 |
| 1 000 | 1 000 | 17.35 | 15.87 |
| 2 500 | 1 000 | 16.34 | 17.44 |
| 5 000 | 1 000 | 18.84 | 20.05 |
| 10 000 | 250 | 13.79 | 14.16 |
| 10 000 | 1 000 | 23.39 | 25.28 |
| 10 000 | 2 500 | 45.32 | 47.52 |
| 10 000 | 5 000 | 84.87 | 84.59 |
| 10 000 | 10 000 | 153.41 | 158.72 |
| 20 000 | 1 000 | 36.24 | 35.73 |
| 20 000 | 5 000 | 97.19 | 95.04 |
| 20 000 | 20 000 | 319.88 | 317.44 |

Worst residual 8.5%, at the smallest cell of all. So ADR-0102's "insensitive
to `N`" was nearly right and not quite: there is a second term, and it is
about one microsecond per row *already in the list*, which is the list being
laid out again around the rows that arrived. It is fourteen times smaller than
the term that matters, and neither term is a distribution: the spread and
contiguous columns agree everywhere.

What sets the 14.83 µs is the row, and the row is the program's:

| row template | nodes | forced per row shown |
| --- | ---: | ---: |
| text only | 2 | 5.45 µs |
| one `<span>` | 3 | 7.08 µs |
| three `<span>` | 7 | 9.05 µs |
| one `<span>` + one `<button>` | 6 | **11.36 µs** |
| Toggle Lab's row | 11 | 18.16 µs |
| Toggle Lab's row + 3 nodes | 17 | 23.79 µs |

It is not a node count — the six-node row with a button costs more than the
seven-node row of spans — and it is the same thing ADR-0101 found on the
history write: a form control costs the document more than a span does. **The
show direction is a floor and the floor's height is the row template**, which
is the author's declaration and not a lowering.

### 2. The bulk detach, declined at the shape that matters

The hide direction is now `k` calls to `setDisplayed` and, at `k` = `N` =
10 000, 22 ms of detach write. `removeMany` already carries the shape that
would replace it — one `parent.textContent = ""` for a parent the region owns
outright — and ADR-0101's objection to a container-wide write does not apply
here, because detaching is not writing an attribute and no selection owns it.
Only the hide side is priced: ADR-0102 already found the fragment slower on
the way back in.

Framework-free, ten thousand rows, every row out, write only:

| row template | nodes | `k` × `removeChild` | one `textContent = ""` |
| --- | ---: | ---: | ---: |
| text only | 2 | 6.97 | 6.03 |
| one `<span>` | 3 | 8.24 | 7.82 |
| three `<span>` | 7 | 13.50 | 13.47 |
| one `<span>` + one `<button>` | 6 | 13.16 | 13.19 |
| Toggle Lab's row | 11 | 22.13 | 22.49 |
| Toggle Lab's row + 3 nodes | 17 | 29.68 | 30.44 |

which fits `368 ns per row + 156 ns per DOM node inside it` at ten thousand
rows — **the detach is charged per node leaving the document, not per call** —
and paired, ABBA inside every pass, against an A/A control read first:

| cell | A/A | per-row | one write | ratio |
| --- | ---: | ---: | ---: | ---: |
| 10 000 rows, Toggle Lab's row | 1.014× | 21.740 | 22.320 | **0.974×** |
| 1 000 rows, Toggle Lab's row | 0.998× | 2.140 | 2.195 | **0.975×** |
| 100 rows, Toggle Lab's row | 0.963× | 0.270 | 0.245 | 1.102× |
| 10 000 rows, text-only row | 1.007× | 6.885 | 6.195 | 1.111× |
| 1 000 rows, text-only row | 1.007× | 0.745 | 0.675 | 1.104× |

**At the row shape the language actually emits it loses**, by 2.5% at both
counts, outside an A/A band of 0.998–1.014×. It wins 1.11× only on a row that
is a single text node, where the per-call constant is a fifth of the write
instead of a sixth of it — and 11% of that shape's 6.9 ms is 0.7 ms against a
round trip of 62.8 ms for the same rows, **1.1%**. The bar this round set was
10% of the round trip. The measurement is an order of magnitude under it in
the best case and negative in the real one.

A consequence for something already shipped: **ADR-0100's owned-parent clear
is one write and not one saving.** Its `parent.textContent = ""` is real and
its metric is honest — the bulk removal counts one write where the loop
counted `N` — but the browser charges the same either way, because what costs
is unparenting the subtrees and there are exactly as many of them. ADR-0100's
9.39× came from not entering the reconcile, which is where it always said the
win was; the clear is a tidiness, and the comment in the host that called it
"the one place the row count stops costing a detach each" is corrected.

### 3. The write-back, split three rounds on

ADR-0099 declined the write-back at 74% of a ten-thousand-row `append`'s
commit and ADR-0100 and ADR-0101 each left the question standing. Everything
around it has since been folded, so the share has moved. Milliseconds,
commit-scoped, medians of five page loads at seven to fifteen dispatches each:

| action | commit | write-back | share | row loop | `join` + `setItem` |
| --- | ---: | ---: | ---: | ---: | ---: |
| `append`, 10 000 rows | 0.840 | 0.784 | **93.4%** | 0.049 | 0.736 |
| `removeIf` 1 of 10 000 | 0.806 | 0.766 | **95.0%** | 0.031 | 0.735 |
| `removeIf` 100 of 10 000 | 1.042 | 0.764 | 73.3% | 0.031 | 0.733 |
| `removeIf` 1 000 of 10 000 | 3.281 | 0.747 | 22.8% | 0.031 | 0.714 |
| `removeIf` 5 000 of 10 000 | 13.284 | 0.408 | 3.1% | 0.022 | 0.387 |
| `append`, 1 000 rows | 0.072 | 0.052 | 72.1% | 0.006 | 0.047 |
| `removeIf` 1 of 1 000 | 0.065 | 0.052 | 80.9% | 0.004 | 0.048 |
| `broadcast`, 10 000 rows | 14.335 | 4.773 | 33.3% | 4.251 | 0.527 |
| filter flip, 10 000 rows | 22.5–46.8 | **0** | 0% | 0 | 0 |

74% is now **93.4%**, and a single-row `removeIf` is 95.0%. Nothing about the
write-back grew — it is 0.78 ms where ADR-0099 measured 0.66 — the rest of the
commit shrank around it, which is what four rounds of folding are for.

**The sub-split is the answer the ratio is not.** Of the 0.784 ms, the row
loop that builds the segment array is **0.049** and the `join` plus the
`setItem` are **0.736**: 94% of the write-back is one string and one store
over a payload that is the whole table by ADR-0063's contract, and there is no
row term left to narrow. ADR-0099 declined on "two thirds of it is bytes";
on the current emission it is 94%, because the ADR-0085 per-row serialization
cache has made the loop nearly free — a narrow commit re-encodes one row. The
broadcast is the same cache read from the other side: every row's cell is
stale, the loop is 4.25 ms of ten thousand re-encodings, and the store is
0.53. All three of ADR-0099's declines stand, and the one that mattered
stands harder.

The click-scoped number is worth keeping beside it. A ten-thousand-row
`append` dispatches in 0.85 ms and dirties 6.06 ms of style and layout, so
the write-back is **11.3% of what a user waits for**, not 93%.

### 4. What a filter flip's commit actually spends: the history write

Splitting the flip's commit in **both** directions is what this round was
missing. The `route` probe, ten thousand rows, ADR-0102's emission:

| N / k | hide: route | sweep | commit | show: route | sweep | commit | route, round trip |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 / 100 | 21.03 | 0.40 | 21.45 | 20.46 | 0.11 | 20.58 | 41.49 |
| 10 000 / 1 000 | 20.78 | 2.85 | 23.61 | 17.90 | 0.47 | 18.38 | 38.68 |
| 10 000 / 5 000 prefix | 20.30 | 13.47 | 33.78 | 9.22 | 2.04 | 11.31 | 29.52 |
| 10 000 / 5 000 spread | 20.51 | 15.94 | 36.50 | 10.22 | 2.22 | 12.44 | 30.73 |
| 10 000 / 10 000 | 20.87 | 27.64 | 48.34 | 0.33 | 3.97 | 4.31 | 21.20 |
| 1 000 / 500 | 1.84 | 1.28 | 3.12 | 0.94 | 0.18 | 1.12 | 2.78 |
| 1 000 / 1 000 | 1.85 | 2.58 | 4.43 | 0.14 | 0.36 | 0.50 | 1.99 |

**The route write is 88% of the hide commit at `k` = 1 000 and 44% at
`k` = `N`, and the sweep only overtakes it once half the table moves.**
ADR-0100 read 21.5 of a 24.7 ms flip and ADR-0101 named the mechanism; what
ADR-0102 changed is that the number is no longer a constant. It is
**2.06 µs × the rows in the document at the moment of the write** — 20.87 for
ten thousand, 20.46 for nine thousand nine hundred, 17.90 for nine thousand,
9.22 for five thousand, 0.33 for none, and 1.85 for a thousand-row list — and
since ADR-0102 the sweep changes that count inside the same commit.

So the emission has a free choice it did not have before: the route write sits
before the region sweeps, and moving it after them would let the hide
direction pay for the document it leaves rather than the one it entered.
**It is a wash, and the table above is why.** Before the sweep the hide
direction pays `f(N)` and the show direction pays `f(N − k)`; after it, the
hide direction pays `f(N − k)` and the show direction pays `f(N)`. The round
trip pays `f(N) + f(N − k)` either way, and a filter that hides also un-hides.

Measured rather than argued — two dists of the generated module differing
only in the position of sixteen statements, the same multiset of lines, one
page each plus a second page of the first as the A/A control, ABBA inside
every pass, the whole round trip in both directions:

| cell | A/A | route first | route last | ratio |
| --- | ---: | ---: | ---: | ---: |
| 10 000 rows, all deselected | 0.991× | 264.29 | 268.63 | 0.984× |
| 10 000 rows, 5 000 contiguous | 0.972× | 162.76 | 160.65 | 1.013× |
| 10 000 rows, 5 000 spread | 0.998× | 167.57 | 166.25 | 1.008× |
| 10 000 rows, 1 000 contiguous | 0.985× | 78.24 | 79.09 | 0.989× |
| 1 000 rows, all deselected | 1.015× | 26.42 | 26.09 | 1.013× |
| 1 000 rows, 500 contiguous | 1.037× | 15.88 | 15.83 | 1.003× |
| 1 000 rows, 500 spread | 0.997× | 15.85 | 15.65 | 1.013× |
| 100 rows, 50 contiguous | 1.013× | 1.80 | 2.02 | 0.889× |

Every cell inside its own control, and the one that is not is 1.8 ms.

## Decision

**Nothing changes.** No host export, no record slot, no statement order;
`runtimeAbi` stays 20 and every generated module in the repository is
byte-identical to the one the previous commit produced.

Three terms were priced and three are declined, each on a number rather than
an argument:

- **The show direction is the floor.** Re-showing a detached row is 0.975–
  1.016× against mounting a fresh one, inside an A/A band of 0.958–1.009×.
  What is left to spend is `1.045 µs · N + 14.83 µs · k` of style and layout,
  the second term set by the row template — 5.45 µs for a row of text, 18.16
  for Toggle Lab's four cells, checkbox and two buttons. ADR-0102's first
  open question is **closed**: showing fewer rows than the filter selects is
  the only thing left that would move it, and that is a language question
  about what a region promises, not a lowering of what it already promises.
- **The bulk detach loses at the shape that matters.** One owned-parent write
  is 0.974× against `k` `removeChild` calls on Toggle Lab's row, and 1.111× —
  0.7 ms, 1.1% of that shape's round trip — on a row that is one text node.
  The detach is `368 ns/row + 156 ns/node`, so a bulk call removes the calls
  and not the nodes.
- **The write-back keeps its `N`.** It is 93.4% of a ten-thousand-row append's
  commit and 11.3% of the click, and 94% of *it* is one `join` and one
  `setItem` over a payload the contract defines as the whole table. ADR-0085's
  cache has already taken the row term down to 6%.

And one term is **named** rather than declined, because naming it is the
result: on a ten-thousand-row list the largest thing a filter flip's commit
does is the ADR-0063 history write, at 2.06 µs per row *in the document*, and
the only lowering that could move it — writing the hash when the document is
smallest — is a wash across the round trip by construction and measures as
one.

## Consequences

- **Two files carry a source change and neither changes behaviour.**
  `runtime/leanrx_region.mjs` corrects the `removeMany` comment that called
  the owned-parent clear "the one place the row count stops costing a detach
  each" — it stops costing a *call* each — and gives `setDisplayed` the two
  laws this round measured, so the next reader does not re-derive them. The
  region host grows 20 644 → **21 423** bytes in the eight bundles that ship
  it (Branch, Grid, Issue Browser, Mix, Nest, Todo, Toggle, Twin); no
  generated module, no manifest, no `graphHash` and no size baseline moves,
  because nothing the compiler emits changed — Toggle Lab's module and its
  manifest were regenerated and compared byte for byte against the previous
  commit's.
- **The guide and the dynamic-regions note gain the numbers and lose a
  stale one.** The guide's flip paragraph said the flip costs 24.7 ms of
  commit with 21.5 of it the history write, which was one cell of one
  direction before the rows started leaving the container; it now carries the
  per-direction split and the `2.06 µs × rows displayed` rule. Both documents
  gain the show-direction law and the bulk-detach decline.
- **The probe set is ten and every anchor held.** `route`, `persistLoop` and
  `persistStore` join the seven ADR-0099 anchors, all at exactly sixteen
  sites on the first run — the first of the last four rounds in which the
  count assertion found nothing, which is worth recording precisely because
  the three before it were each caught by it.
- **ADR-0102's open question 1 is closed and ADR-0100's open question 3 is
  answered as far as measurement can answer it.** The remaining share is a
  contract, not a lowering: narrowing the write-back means narrowing what
  `persist` promises to have written when a commit returns.

## Open questions

1. **A row template that costs the document, for the third time — and the
   platform's own word for it.** The 14.83 µs per row shown, the 156 ns per
   node detached and the 2.06 µs per row of history write are all the same
   fact from three directions: a row carrying one checkbox and two buttons
   costs the browser more than a row carrying text, in rendering, in removal
   and in session history alike. ADR-0101 raised it with the sentence that
   nothing in the vocabulary lets a component say a row's controls are not
   worth restoring — and `autocomplete="off"` is exactly that sentence, said
   to the browser. Scouted framework-free and coarsely (medians of nine, not
   paired, run beside a CPU-bound gate), `location.hash =` over ten thousand
   rows costs **18.29 ms** with a plain checkbox per row, **1.05 ms** with
   `autocomplete="off"` on it, and 0.375 ms with no control at all; at a
   thousand rows, 1.90 / 0.24 / 0.18. That is a **17×** on the largest term
   this round named, and it is one static attribute per row, which ADR-0101
   already measured as free on the mount path (1.025×/0.999×/0.996×). What it
   would cost is the browser's own form-state restoration across reload and
   back-forward — redundant for a program that persists and rehydrates its
   rows through ADR-0063, and not redundant for one that does not — and that
   sentence has to be written and priced before the attribute is emitted.
   Nothing here takes it: this is a scout, and the round that takes it owes a
   paired measurement on the real emission and a statement of what a user
   loses.
2. **Showing fewer rows than the filter selects.** The one lowering that
   would move the show direction is a region that renders a window of its
   selection rather than all of it, and the number that would justify it is
   `14.83 µs · k`: 74 ms for five thousand rows a user cannot see at once.
   What it costs is that a region's rows stop being *the* rows — every count,
   every sweep and every `childAt`-free positional export is written against
   a table that is entirely rendered — so it is a language round, and a large
   one.
3. **`swapAt` and the filter still cannot meet.** ADR-0102's second open
   question is untouched: no emission puts a swap and a filter on one region,
   so the displayed-anchor branch remains exercised only by the host gate.
