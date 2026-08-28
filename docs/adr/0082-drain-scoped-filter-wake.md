# ADR-0082: A key is a namespace, a touch is two events

- Status: Accepted
- Date: 2026-08-29

## Context

Two loose ends were left over from the persistence and filter contracts.

**The unwitnessed persist branch.** `validatePersists` has four rejections
and three had compile-fail witnesses (`PersistUnknownRegion`,
`PersistDuplicateKey`, `PersistRegionTwice`). The fourth — `persist r := ""`
— had none, and nothing recorded whether an empty key is a principled
rejection or a leftover shape check.

**ADR-0081 OQ2.** A region's touched flag is
`regions[i][3] || regions[i][4]["length"] !== 0` — structurally dirty, or
holding pending row positions — and the filter sweep is guarded on
`region_touched_{i} || changed[field]`. A `row` update that writes a field
no filter arm reads therefore wakes a sweep that walks every row and writes
each row root's `hidden` with the value already there. The sweep is
`setProperty` N times for N rows; whether narrowing it is worth the
analysis was unexamined.

### The empty key, observed

`storageGet("")`/`storageSet("")` were run in Chromium against the
generated module with its persist key rewritten to `""`:

```
setItem("", v) throws:      no
getItem(""):                the stored value
localStorage.length:        1
localStorage.key(0):        ""
Object.keys(localStorage):  [""]
"" in localStorage:         true
```

The empty string is a *legal, enumerable* localStorage key. The generated
module works perfectly under it: seeds write, mount hydrates. So the empty
key is not a runtime error to be surfaced — it is a silent one, and three
observations say what kind:

1. **It is the one key value different components collide on by accident.**
   `validatePersists` seals one writer per key *within* a component; the
   origin-wide key space is not visible to the compiler. Every unnamed
   writer picks `""`.
2. **Hydration is fail-closed only against malformed arity, not against a
   foreign writer.** Mounting against a foreign `""` value with this
   region's field arity hydrates the foreign rows as its own and
   re-persists them:

   ```
   hydrate from "STOLEN,true"  → rows ["STOLEN"], stored "STOLEN,true"
   hydrate from "a,b,c"        → rows [],         value left untouched
   ```

   The arity check is the only guard there is, and it passes for anything
   shaped like a row. Fail-closed ends at the *shape*, so the key has to
   carry the identity.
3. **It is not a name.** In devtools it is an empty row; `storageGet("")`
   cannot be told apart from "no key configured".

### The drain-only sweep, measured

The generated Twin Lab module was hand-edited so the persisted region's row
event writes `label` (which no arm reads) instead of `flag` (which every arm
reads), and a second copy narrowed the sweep guard to the structural flag.
Both were mounted with N rows hydrated from storage in one transaction, then
driven with 450 single-row writes each; median ms per commit in Chromium:

| rows | filter + persist | narrowed | filter only | narrowed |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 0.054 | 0.040 | 0.020 | 0.008 |
| 1000 | 0.358 | 0.260 | 0.100 | 0.010 |
| 5000 | 2.008 | 1.480 | 0.472 | 0.026 |
| 10000 | 4.098 | 2.938 | 1.004 | 0.046 |

Two readings, and they disagree:

- Beside a **persistence** sweep the narrowing is a 27% cut of something
  that stays O(N) either way: the write-back re-serializes every row on
  every touching transaction, and the dispatch's key→position scan is O(N)
  before that.
- With the filter sweep **alone** it is the whole cost: 1.004 ms → 0.046 ms
  at 10k rows, because what remains is the pure-JS key scan and one
  `updateAt`. The sweep is ~0.1 µs per row, all of it DOM.

The row write cannot change the selection in either column. The second is
20× and it is the shape a filtered, unpersisted list has.

## Decision

**An empty storage key stays rejected, on the ground that a key is a
namespace and not a label; and the filter sweep's touch wake narrows to the
structural flag whenever no drain path writes a field the filter reads.**

**The key.** `LRX-TYPE-118`'s nonempty rule is now stated as what the
browser showed: `""` is a working key, so the rejection buys nothing at
runtime and everything at the origin. One writer per key is the invariant
the other three branches enforce inside a component, and the empty key is
the one value that breaks it *between* components, where no validator can
look. Hydration cannot backstop it — a same-arity foreign value is
indistinguishable from this region's own rows — so the check has to sit
where the key is written. Fixture `PersistEmptyKey`, pinned on its own
message; all four branches are now witnessed.

