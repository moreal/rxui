# ADR-0086: A filtered row carries its own displayed state

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0085 collapsed the persistence half of a drain commit and left the
sweep half standing. A `toggle` on a 10 000-row Toggle Lab region still
costs ~2.5 ms, and ADR-0082 OQ2 has named the suspect since: the ADR-0051
filter sweep writes `hidden` on **every** row through a `childAt` +
`setProperty` pair, however few rows the filter actually moved.

### The survey: split the commit, then measure

ADR-0085's clamp still applies — Chromium rounds `performance.now()` to
0.1 ms, which is larger than most of the segments — so the survey ablates
again: nine hand-edited copies of the *generated* Toggle Lab module, each
rung removing one more segment, driven with 400 single-row `toggle`
dispatches over one seeded region, whole loop timed and divided. Median of
five runs at 10 000 rows, filter `"all"`, ms per commit:

| variant | ms |
| --- | ---: |
| W0 the emitted commit | 2.489 |
| W1 without the `storageSet` call | 1.912 |
| W2 without the `join` | 1.719 |
| W3 without the persistence sweep | 1.418 |
| W4 without the sweep's `setProperty` | 0.896 |
| W5 without the sweep's `childAt` | 0.199 |
| W6 without the sweep's predicate | 0.199 |
| W7 without the four predicate scans | 0.083 |
| W8 with an O(1) key→position lookup | 0.054 |

Differencing the ladder gives the shares the goal asked for, and one of
them is a surprise:

| segment | ms | share |
| --- | ---: | ---: |
| filter sweep `childAt` | 0.697 | **28.0%** |
| `storageSet` | 0.577 | 23.2% |
| filter sweep `setProperty` | 0.522 | **21.0%** |
| persist cache check + push loop | 0.301 | 12.1% |
| persist `join` | 0.194 | 7.8% |
| the four predicate scans | 0.116 | 4.7% |
| key→position scan | 0.030 | 1.2% |
| filter predicate evaluation | 0.000 | 0.0% |
| transaction shell + `updateAt` | 0.054 | 2.2% |

The filter sweep's two DOM calls are **49%** of the commit, and the
navigation is the larger of the two: `childAt(parent, i)` is
`parent.childNodes[i]`, which re-crosses the binding for the child list on
every row, and at 70 ns per row it costs more than the property write it
navigates for. The four predicate scans the goal suspected are 4.7%, and
the predicate the sweep evaluates per row — the whole state-to-predicate
chain, on a row tuple, in JS — is not measurable at all. That last zero is
what decides the shape of the cache below.

### The two candidates, measured against each other

Two ways to spend the 49% were priced on the same harness, hand-applied to
the same generated module. Median of five runs, 10 000 rows, ms per commit:

| variant | `toggle` | |
| --- | ---: | ---: |
| the emitted sweep | 2.546 | |
| P1 a per-row `hidden` cache | 0.764 | **3.3×** |
| P2 `firstChild`/`nextSibling` instead of `childAt` | 2.365 | 1.08× |
| P3 both | 1.781 | 1.43× |

P2 is a real but small win, and it needs no ABI bump — `firstChild` and
`nextSibling` are already host exports. It is nevertheless rejected, and
P3 is the reason: **a sibling cursor must advance on every row**, which is
exactly the work the cache exists to skip. Making the navigation cheaper and
making it rare are not additive; they are alternatives, and the second is
worth four times the first. So the answer to "can the `childAt(container, i)`
walk be removed" is: it is removed for every row that did not move, which
is the only way it is worth removing.

## Decision

**A filtered region's row carries the `hidden` value the sweep last wrote
into its root, and the sweep writes only the rows whose value moved.**

> A region named by a `filter` item emits its rows as
> `[key, f_0, …, f_{n-1}, (serial)?, shown]`, where `serial` is ADR-0085's
> serialization cell (present only when the region is also persisted) and
> `shown` is the last `hidden` value written to that row's root, `null` for
> "never written". The tuple is born with `null` in both cells at every
> construction site — the component-event `append` and the mount hydration —
> so the array shape is fixed at construction. The sweep evaluates the sealed
> state-to-predicate table for **every** row, compares the result against
> that row's own cell, and only on a mismatch writes the cell, navigates
> `childAt(container, i)`, and writes the root's `hidden`. It reports the
> number of rows it wrote as one trace entry,
> `filter:{region}:written:{n}`; the shared DOM-write counter and its
> `dom:filter:{region}:write` entry take the ADR-0045
> evaluate-compare-write shape and fire only when that number is nonzero.

An unfiltered region's rows keep their exact previous shape, and no region
record slot moves for any region — the ADR-0085 argument carries over
verbatim, and Mix Lab's nine-slot `crew` beside its eight-slot `pins` is
untouched.

**The asymmetry with ADR-0085, which is the whole design.** ADR-0085's
`serial` is a function of the row's fields alone, so it can be *invalidated*:
two enumerable write sites null it and it is otherwise valid, and the sweep
skips the encoding itself. This cell cannot work that way. Its value is a
function of the row's fields **and** the filter state field, so a change to
the state field stales every row at once — there is no O(1) invalidation to
write, and an O(N) one would be the loop it was meant to replace. So this is
not a compute cache but a **write-elision** cache: the predicate is
recomputed for every row on every sweep, and the cell guards only the two
DOM calls. The survey is what makes that affordable — the predicate
evaluation measured 0.000 ms of a 2.489 ms commit — and it buys the property
that matters: **nothing anywhere invalidates this cell.** Not the row stage,
not the broadcast, not a filter flip. There are zero invalidation sites,
where ADR-0085 has two.

