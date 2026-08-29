# ADR-0096: A persisted region's write costs its bytes and its join costs its rows

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0087 stopped the persistence line on one sentence: `storageSet` and the
`join` are the floor at 35% each, neither narrows under identity keying, and
moving either needs the position-keyed cache that ADR rejected "or a storage
host that takes something other than one string — which would be an ABI
question, not a codegen one." ADR-0088, 0092, 0093, 0094 and 0095 all handed
that open question forward untouched.

Two things had to happen before it could be answered. The denominator moved
underneath it — ADR-0088 fused the predicate scans and ADR-0092 replaced the
key scan with a binary search, so the shares ADR-0087 published are shares of
a commit that no longer exists. And ADR-0087 priced the two segments without
ever asking what they are functions *of*. It had no reason to: they measured
the same size, so it read them as one floor.

### Re-measuring the ladder

The method is ADR-0085's, re-derived against the shipped emission as ADR-0087
warned it must be: hand-edited copies of the *generated* Toggle Lab module,
each rung removing one more segment, driven through the region dispatch over
one seeded row table. L1 keeps the `join` and drops the `storageSet`; L2 keeps
the push loop and drops the `join`; L3 drops the persistence sweep. Every rung
is checked to leave a byte-identical row table (a hash over all four fields of
every row) so the rungs price the same work. Interleaved by variant, three
repetitions, median of medians of five runs, ms per commit:

| rows | payload | commit | L0 | L1 | L2 | L3 |
| ---: | ---: | --- | ---: | ---: | ---: | ---: |
| 10 000 | 248 KB | `toggle` | 0.6198 | 0.3862 | 0.1355 | 0.0973 |
| 10 000 | 248 KB | `retype` | 0.5060 | 0.2685 | 0.0395 | 0.0010 |
| 10 000 | 248 KB | `remove` | 5.7215 | 5.1520 | 5.3570 | 4.9540 |
| 10 000 | 248 KB | `append` | 5.9420 | 5.7995 | 5.3025 | 4.5630 |
| 1 000 | 22.8 KB | `toggle` | 0.0565 | 0.0355 | 0.0158 | 0.0140 |
| 100 | 2.1 KB | `toggle` | 0.0122 | 0.0050 | 0.0030 | 0.0017 |
| 1 000 | 223 KB | `toggle` | 0.2675 | 0.0560 | 0.0180 | 0.0142 |

Differenced into shares of L0:

| rows | payload | commit | `storageSet` | `join` | push loop | rest |
| ---: | ---: | --- | ---: | ---: | ---: | ---: |
| 10 000 | 248 KB | `toggle` | 37.7% | 40.5% | 6.2% | 15.7% |
| 10 000 | 248 KB | `retype` | 46.9% | 45.3% | 7.6% | **0.2%** |
| 10 000 | 248 KB | `remove` | 10.0% | — | — | 86.6% |
| 10 000 | 248 KB | `append` | 2.4% | 8.4% | 12.4% | 76.8% |
| 1 000 | 22.8 KB | `toggle` | 37.2% | 35.0% | 3.1% | 24.8% |
| 100 | 2.1 KB | `toggle` | **59.2%** | 16.3% | 10.2% | 14.3% |
| 1 000 | 223 KB | `toggle` | **79.1%** | 14.2% | 1.4% | 5.3% |

Three of those rows say something ADR-0087's two did not.

**On a `retype` the persistence sweep is 99.8% of the commit.** ADR-0082's
drain-scoped wake gave the region dispatch a flag per sweep: the predicate
pass and the filter sweep wake on `region_drain_0_0` (structural, or a
`toggle`), the hidden-attr scan on `region_drain_0_1` (`edit`/`commit`/`keys`).
A `retype` — the per-keystroke event of an editing row — wakes none of them.
The persistence sweep is the one sweep that cannot be narrowed, because the
write-back reads every field, so it is the *only* O(N) work a keystroke does.

**On a structural commit the floor is a tenth of the bill.** A single-row
`remove` costs 5.72 ms where a `toggle` costs 0.62 ms, and with the whole
persistence sweep deleted it still costs 4.95 ms. The ladder cannot resolve
the two segments there at all — `remove`'s `join` differences *negative* —
because a 5 ms term that drifts across remounts swamps a 0.2 ms one. What
that row establishes is only the bound, and the bound is what matters: this
axis is at most 10% of a structural commit.

**The two segments do not move together.** The last two rows carry nearly the
same payload — 223 KB in a thousand rows, 248 KB in ten thousand — and the
`storageSet` barely notices (0.2115 against 0.2335) while the `join` moves by
6.6× (0.0380 against 0.2508). That is not a floor with two halves. That is
two different functions that happened to cross.

