# ADR-0100: A removal removes its rows, however many there are

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0097 declined `removeIf`, ADR-0098 declined hydration, and ADR-0099
closed by naming what the two declines have in common:

> **The bulk threshold, still open from both ends.** ADR-0097 declined
> `removeIf`, ADR-0098 declined hydration, and this ADR declines neither
> because it touches neither — but the accumulator's rescan is now a third
> O(N) thing gated on the same dirty bit, so whatever threshold answers that
> question will have three subjects rather than two.

Three questions, then: where a wide path's time actually goes, whether a
threshold in the generated code is justified, and what the largest number in
ADR-0099's paired table is made of.

### The harness, and the boundary it draws

The same shape as ADR-0099's: `performance.now()` probes inserted
mechanically into the *generated* Toggle Lab module, one around every O(N)
consumer of the commit body, driven with real dispatches against a region
seeded to 100, 1 000 and 10 000 rows, medians of five page loads. The page is
served with COOP/COEP so Chromium's clock is 5 µs rather than the default
100 µs clamp.

Two harness facts are worth stating because both of them produced a wrong
number first.

**Every probe is anchored on generated statement text, and a rename measures
zero rather than failing.** So the injector asserts an exact count for both
ends of every probe — sixteen, one per transaction function — and two of the
nine anchors were wrong on the first run: one matched thirty-two times
(the reconcile's tail and the append drain's end are the same two lines) and
one fifteen (the region's own dispatch function spells the filter sweep's
guard `region_drain_0_0`, not `region_touched_0`). Neither would have thrown.

**Seeding a row table is not the same as committing one.** The first version
installed rows straight into `regions[r][1]` and reconciled them, which leaves
every attr cache saying what it said when the region was empty — including
the ADR-0058 `hidden` on the list wrapper. Every DOM write in every cell then
went into a `display:none` subtree, and the forced layout after a five-
thousand-row filter flip read **0.010 ms** instead of 1 282. The seed now
settles through one real, untimed commit.

### Where the wide paths' time is

Milliseconds, one commit, medians of five page loads. `k` is the number of
rows the action removes; `layout` is `document.body.offsetHeight` forced
after the dispatch returns, timed apart.

| rows | action | k | body | rescan | reconcile | drain | sweep | write-back | **commit** | layout |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 | `removeIf` | 1 | 0.134 | 0.152 | **12.409** | 0 | 0.179 | 0.998 | **13.763** | 8.18 |
| 10 000 | `removeIf` | 100 | 0.138 | 0.152 | **12.849** | 0 | 0.181 | 1.045 | **14.267** | 8.81 |
| 10 000 | `removeIf` | 1 000 | 0.147 | 0.143 | **14.286** | 0 | 0.163 | 0.993 | **16.090** | 7.84 |
| 10 000 | `removeIf` | 9 999 | 0.162 | 0 | **26.920** | 0 | 0.001 | 0.040 | **26.988** | 0.16 |
| 10 000 | `broadcast` | — | 0.096 | 0.150 | 13.950 | 0 | 0.177 | 6.584 | **20.908** | 13.08 |
| 10 000 | `hydrate` | — | 8.404 | 0.477 | 38.009 | 0 | 2.540 | 6.513 | **47.315** | 240.9 |
| 10 000 | filter flip | — | 0 | 0 | 0 | 0 | **2.558** | 0 | **24.661** | 1 282.3 |
| 1 000 | `removeIf` | 1 | 0.013 | 0.012 | **1.110** | 0 | 0.012 | 0.172 | **1.328** | 0.47 |
| 1 000 | `removeIf` | 100 | 0.014 | 0.012 | **1.268** | 0 | 0.013 | 0.165 | **1.483** | 0.48 |
| 1 000 | `removeIf` | 999 | 0.021 | 0.001 | **2.623** | 0 | 0.002 | 0.033 | **2.683** | 0.12 |
| 100 | `removeIf` | 1 | 0.003 | 0.002 | **0.101** | 0 | 0.003 | 0.023 | **0.140** | 0.07 |
| 100 | `removeIf` | 99 | 0.003 | 0.001 | **0.257** | 0 | 0.001 | 0.018 | **0.289** | 0.05 |

Three readings.

