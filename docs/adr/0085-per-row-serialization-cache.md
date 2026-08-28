# ADR-0085: A persisted row carries its own serialization

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0084 left the drain commit's floor named but unmeasured. A `retype`
keystroke on a 10 000-row region skips every count, every selection and the
filter sweep, and still costs 5.19 ms. Three candidates were left standing:
the dispatch's key→position linear scan, the `persist` serialization (which
reads every field and can therefore never narrow under any wake rule), and
the `storageSet` host call.

### The survey: split the commit, then measure

The clamp ADR-0084 already hit applies here too — Chromium rounds
`performance.now()` to 0.1 ms, which is larger than three of the four
segments — so per-segment timing inside one commit is not measurable at all.
The survey instead ablates: five hand-edited copies of the *generated* Toggle
Lab module, each removing one more segment, driven with 400 single-row
`retype` dispatches over one seeded region, whole loop timed and divided.
Median of five runs, ms per commit:

| variant | 10 000 rows | 1000 rows |
| --- | ---: | ---: |
| V0 the emitted commit | 4.944 | 0.4868 |
| V1 without the `storageSet` call | 4.669 | 0.4590 |
| V2 without the persistence sweep | 0.0480 | 0.0130 |
| V3 with an O(1) key→position lookup | 0.0025 | 0.0013 |
| V4 without the `updateAt` drain | 0.0008 | 0.0005 |

Differencing the ladder gives the shares:

| segment | 10 000 rows | share | 1000 rows | share |
| --- | ---: | ---: | ---: | ---: |
| serialization loop | 4.621 | **93.5%** | 0.4460 | 91.6% |
| `storageSet` | 0.2755 | 5.6% | 0.0278 | 5.7% |
| key→position scan | 0.0455 | 0.9% | 0.0117 | 2.4% |
| `updateAt` drain | 0.0017 | 0.03% | 0.0008 | 0.2% |
| transaction shell | 0.0008 | 0.02% | 0.0005 | 0.1% |

The two candidates the round was to choose between are 93.5% and 0.9%. The
key index is not worth an ADR: moving ADR-0027's monotone/lazy index into the
component region record would buy under 1% of the commit and would owe the
whole append/remove/broadcast/hydrate invalidation matrix in exchange. The
serialization is worth all of it.

Why it is so large is arithmetic, not mystery. One row of Toggle Lab's four
fields costs three `split`/`join` pairs per field — the throw-free escape of
ADR-0063 — so 10 000 rows is 240 000 intermediate arrays and as many strings,
built from scratch on every keystroke. `storageSet` moving the finished
300 KB is a twentieth of that.

### The record survey, and why no record slot moves

A cache slot was expected to be this line of ADRs' first *region record*
change, so every site computing a slot number was read first: the base five
(`handle, rows, nextKey, dirty, pending`), the ADR-0050 count pair at 5/6,
the ADR-0051 filter slot at `5 + (counts ? 2 : 0)`, and the ADR-0075
inventory at `5 + (counts ? 2 : 0) + (filter ? 1 : 0)`. Every one is computed
from that region's own feature set, which is exactly what Mix Lab's
nine-slot `crew` and eight-slot `pins` records pin: slot 7 means *container*
in one and *inventory* in the other.

That survey is what argues against the record. A record-slot cache would be
an array parallel to `rows`, and therefore keyed on **position** — so
`remove`, an ADR-0050 predicate removal and an ADR-0053 guard hit, all of
which rebuild the row array around unchanged tuples, would each have to
invalidate the whole cache despite writing no field at all.

Keying the cache on **row identity** instead deletes that entire matrix. The
cache is one cell on the row tuple, behind the declared fields:

```js
[key, f_0, …, f_{n-1}, serial]
```

A rebuild of the row array moves tuples without writing them, so every
survivor's cell stays valid by construction. Only a write to a field can
stale one, and ADR-0083 already enumerated the write paths exhaustively:
the ADR-0043 row stage's assignments and the ADR-0050/0061 broadcast. That is
the whole invalidation rule — two sites, one statement each.

It also means no record slot moves, and the Mix Lab asymmetry gate is
untouched: `crew` still ends at nine slots and `pins` at eight.

### What it is worth, measured

The same harness, with the row-cache emission hand-applied to the generated
module. Median of five runs of 400 dispatches, ms per commit:

| rows | event | before | after | |
| ---: | --- | ---: | ---: | ---: |
| 1000 | `retype` | 0.5062 | 0.0710 | **7.1×** |
| 10000 | `retype` | 5.109 | 0.5868 | **8.7×** |
| 1000 | `toggle` | 0.6165 | 0.1812 | 3.4× |
| 10000 | `toggle` | 6.875 | 2.0845 | 3.3× |

