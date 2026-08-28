# ADR-0084: A drain wakes only the sweeps the row event it ran can move

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0083 made the wake flag a function of each sweep's read set and left
one open question standing: the *write* set is still the union over **all**
of a region's row events. Toggle Lab's `retype` writes `draft` alone, but
some other row event writes `done`, so a keystroke inside a row editor still
runs both `done` predicate counts, both `done` predicate selections, and the
O(N) filter sweep beside them.

The round began from the premise that the emission already knows better:
the commit body is inlined per transaction function, so a function's own
row stages are known where its flag constants are emitted. Parameterizing
`regionDrainWrites` by "the stages this function runs" would then make the
flag set differ per function.

### The survey: per function is worth exactly nothing

That premise is wrong about the shape of the emission, and the survey is
the finding. `listenDelegatedCells` resolves a row action by structure and
calls **one** dispatch function per region — Toggle Lab's whole row
vocabulary (`toggle`, `edit`, `retype`, `commit`, `keys`) lives in
`$lrx_region_0_dispatch` as five `action === "…"` branches over one shared
commit. So a per-function write set splits the sixteen transaction
functions of that module into exactly two cases:

| transaction function | drain write set |
| --- | --- |
| `$lrx_region_{i}_dispatch` | the union over that region's row events — **ADR-0083 unchanged** |
| component events, typed events, ADR-0056 key arms, ADR-0063 route arms, hydration | ∅ for every region |

and the second case buys nothing. A function with no drain path has a
provably empty pending slot — every commit clears it, and the array is
pushed in exactly one place, the guard-miss arm of a row stage inside the
dispatch — so `region_touched_{i}` and `region_structural_{i}` are the same
value there. Narrowing them would delete a dead `|| pending.length !== 0`
disjunct and nothing else: no sweep changes its behaviour, no evaluation
counter moves. The rest of ADR-0083's classification re-verifies unchanged:
`append` pushes and sets the dirty bit, an event `remove` and an ADR-0050
predicate removal rebuild the row array and set it, an ADR-0053 guard *hit*
takes the remove branch and sets it, an ADR-0050/0061 broadcast writes every
row and sets it, hydration pushes the decoded rows and sets it. All of them
are on the structural side; only the row stages queue.

The axis that is worth something is therefore one level below the function:
the row **event**.

### The action argument is already the witness

Inside the dispatch — and only there — the row event that ran is a value:
the `action` parameter. Exactly one action branch executes per call, so for
a set `S` of row events

```js
regions[i][3] || regions[i][4]["length"] !== 0 && (action === "a" || …)
```

is not an approximation of "a drain that these sweeps could see happened".
It *is* that predicate: the pending array is non-empty only if the branch
that ran queued a position, and `action` names which branch that was. A key
that matches no ADR-0052 arm, or a row key that no row carries, queues
nothing and the conjunction is false on the pending half.

Nothing else changes. No region-record slot, no accumulator, no statement
added to any write path — the flag is one more `const` in the commit
prologue, exactly where ADR-0082's two flags already sit.

Grouping is per event and not per stage: an ADR-0052 key selection's arms
share one action string, so their write sets union under it. Toggle Lab's
`keys` writes `{label, draft, mode}` (Enter) and `{draft, mode}` (Escape),
and no sweep in the tree distinguishes them.

### The classes, from the surface

Toggle Lab's `items` region, fields `(label, draft, done, mode)`:

| row event | writes | | sweep | reads |
| --- | --- | --- | --- | --- |
| `toggle` | `done` | | `{count items (done == "false")}` ×2 | `done` |
| `edit` | `mode` | | `hidden={count items (done == "true") == 0}` | `done` |
| `retype` | `draft` | | `checked={count items (done == "false") == 0}` | `done` |
| `commit` | `label, draft, mode` | | `filter items by filter` | `done` |
| `keys` | `label, draft, mode` | | `hidden={count items (mode == "edit") == 0}` | `mode` |
| | | | `{count items}`, three `== 0` emptiness subjects | length |
| | | | `persist items` | every field |

Two classes fall out — `{toggle}` and `{edit, commit, keys}` — beside the
structural bit for the row total and the emptiness subjects and the
region-wide touched flag for the persistence write-back:

```js
    const region_touched_0 = regions[0][3] || regions[0][4]["length"] !== 0;
    const region_structural_0 = regions[0][3];
    const region_drain_0_0 = regions[0][3] || regions[0][4]["length"] !== 0 && action === "toggle";
    const region_drain_0_1 = regions[0][3] || regions[0][4]["length"] !== 0 && (action === "edit" || action === "commit" || action === "keys");
```

`retype` is in neither class. A keystroke inside a row editor drains one
retained row and re-serializes the table, and re-evaluates nothing else at
all.

Every other region in the tree is unchanged, and provably so: a class is
emitted only where the events that can move a sweep are a *proper*, nonempty
subset of the region's drain paths. Twin Lab's `left` (one drain event,
writing a field no sweep reads) stays on the structural flag alone, `right`
and `solo` are untouched, and Mix Lab's `crew` has one drain event so every
sweep it can move is all of them. Both modules are byte-identical.

### What it is worth, measured