**Why identity keying still matters.** A position-keyed parallel array would
have to be rebuilt by `remove`, an ADR-0050 predicate removal and an
ADR-0053 guard hit. On the row tuple those three paths carry every
survivor's cell along *and* leave its DOM node attached and untouched, so
cell and node stay in agreement by construction — the sweep that follows the
rebuild writes zero. That is the property the witness measures directly.

**Why `null` at birth.** A freshly mounted row's DOM `hidden` is the default
`false`, which may be the wrong value. `null` differs from both booleans, so
a fresh row is always written exactly once by the first sweep that sees it —
including every row a hydration mounts.

**Why this is safe to leave uncorrected.** The sweep is the *only* writer of
a row root's `hidden`: row scope has no `hidden` selection at all
(`lowerRowAttrs` maps `class`, `value`, `checked`, `onChange` and `autoFocus`
and passes everything else through as a static attribute), so nothing can
move the property behind the cell's back. This is ADR-0081's one-writer
shape again, in row scope.

**What it costs when nothing is cached.** On a whole-table flip where every
row's selection moves, the sweep pays one extra compare and one extra store
per row on top of the two DOM calls it still makes. Measured on the shipped
emission with the hash write stubbed out, median of nine runs: 1000 rows
0.1353 → 0.1467 ms (**+8.4%**), 10 000 rows 2.23 → 1.93 ms — at 10k the
difference is inside the run-to-run noise band in either direction. The
worst case is bounded by a compare against two DOM crossings.

**Witness.** Twin Lab's browser gate walks the matrix on two rows per region
across three regions, one of them persisted. Each of the first two appends
writes exactly **one** row per region — the appended one, born `null`, while
its already-selected neighbour is never navigated to. A `mode` flip writes
exactly the one row per twin whose selection inverted, and leaves `solo`
(filtered on a different field) unwoken. A ✕ removal wakes the sweep on the
structural bit, evaluates the survivor and writes **zero** — the assertion
also pins that the survivor is the same DOM node and still carries the
`hidden` the pre-removal sweep gave it. A `right` row toggle shows the two
per-row caches side by side in one commit: `storage:right:encode:1` beside
`filter:right:written:1`, with the untouched row paying neither. And a hash
flip from `#/off` to `#/mixed` — two state literals whose arms select the
same predicate — wakes both twin sweeps, evaluates every row and writes
zero, with `tx[9]` unmoved: the state-change path recomputing everything and
still writing nothing, which is the asymmetry above made observable. The
artifact gates pin the emitted sweep in all three labs, Twin Lab's slot
asymmetry (`shown` at 3 for the unpersisted twins, at 4 behind `serial` for
the persisted one), Mix Lab's `crew` at slot 5, and the `null`s in every
fresh and hydrated row.

## Consequences

- A `toggle` on a 10 000-row filtered region costs 0.76 ms instead of
  2.47 ms (3.2×); with the filter on a selecting literal, 0.84 ms instead of
  2.49 ms (2.9×). At 1000 rows, 0.114 ms instead of 0.200 ms. A `retype`
  keystroke is unchanged at 0.59 ms — ADR-0084 already keeps it out of the
  sweep — so the extra tuple cell costs it nothing measurable.
- Three generated modules change: Toggle Lab, Twin Lab (all three regions)
  and Mix Lab (`crew`). Every component with no `filter` item is
  byte-identical, as is every unfiltered region inside the ones that changed.
- The benchmark artifacts and their size gate are untouched: the
  js-framework-benchmark backend is hand-written and filters nothing.
  BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.
- The trace gains one entry per sweep. `dom:filter:{region}:write` and
  `tx[9]` now fire only when the sweep wrote a row, which is the shape every
  attribute selection beside them already has.

## Open questions

1. **The `storageSet` is the new largest segment.** With the sweep's DOM
   pair gone from a cached commit, the survey's remaining ladder puts
   `storageSet` (0.577 ms at 10k) and the persistence push/join loop
   (0.495 ms) at the top. ADR-0085 OQ1 already noted that caching the
   *joined* string needs position information a row cannot carry; the
   `storageSet` itself is a host call whose cost is the browser's.
2. **The four predicate scans are 4.7% and unnarrowed.** ADR-0082 OQ1's
   general per-sweep read set landed in ADR-0083/0084, but two counts and
   two selections over the same field still each run their own O(N) scan
   over the same row table in the same commit. Sharing one scan across
   sweeps with an identical read set is a codegen question, not a contract
   one, and the survey prices the whole opportunity at 0.116 ms of 2.489.
3. **The key→position scan is O(N) per dispatch** (ADR-0084 OQ2, ADR-0085
   OQ2, unmoved). Priced here at 1.2% of an uncached 10k `toggle`, it is
   4% of the cached one — still the second-smallest segment, and still owed
   the whole append/remove/broadcast/hydrate invalidation matrix in
   exchange.