**The sweep.** A region's touched flag conflates two events: *the row set
changed* and *some row's fields changed*. Only the first can change which
rows a table selects — unless the second writes a field the arms read. So:

> A region's filter sweep is guarded on `region_structural_{i} ||
> changed[field]` — the dirty bit read at the same point in the commit, before
> the reconcile clears it — exactly when the region has a drain path and no
> declared `row` update stage writes a field the filter's arm predicates read.
> Otherwise it keeps `region_touched_{i} || changed[field]`.

The rule is total, and it is decided from the spec alone:

- The pending slot is written in exactly one place — the row stage's
  queue-the-position step. `remove`, an ADR-0053 guard hit, an
  ADR-0050 broadcast, a predicate removal, an append, and hydration all raise
  the **dirty** flag instead, so every path that changes the row set or its
  order is on the structural side by construction.
- The drain re-runs `updateItem` on the retained handle. Row roots are not
  remounted and do not move, so the `hidden` the last sweep wrote by
  position is still on the row the sweep would rewrite.
- The written set is the assignment targets of every declared stage, the
  ADR-0052 key arms included; the read set is every arm predicate subject's
  `fieldRefs`, so a composed or trimmed subject counts every field it
  projects.

**Where it is invisible.** A region with *no* drain path has a provably
empty pending slot, so `touched` and `structural` are the same predicate
and the uniform flag is kept — narrowing there would be a second name for
one value. Every generated artifact in the tree is byte-identical under this
change; the narrowing shows up only on the new surface below.

**Witness.** Twin Lab's `left` gains `row left mark := set label (label ++
"*")`: a drain path on a filtered region that writes a field the table does
not read. The emission puts both flags side by side in one region —

```js
    const region_touched_0 = regions[0][3] || regions[0][4]["length"] !== 0;
    const region_structural_0 = regions[0][3];
```

— the count sweep reading the first, the filter sweep the second, while
`right` (whose drain writes its own subject) keeps the touched flag and
`solo` (no drain path) grows no second flag at all. The browser gate marks a
displayed row and a *hidden* one: one `region:left:updateAt` each, zero
`filter:left:evaluated`, `tx[8]` unmoved, both rows' `hidden` byte-equal to
what the last sweep left — and an append afterwards still wakes the sweep
once and re-selects every row, marked labels included.

## Consequences

- The persistence contract now reads as one sentence: one writer per key,
  and the key names the writer. The nonempty rule is part of that sentence
  rather than a shape check, and the ADR carries the browser observation
  that makes it necessary.
- The filter contract gains a *why* for its guard: the flag it reads is
  chosen per region from the declared row events, so a reader who finds
  `region_structural_0` beside `region_touched_1` in one module can derive
  which is which from the surface.
- The count, emptiness, and persistence sweeps beside it still wake on the
  touched flag. That is the next axis, not an oversight — see the open
  question; the witness asserts the count sweep *does* re-evaluate on the
  same drain, so the boundary is pinned rather than assumed.
- No host change and no validator change: `runtimeAbi` stays 17, the
  benchmark artifacts and their size gate are untouched, and the only
  generated module that moves is Twin Lab's.

## Open questions

1. **The sibling sweeps.** The same conflation is in the count sweep
   (ADR-0050), the emptiness selections (ADR-0058/0059/0060), and the
   persistence write-back (ADR-0063), and each has a *different* read set:
   a total count and a total emptiness subject read only `rows.length`, so
   *no* drain can move them; a predicate count reads its predicate's field;
   the write-back reads every field, so it can never narrow. Doing all four
   from one per-sweep read set is the general shape of this decision, and
   unlike the filter case it would change existing artifacts and their
   evaluation counters (Mix Lab and Toggle Lab both re-evaluate a total
   count on every row toggle).
2. **The sweep has no per-row cache.** Even a sweep that must run rewrites
   `hidden` on every row rather than the rows whose selection changed — the
   measured ~0.1 µs per row is paid in full on every filter flip. A per-row
   cache would cost a region-record slot; nothing needs it yet.