### The shape: what each segment is a function of

Measured directly, outside the component, in the same Chromium. `setItem` of
one value, ns per call:

| bytes | 0 | 1 K | 10 K | 25 K | 100 K | 250 K | 500 K |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ns | 5033 | 6533 | 14133 | 37533 | 95333 | 217750 | 419750 |

which is **5.0 µs of fixed cost plus 0.85 ns per byte**, to within 8% at every
point, with no segment-count term at all — the host is handed a string and the
string is all it knows. The model predicts the ladder out of sample: 6.8 µs
against 7.2 measured at 100 rows, 24.4 against 21.0 at 1 000, 215.6 against
233.5 at 10 000.

`Array.join` at a fixed ~250 KB payload, varying the segment count: 10.5 µs at
10 segments, 20.5 at 100, 81.5 at 1 000, 210 at 10 000, 559 at 50 000. A 53×
spread for a 1.2× spread in bytes. Held at 10 000 segments and varying the
payload instead: 114.5 µs at 40 KB and 115.0 at 120 KB — the byte term does
not even register until the payload is several times the segment count. So the
`join` is **~18 ns per row plus ~0.1 ns per byte** (the per-row slope fitted
from the ladder; the isolated probe reads the same slope and a higher byte
term because its segments are unflattened).

Setting the two equal, the crossover is at about **23 bytes per row**. Toggle
Lab's row is 24.8 bytes. ADR-0087's "35% each" was that coincidence, and the
223-byte row confirms it from the other side: at ten times the density the
ratio is 5.6 : 1 in `storageSet`'s favour, exactly as the model says.

### The ABI exit, measured rather than argued

OQ1's second exit was a host that takes something other than one string. It
was built, three ways, each with a real host export beside the existing ones
and the emission rewritten to call it:

- **H1** `storageSetParts(key, parts, sep)` — the host joins the segment array
  the emission already builds. The `join` crosses the ABI.
- **H2a** `storageSetRows(key, rows, slot, sep)` — the host walks the caller's
  row table and ropes the payload with `+=`. The emission allocates no array,
  pushes nothing and joins nothing.
- **H2b** the same signature, the host building its own array and joining it.

Against the shipped emission, interleaved, three repetitions:

| candidate | 10k `toggle` | 10k `retype` | 1k `toggle` | 1k `toggle`, 223 B rows |
| --- | ---: | ---: | ---: | ---: |
| H1 | 0.99× | 1.01× | 1.01× | 1.01× |
| H2a | 1.06× | **1.10×** | 1.01× | 1.04× |
| H2b | 1.03× | 1.03× | 1.01× | 0.98× |

All twelve cells wrote a **byte-identical** payload to the shipped emission
(one distinct payload hash per cell across all four variants), so the numbers
price the same work.

H1 is the exit as OQ1 phrased it and it is worth **nothing** — 0.99× to 1.01×.
Moving the `join` across the ABI does not make it cheaper, because its cost is
N segments of pointer work and the host walks the same N. H2a is the maximal
version — no array, no push, one rope — and its best cell is 1.10×, on the one
commit kind where the sweep is the entire commit. What it buys is the push
loop the ladder prices at 6–8%, which is what is left once the `join` and the
`storageSet` are conceded, and it buys it at the price of putting the row
tuple's slot layout into the ABI — the layout ADR-0085 and ADR-0086 each
extended by one cell without an ABI event.

## Decision

**A persisted region's commit costs its payload in the host and its row count
in the join, and neither is an ABI question.** OQ1 closes: there is no exit.

> Per region-touching transaction, per persisted region it touched, a
> generated component pays about **5 µs** of fixed `storageSet` cost, about
> **0.85 ns per byte** of that region's table, and about **18 ns per row** to
> join it. The payload is the component's own bytes: the encoding adds one
> field separator between each pair of a row's declared fields and one row
> separator between rows, and nothing else — no per-row key, no position
> index, no length prefix, no version tag. Both terms are therefore the
> component's to control. Bytes per row set the
> host term; row count sets the join term; the two are equal at about
> twenty-three bytes per row and diverge in either direction from there.

**Why the `storageSet` term cannot move.** It is a function of bytes with no
row term, and every candidate host signature hands `localStorage` the same
bytes. A signature change moves *where* the string is assembled, never how
much of it crosses. The only way to write fewer bytes per commit is to write
part of the table — a chunked key space — and that is declined here on the
contract ADR-0087 sealed rather than on cost: `localStorage` has no multi-key
transaction, so a reader in another tab, which is a separate process reaching
the same origin, could observe one chunk of a commit and not the next. "A read
of the key by another tab observes what the last completed commit wrote" is
the sentence that would have to be withdrawn. The other O(1) store is
IndexedDB, whose write is asynchronous, which withdraws the same sentence
harder.