`toggle` is the control from ADR-0084: it is in the `done` wake class, so it
keeps paying four predicate scans and the filter sweep's N `childAt`/
`setProperty` pairs, and only its serialization collapses. What remains on
`retype` at 10k is the `join` over 10 000 cached strings, the `storageSet`,
and the key scan — the second and third of which the survey already priced
at 0.32 ms together.

## Decision

**A persisted region's row carries its own serialization, and only a write to
one of its fields discards it.**

> A region named by a `persist` item emits its rows as
> `[key, f_0, …, f_{n-1}, serial]`, where `serial` is `null` for "not
> encoded" and otherwise the row's ADR-0063 serialization. The tuple is born
> with `null` at every construction site — the component-event `append` and
> the mount hydration — so the array shape is fixed at construction. Every
> path that assigns a row field writes `row[n + 1] = null` after its
> assignments: the ADR-0043 row stage (once, for the drained row) and the
> ADR-0050/0061 broadcast (once per row, inside its own loop). Nothing else
> writes a field. The write-back then walks the row table, encodes exactly
> the rows whose cell is `null`, and joins the cells.

An unpersisted region's rows keep their exact previous shape, and no region
record slot moves for any region.

**Why the row and not the record.** A parallel array in the record is keyed
on position, so the three paths that rebuild the row array without writing a
field — `remove`, the ADR-0050 predicate removal, the ADR-0053 guard hit —
would each have to invalidate everything. Keying on identity makes those
three paths *provably* cache-preserving, which is the property the witness
below measures directly.

**Why the write-back keeps the region-wide flag.** ADR-0083's trap is
unmoved: the write-back reads every field, so no wake rule narrows it, and it
still runs on every region-touching transaction. What ADR-0085 changes is not
*when* it runs but what it costs when it does.

**Why a trace and not a counter.** The cache is only observable through how
many rows the sweep had to encode. One trace entry per encoded row would be
O(N) entries on a rebuild; a new `tx` counter would be a host change and an
ABI bump. The sweep instead pushes one entry per write-back carrying the
count — `storage:{region}:encode:{n}` — which is O(1) and needs neither. It
is the first trace whose text is computed at commit time; every other one
remains a static string.

**Witness.** Toggle Lab's browser gate walks the whole invalidation matrix on
three rows: mount with no stored value encodes nothing; each of three appends
encodes exactly one row; a `toggle`, an `edit`, each `retype` keystroke and
the Enter commit each encode exactly one however many rows the region holds;
a filter change encodes nothing because it never touches the region; the ✕
removal and `clearCompleted` encode **zero** — the survivors keep their
cells; `completeAll` and the ADR-0061 payload broadcast encode every row; and
a hydration encodes the whole table, which is what normalizes a hand-edited
stored value exactly as ADR-0063 promised. Every step also asserts the stored
string byte-for-byte, so a stale cell would be caught as a wrong value and
not merely as a wrong count. The artifact gates pin the sweep, both stale
sites, the `null` in the fresh row, the kept-filter that stales nothing, Twin
Lab's one persisted region beside two unpersisted ones with unchanged row
shapes, and Mix Lab's two independent caches beside its unchanged nine/eight
record asymmetry.

## Consequences

- A `retype` keystroke on a 10 000-row persisted region costs 0.59 ms
  instead of 5.11 ms; a `toggle` costs 2.08 ms instead of 6.88 ms.
- Three generated modules change: Toggle Lab, Twin Lab (its one persisted
  region), and Mix Lab (both). Every other module — every component with no
  `persist` item — is byte-identical, as is every unpersisted region inside
  the three that changed.
- The benchmark artifacts and their size gate are untouched: the
  js-framework-benchmark backend is hand-written and persists nothing.
  BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.
- The trace gains one entry per write-back. Tests that count
  `storage:{region}:write` are unaffected; tests that assert the trace
  contains a given entry are unaffected.

## Open questions

1. **The `join` is the new floor.** A drain commit on a persisted region is
   now one key scan, one encode, an N-element push loop, one `join` and one
   `storageSet` — 0.59 ms at 10k rows, of which the `storageSet` is 0.28.
   Caching the *joined* string would need position information the row cannot
   carry, and would put the region record change back on the table.
2. **The key→position scan is O(N) per dispatch** (ADR-0084 OQ2, priced here
   at 0.9% of a 10k-row commit and unmoved). It is now a *larger* share of a
   smaller commit — 7.8% — but still the second-smallest segment.
3. **The sweep still has no per-row cache** (ADR-0082 OQ2, unmoved). A sweep
   that must run rewrites `hidden` on every row rather than the rows whose
   selection changed. This is what `toggle` still pays and `retype` no longer
   does.