The trap ADR-0083 named applies here too: the persistence write-back reads
every field, so it can never narrow, and it is O(N) on every keystroke.
Two hand-edited copies of the *generated* Toggle Lab module differing only
in which flag the narrowed blocks read, seeded with N rows and driven with
400 (200 at 10k) single-row dispatches; ms per commit in Chromium, median
of five runs:

| rows | `retype`: region-wide | per event | `toggle`: region-wide | per event |
| ---: | ---: | ---: | ---: | ---: |
| 100 | 0.0752 | 0.0623 | 0.0745 | 0.0725 |
| 1000 | 0.619 | 0.516 | 0.658 | 0.655 |
| 5000 | 3.416 | 2.556 | 3.406 | 3.381 |
| 10000 | 7.743 | 5.188 | 7.728 | 7.563 |

`toggle` is the control: it is in the `done` class, so it wakes everything
it woke before and the two columns agree inside the noise. `retype` drops
17% at 100 and 1000 rows and 33% at 10k — what it stops paying is four
predicate scans and the filter sweep's N `childAt`/`setProperty` pairs;
what it keeps paying is the key→position scan and the serialization, both
O(N) and both untouched by any wake rule. The dividend grows with N because
the part that was removed is the part that scaled with the *number of
sweeps*, not with the row.

## Decision

**A region's sweep wakes on a drain only when the row event that ran can
write a field the sweep reads.**

> Inside a region's own dispatch function a sweep is guarded on
> `region_drain_{i}_{c}` — `regions[i][3] || pending.length !== 0 && action
> ∈ S_c` — where `S_c` is the set of that region's row events whose update
> stage assigns a field the sweep's read set contains, whenever `S_c` is a
> proper nonempty subset of the region's drain paths. `S_c` empty is
> ADR-0082's structural bit; `S_c` the whole set is the region-wide touched
> flag. Every other transaction function keeps ADR-0083's region-wide
> flags. Sweeps sharing an `S_c` share a flag, and adjacent sweeps sharing a
> flag share a block.

The classes are numbered in sweep emission order after de-duplication, so a
reader can derive `region_drain_{i}_{c}` from the declared row events and
the sweep list without consulting the compiler.

**Why the other functions keep the wider flag.** The narrowing there would
be pure dead-code removal — but it would also be the only place in the
emission where correctness depended on transactions never nesting. The
shell's `tx[0]` depth counter contemplates a nested transaction, whose
commit runs in the *outer* function, and an outer function's `action` cannot
name what an inner dispatch queued. Keeping the pending disjunct outside
the dispatch means the rule stays sound under a nesting the generator does
not currently produce, at a cost of one array-length comparison against a
provably empty array.

**Why per event and not per stage.** The dispatch is handed an action, not
a stage. Splitting an ADR-0052 key selection's arms would need a second
discriminant (`eventKey`) in the guard, and no sweep in the tree reads a
field that only one arm writes.

**Witness.** Toggle Lab gains an editing hint —
`hidden={count items (mode == "edit") == 0}` — so `items` carries a sweep
whose class is a *different* proper subset from the `done` sweeps', and the
emitted disjunction is more than one action long. The browser gate walks
all four cases on one mounted lab: `edit` wakes the hint and neither `done`
count; a keystroke wakes nothing at all — every count, every selection, the
filter sweep, and both `tx[5]` and `tx[8]` unmoved, while the drain and the
storage write both happen exactly once, and both row roots keep the
`hidden` byte the last sweep wrote; Escape wakes the hint again; `toggle`
is the mirror image, waking both `done` counts, both `done` selections and
the filter table but not the hint; and an `Add` afterwards wakes all of
them, whichever flag they read. The artifact gate pins both class constants
with their action tests, the hint's block behind `region_drain_0_1`, the
filter sweep behind `region_drain_0_0`, and the persistence write-back
still behind `region_touched_0`.

## Consequences

- The counters keep the meaning ADR-0083 gave them and sharpen it:
  `count:{r}:{i}:evaluated` now says *the row event that just ran could have
  moved this value*.
- One generated module changes: Toggle Lab's, by +100 bytes for the rule
  (two `const`s in the one function that gets them) and +9922 for the
  editing hint, whose sweep block repeats in all sixteen transaction
  functions — a lab edit, not the rule's cost. Twin Lab and Mix Lab are
  byte-identical, as is every drain-free region in the tree.
- The benchmark artifacts and their size gate are untouched — the
  js-framework-benchmark backend is hand-written and never reaches this
  path — and BENCHMARK.md stands unre-measured.
- No host change and no validator change: `runtimeAbi` stays 17.

## Open questions

1. **Persistence is the floor.** A `retype` keystroke is now one key scan
   plus one full re-serialization, and both are O(N). Narrowing the
   write-back would need a per-row serialization cache keyed on the fields
   that changed — a region-record change, and the first one this line of
   ADRs would need.
2. **The key→position scan is O(N) per dispatch** (unmoved since ADR-0043).
   The row array is not indexed by key inside the component backend, unlike
   the ADR-0027 index the benchmark backend carries.
3. **The sweep still has no per-row cache** (ADR-0082 OQ2, unmoved). A sweep
   that must run rewrites `hidden` on every row rather than the rows whose
   selection changed.