**Why the `join` term cannot move for an ABI's price.** It is N segments of
work wherever it runs; H1 measures that at 0.99×. Removing the emission's
array as well (H2a) is 1.10× at best and freezes the row tuple layout in the
ABI. The only shape that removes the N term is a joined string kept across
commits and patched in place, which is ADR-0087's B2: measured there at
1.52×/2.30×, declined for seven invalidation sites against identity keying's
two, two region record slots, and a wrong string in storage as the failure
mode. This round re-confirms the decline from the cost side — B2's ceiling is
the `join` share alone, because the `setItem` underneath it is untouched.

**What this changes in practice.** Nothing in any emitted module, and nothing
in the ABI. What it changes is the advice: a component that wants a cheaper
persisted region makes its rows *narrower* or *fewer*, and the emitter will
never do either for it, because a field's value is an opaque string it may not
shorten. The 5 µs fixed term is per touched region, not per transaction, so a
component persisting several regions (ADR-0078) pays it once for each region a
commit touched.

**Witness.** Two deterministic gates, because the cost model rests on two
structural facts and neither was pinned anywhere. Toggle Lab's asserts the
**no-framing-tax** identity: the stored length equals the sum of the escaped
field lengths, plus one separator between each pair of a row's four declared
fields, plus one row separator between rows — over rows whose labels carry all
three escaped characters, so the escape expansion is counted rather than
hidden — and that the whole origin holds exactly the one declared key. Mix Lab's asserts the two-region case:
exactly two keys for two persist items, each holding that region's whole
table. Broken three ways: a one-token-per-row position index in the payload
goes red on Toggle Lab's framing identity; a second chunk key beside the
declared one — which leaves the primary key's value untouched, so no existing
assertion in the suite sees it — goes red on Toggle Lab's key set alone; and
chunking the *second* region of the two-region component goes red on Mix Lab's
key set, naming the third key, while both declared values still read correct.

## Consequences

- No generated module changes. Every artifact in the repository is
  byte-identical, the benchmark size gate and every manifest included, and
  BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.
- `PersistSpec` and the language guide now carry the cost model beside
  ADR-0087's visibility contract, so "what does persisting a region cost"
  has an answer in the guide rather than in an ADR's appendix.
- ADR-0087 OQ1 is closed, and its "35% each" is superseded: the two segments
  are 37.7% and 40.5% of a `toggle` at ten thousand rows and are equal only
  because Toggle Lab's row is 24.8 bytes.
- ADR-0086 OQ1's method warning gets a second instance. A share is only valid
  against the emission and the *workload* it was measured on: ADR-0087's
  `retype` row read 5.7% "everything else" where this one reads 0.2%, because
  the drain wake that makes a keystroke touch nothing else was already in the
  emission and the ladder simply never varied the payload density to see it.

## Open questions

1. **A one-row structural change costs a full-table host reconcile.** At ten
   thousand rows a single-row `remove` is 5.72 ms and a single-row `append`
   5.94 ms against a `toggle`'s 0.62 ms, and with the entire persistence sweep
   removed they are still 4.95 and 4.56 ms where a `toggle` is 0.097 ms. The
   difference is `createKeyedRegion`'s `update`, which re-runs the generated
   per-row update callback on *every* retained row — about six DOM operations
   times N. The host has carried `removeAt` since ADR-0026, and the component
   backend has never emitted it: the structural path calls `update` with the
   whole table for a change ADR-0092's key-ordered table already located.
   This is now the largest unnarrowed cost in a generated commit, an order of
   magnitude above the floor this ADR closes, and it replaces OQ1.
2. **The `retype` commit is 99.8% persistence** (this ADR's first table). A
   keystroke in an editing row rewrites the whole table because `draft` is a
   persisted field. Whether a persisted region should carry a field that only
   an in-progress edit reads is a language question, not a codegen one, and
   the answer decides whether the floor is paid per keystroke or per commit.
3. **What the floor is now.** ADR-0087's other two open questions are closed
   elsewhere — the four predicate scans by ADR-0088, the key→position scan by
   ADR-0092 — so the whole of that line reduces to this. A *field-write*
   commit is priced to the last percent and has no unexplained remainder: at
   ten thousand rows a `toggle` is 78% store (37.7 + 40.5), 6% push loop and
   16% filter sweep, and a `retype` is 99.8% store. Both terms of the store
   are the payload's, and the payload is the component's. A *structural*
   commit is item 1 and is nine times larger. There is no third thing left in
   a persisted region's commit that has not been measured.