**A `removeIf` is the reconcile and almost nothing else.** At ten thousand
rows, removing *one* row costs 13.76 ms of which 12.41 is `update`, and the
other two dirty-bit consumers this round was told to expect — the ADR-0099
rescan at 0.15 and the ADR-0051 wide sweep at 0.18 — are together 2.4% of it.
The write-back is 1.00 ms and stays (ADR-0099). The reconcile is nearly flat
in *k* and linear in *N*, which is the shape of its cost: it re-renders the
*N − k* rows it retains, whatever *k* is.

**The filter flip's 20.5 ms is not the sweep.** The sweep is **2.56 ms** of a
24.66 ms commit. The rest is one statement — `writeHash`. Timed bare, with
layout clean going in and no LeanRx code between the two clock reads, an
assignment to `location.hash` costs **19.8–22.2 ms at ten thousand rows,
1.9–2.1 ms at one thousand and 0.20 ms at one hundred**: changing the URL
fragment invalidates `:target` for the whole document, so it is O(N) and it
is the browser's. ADR-0063's route write has been paying it since it landed
and no compiler decision reaches it.

**The layout after the flip is fifty times the commit, and none of it is
ours.** Hiding five thousand of ten thousand rows costs 1 282 ms of forced
style and layout. A control that writes the same five thousand `hidden` bits
straight onto the nodes — no sweep, no framework, one loop — pays **1 237 ms**
for the same flip and 126 ms for the reverse. The asymmetry is the browser's
too.

### The crossover, in numbers

The question the round asked directly: at what *k* does repeating the host's
per-row `removeAt` beat handing the whole table to `update`? Measured in the
real host with the real generated callbacks, ABBA inside every rep, five
passes, medians — milliseconds:

| rows | k | `update` | k × `removeAt` | ratio |
| ---: | ---: | ---: | ---: | ---: |
| 10 000 | 1 | 11.05 | 0.048 | **210×** |
| 10 000 | 100 | 11.16 | 0.743 | 15.0× |
| 10 000 | 1 000 | 12.81 | 9.41 | 1.36× |
| 10 000 | 2 000 | 16.91 | 9.72 | 1.74× |
| 10 000 | 5 000 | 18.96 | 24.56 | 0.77× |
| 10 000 | 9 999 | 26.89 | 29.20 | 0.92× |
| 1 000 | 1 | 1.152 | 0.036 | 32× |
| 1 000 | 100 | 1.165 | 0.358 | 3.3× |
| 1 000 | 500 | 1.789 | 1.459 | 1.23× |
| 1 000 | 999 | 2.553 | 2.756 | 0.93× |
| 100 | 1 | 0.103 | 0.017 | 6.1× |
| 100 | 50 | 0.181 | 0.135 | 1.34× |
| 100 | 99 | 0.260 | 0.251 | 1.04× |

**The crossover exists and it is neither a constant nor a ratio.** Per-row
removal wins up to *k* ≈ 2 000 at ten thousand rows, *k* ≈ 900 at one
thousand, and *k* ≈ 99 at one hundred: as a fraction of the table that is
0.20, 0.90 and 0.99, and as an absolute count it is 2 000, 900 and 99. Both
readings of the question are wrong, and the model says why. The reconcile
costs `a·(N − k)` with *a* ≈ 1.15 µs of `updateItem` per *retained* row; the
per-row loop costs *k* splices each moving about `N − k/2` array elements at
≈ 0.5 ns. The crossover solves `a(N − k) = σk(N − k/2)`, which is a constant
`a/σ` ≈ 2 300 while *k* ≪ *N* and collapses toward *N* as *k* approaches it.
Fitting σ at the ten-thousand-row crossover and predicting the other two out
of sample gives 790 and 96 against 900 and 99 measured.

**And the crossover is an artifact of the splice.** Nothing in a bulk removal
needs *k* separate shifts of the same array. One call that validates the
whole set, disposes and detaches its rows, and then closes the gaps with one
native `copyWithin` per surviving run costs — same harness, ABBA over four
lowerings, five passes:

| rows | k | `update` | k × `removeAt` | one `removeMany` | bulk/many | removeAt/many |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 | 1 | 11.05 | 0.048 | 0.052 | **210×** | 0.92× |
| 10 000 | 10 | 10.99 | 0.112 | 0.075 | 147× | 1.49× |
| 10 000 | 100 | 11.16 | 0.743 | 0.321 | 34.8× | 2.32× |
| 10 000 | 1 000 | 12.81 | 9.41 | 2.657 | 4.82× | **3.54×** |
| 10 000 | 2 000 | 16.91 | 9.72 | 5.585 | 3.03× | 1.74× |
| 10 000 | 5 000 | 18.96 | 24.56 | 12.98 | 1.46× | 1.89× |
| 10 000 | 9 999 | 26.89 | 29.20 | 25.89 | 1.04× | 1.13× |
| 10 000 | 10 000 | 25.57 | 29.23 | 25.66 | 1.00× | 1.14× |
| 1 000 | 1 | 1.152 | 0.036 | 0.037 | 30.7× | 0.95× |
| 1 000 | 500 | 1.789 | 1.459 | 1.265 | 1.41× | 1.15× |
| 1 000 | 999 | 2.553 | 2.756 | 2.476 | 1.03× | 1.11× |
| 100 | 1 | 0.103 | 0.017 | 0.014 | 7.3× | 1.22× |
| 100 | 99 | 0.260 | 0.251 | 0.244 | 1.06× | 1.03× |
| 100 | 100 | 0.237 | 0.255 | 0.240 | 0.99× | 1.06× |

One call ties `removeAt` at *k* = 1 (0.92–1.22× across the three table sizes,
inside the harness's own bias floor), beats it at every larger *k* up to
3.54×, and is never worse than the reconcile anywhere — the two cells that
read 0.99× and 1.00× are the whole table at once, where both paths clear an
owned parent in one write.

## Decision

**A removal removes its rows, however many there are.** The keyed region host
gains one export, the ADR-0097 drain calls it once, the ADR-0050 predicate
removal queues into the same slot, and **no threshold is emitted anywhere**.

### `removeMany`, the ABI 19 export

`removeMany(drops, context)` takes `drops`, a strictly ascending array of
`[position, key]` pairs against the order the call starts in. Every pair is
checked before any callback or DOM mutation (`LRX-REGION-003` otherwise,
exactly as `removeAt` checks its one); the named rows are disposed and
detached and their keys leave the index; and the survivors close the gaps
with one `copyWithin` per surviving run. Every survivor keeps its handle, its
node and its rendering, and no update callback runs. A set that names every
row of a parent the region owns outright clears it in one write, which is the
`rebuild` path's trick and the only place the row count stops costing a
detach each.

The contract it hands the caller is `removeAt`'s, once for the whole set
instead of once per row, which is what makes the ADR-0094 order contract's
answer mechanical: `drops` is a caller array the host reads and never
mutates, declared as such in the surface table, and H4 requires it to be
exercised under the guard.

### The drain calls it once, whatever the length

The commit sweep's ADR-0097 loop becomes one call. This is where the round's
question is answered as a *decision* rather than a measurement: there is no
`if (queue.length < T)` in the emission, because the measurement above says
no *T* is worth its own branch — the one-row case ties the loop it replaces
and every larger one beats it.

The single-row path ADR-0097 built is unchanged in everything but the call it
drains through: the dispatch still keeps the position ADR-0092 resolved,
still queues `[position, key]`, and still falls back to the dirty bit when it
cannot.

### The predicate removal joins the queue

An ADR-0050 `remove items (…)` stops raising the dirty bit. Its one loop —
the loop that has always built the survivor array — now carries three jobs:

- the survivor push, unchanged;
- `[position, key]` pushed onto the ADR-0097 queue for each dropped row, in
  ascending order because it walks the table in order;
- the ADR-0099 accumulator decremented by exactly what left, which is the
  same delta the sealed single-row removal already applies.

So all three of the dirty bit's O(N) consumers go quiet on a predicate
removal at once. The reconcile is replaced by the drain. The rescan is
unnecessary because the accumulator was moved by the loop that found the
rows. And the ADR-0051 filter sweep takes its narrow path and reads *zero*
rows, for the reason ADR-0099 already established: a removal shifts survivors
whose fields did not change and whose DOM nodes were never touched.

The queue guard is ADR-0097's, one conjunct wider on both sides. A position
is only meaningful against the table the site that recorded it started from,
so the queue must be filled by exactly one site per transaction: the
predicate removal falls back to the dirty bit if the queue, the ADR-0043
pending array or the ADR-0098 append counter is non-empty, and the sealed
removal now reads the queue beside the two it already read. Exactly one
action branch runs per dispatch and every commit empties all three, so the
fallback is unreachable today — it is emitted for the reason ADR-0097's is,
and the host's key check is what would say so at run time if the reasoning
were ever wrong.

### The broadcast, declined with a number

An ADR-0050 broadcast writes every row's fields, so every row's DOM has to be
rewritten; the only question is whether the reconcile is the wrong vehicle
for it. Measured: one bulk `update` against *N* `updateAt` calls, ten
thousand rows, **11.92 ms against 12.12 ms — 0.98×**, and 1.03× and 0.92× at
one hundred and one thousand. The reconcile's per-row `updateItem` loop *is*
the work a broadcast owes; the key validation, the placement and the entry
bookkeeping around it are not what a broadcast costs. It keeps the dirty bit.

### Hydration, declined again with a number

ADR-0098 declined hydration on the shape of the placement — nothing retained,
so `rebuild` refills a *detached* owned parent — and this round measured the
other side of it: one bulk `update` into an empty region against *N*
`insertAt` calls, ten thousand rows, **37.05 ms against 36.04 ms — 1.03×**,
and 1.09× and 0.95× at one hundred and one thousand. Inside the bias floor,
against a path whose emission would have to store positions it currently does
not. It keeps the dirty bit.

### The filter sweep, declined with a control

The 20.5 ms cell was the largest number in ADR-0099's paired table and 87% of
it is `location.hash`. Of the 2.56 ms that is actually the sweep, the floor is
the writes it must do: a filter state change moves every row's predicate, so
every row must be evaluated, and the sweep already writes only the rows whose
displayed state changed (ADR-0086). Reading fewer than *N* rows would need
the region to keep a per-predicate bucket of positions, which is a
positionally-keyed cache of the kind ADR-0087 priced and declined and ADR-0099
declined again. There is nothing to fold, and the number that made the cell
look foldable belongs to a different statement.

## Consequences

- **`runtimeAbi` moves 18 → 19** with twenty-six mechanical references — the
  version constant, seventeen artifact gates, six Lean backend tests, the
  scalar manifest string, the CLI doctor line and the region contract's
  surface table.
- Paired A/B against the pre-change emission, both variants in one browser
  process, **ABBA inside every cell of every pass** over ten passes, medians
  of per-cell minima, every node lookup outside the timed step. An **A/A
  control** — the same dist against a byte copy of itself — runs first and
  reads **0.980–1.017×** across all thirteen cells, which is the bias floor
  the numbers below are read against. Milliseconds, dispatch-scoped.

  | cell | before | after | ratio |
  | --- | ---: | ---: | ---: |
  | 10 000 `removeIf`, 1 row | 12.007 | 1.279 | **9.39×** |
  | 10 000 `removeIf`, 100 rows | 12.194 | 1.719 | **7.09×** |
  | 10 000 `removeIf`, 1 000 rows | 13.632 | 4.147 | **3.29×** |
  | 10 000 `removeIf`, 5 000 rows | 20.718 | 15.735 | **1.32×** |
  | 10 000 `removeIf`, 9 999 rows | 27.312 | 28.306 | 0.965× |
  | 1 000 `removeIf`, 1 row | 0.790 | 0.131 | **6.02×** |
  | 1 000 `removeIf`, 100 rows | 0.967 | 0.391 | **2.48×** |
  | 1 000 `removeIf`, 999 rows | 2.958 | 3.000 | 0.986× |
  | 100 `removeIf`, 50 rows | 0.215 | 0.185 | 1.16× |
  | 10 000 `append` | 1.007 | 1.144 | 0.880× |
  | 10 000 `broadcast` | 19.202 | 19.276 | 0.996× |
  | 10 000 filter flip | 22.635 | 23.077 | 0.981× |
  | 10 000 `hydrate` | 57.250 | 57.352 | 0.998× |

  The three declines land inside the A/A band, which is the statement that
  the change took nothing from the paths it deliberately did not touch.

  Two cells sit outside it, and a focused re-run over sixteen passes —
  with its own A/A control — separates them.

  The **`append` at 0.880× is noise**: re-run, it reads **1.023×** against an
  A/A control of 1.013×. It could not have been anything else. The two
  emissions of `$lrx_event_0` differ in exactly the lines *inside* the
  removal drain's `if (queue.length !== 0)`, which an append never enters —
  47 bytes in a function an append runs around.

  The **removal of almost every row is a real 4%**, and it reproduces:
  0.958× at 9 999 of 10 000 (A/A 1.004×) and 0.980× at 999 of 1 000
  (A/A 1.003×). It is the far end of the crossover the host measurement
  already showed. With one row retained the reconcile has almost no
  `updateItem` loop left to skip, and what remains is the *k* detaches both
  paths owe; removing *every* row is 1.00×, because there the drain takes the
  same one-write clear the reconcile takes. Trading 4% at *k*/*N* = 0.999 for
  **9.4× at *k* = 1** is the trade this emission makes, and it is also why the
  decision is "one call" rather than "a threshold": a threshold that recovered
  this cell would have to fire within a row of the table's length, and it
  would have to be a *ratio*, which the crossover measurement says the
  boundary is not.
- **The js-framework-benchmark size gate moves**, and this is the second time
  an ABI export has moved it: that backend inlines the whole keyed host, so
  `main.mjs` grows **8 776 → 9 345 raw bytes (+6.5%, brotli 3 200 → 3 400)**
  for an export its own emission never calls. The baseline JSON is updated;
  BENCHMARK.md's timings are unaffected and untouched.
- Generated modules change wherever a region has a removing path — exactly
  the five labs that declare one, Branch, Nest, Twin, Mix and Toggle — and
  every other generated module is unchanged. `leanrx_region.mjs` changes in
  the eight bundles that ship it. Toggle Lab's module gets **174 bytes
  smaller**: the drain's loop and its per-row trace push cost more than the
  predicate removal's queue bookkeeping.
- **The witness is a count of rows, not of calls.** The drain's trace entry
  carries its length — `region:{region}:removeMany:{n}` — so one Toggle Lab
  test pins a three-row predicate removal at one call for three rows, zero
  `region:items:update`, zero mounts, zero updates, zero moves, three
  disposals, every survivor keeping its exact DOM node, *no*
  `predicate:items:read:` entry at all, and `filter:items:read:0` beside
  `filter:items:written:0`. A second pins the whole-table case at one
  `removeMany:4` into an emptied, re-mountable region.
- The host gate gains a `removeMany` section: an ascending set with three
  separate gaps, an empty set as a no-op, five rejections that leave the
  table untouched (a key not at its position, a descending pair, a repeated
  one, a position past the end, and a bad pair after a good one), the key
  index proven clean afterwards, the owned-parent clear counted as one bulk
  write, and a no-op after disposal.

## Open questions

1. **The layout that dwarfs all of this, restated with a control.** ADR-0099
   left the 9.5 ms of layout an append dirties as its open question. This
   round measured a worse one — 1 282 ms to hide five thousand rows — and
   attributed it, with a framework-free control, entirely to the browser.
   What a compiler could still reach is the *shape* of what it writes:
   `hidden` on five thousand `<li>` elements is five thousand style
   invalidations, where one class on the container plus a CSS rule would be
   one. That is a row-template question, not a sweep question, and this line
   of ADRs has never asked it.
2. **The route write's O(N) fragment cost.** ADR-0063 writes the hash to keep
   the URL canonical, and at ten thousand rows that assignment alone is
   20 ms — more than the entire commit around it. Whether a routed filter
   can write the hash without a `:target` invalidation (`history.replaceState`
   is the obvious candidate and changes the back-button contract) is a
   routing question this ADR does not open.
3. **The last O(N) consumer with no threshold left to discuss.** The
   write-back walks every row on every region touch, and ADR-0099 declined it
   from three sides. Nothing here changes that; but a `removeIf` at ten
   thousand rows is now a commit whose largest single term *is* the
   write-back, which is the first time that has been true of a structural
   path.
