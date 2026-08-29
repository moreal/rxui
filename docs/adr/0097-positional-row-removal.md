# ADR-0097: A sealed single-row removal removes one row

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0096 closed the persistence floor and, in closing it, wrote down the thing
that dwarfs it:

> At ten thousand rows a single-row `remove` is 5.72 ms and a single-row
> `append` 5.94 ms against a `toggle`'s 0.62 ms […] The difference is
> `createKeyedRegion`'s `update`, which re-runs the generated per-row update
> callback on *every* retained row […] The host has carried `removeAt` since
> ADR-0026, and the component backend has never emitted it.

That is this ADR's subject. It is not a new observation about the host — the
host's contract has said since ABI 13 that "a backend uses them when it can
show that the exchange or removal changes no other row's payload" — it is that
the component backend never checked whether it could show that, and it always
could.

### Where the time is

Measured on Toggle Lab, Chromium, rows seeded through the ADR-0063 hydration
path, five to nine repetitions per cell, median of medians, with the region
host's `update` split into its four internal phases by `performance.now()`
under cross-origin isolation. Milliseconds, one commit:

| rows | action | commit | of which `update` | key validation | **updateItem loop** | dispose | placeInOrder |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 | `remove` @front | 5.495 | 4.540 | 0.250 | **4.250** | 0.030 | 0.025 |
| 10 000 | `remove` @middle | 5.620 | 4.760 | 0.140 | **4.555** | 0.030 | 0.025 |
| 10 000 | `remove` @back | 5.820 | 4.870 | 0.070 | **4.740** | 0.040 | 0.020 |
| 10 000 | `commit` guard hit | 6.620 | 5.090 | 0.240 | **4.780** | 0.035 | 0.020 |
| 10 000 | `keys` guard hit | 9.110 | 8.425 | 0.150 | **7.045** | 1.005 | 0.015 |
| 10 000 | `removeIf` | 6.080 | 4.735 | 0.185 | **4.485** | 0.030 | 0.020 |
| 10 000 | `append` | 6.985 | 4.520 | 0.130 | **4.350** | 0.025 | 0.020 |
| 10 000 | `toggle` | 0.785 | — | — | — | — | — |
| 1 000 | `remove` @middle | 0.555 | 0.450 | 0.020 | **0.425** | 0.005 | 0.005 |
| 100 | `remove` @middle | 0.070 | 0.045 | 0.005 | **0.035** | 0.005 | 0.000 |

Three readings.

**The loop is `updateItem`, and nothing else is close.** It is 93–97% of
`update` and 75–81% of the whole commit at ten thousand rows, linear in the
row count at about 0.45 µs per retained row — the six DOM operations Toggle
Lab's generated row-update callback performs. The other three phases together
are 0.1–0.3 ms. `placeInOrder` in particular is *already* free for a removal:
its prefix and suffix scans meet immediately, so it moves nothing and returns
in 20 µs over ten thousand rows.

**Position matters only to key validation, and only a little.** Removing the
front row makes every later key miss the "this key was at this position last
time" fast path, so the loop builds and consults the key index: 0.250 ms
against 0.070 ms at the back. It is 5% of the commit either way.

**`toggle` is the control, and it is a factor of seven cheaper** — because
ADR-0043 already gave it `updateAt`. The whole axis is that removals never got
the same treatment.

The `keys` row is higher than the others throughout because the row being
removed holds the focused editor (ADR-0048), so its detach costs a focus
fix-up; the shape is unchanged.

### What ADR-0096's note left open

Two things the note did not separate.

`removeIf` — a component-event predicate removal, `remove items (done ==
"true")` — is in the table above and looks identical. It is not the same case:
its removal count is data-dependent, from one row to the whole table, and when
it clears *everything* the reconcile takes `rebuild`'s bulk path (`textContent
= ""` on an owned parent), which no sequence of per-row removals can match.

`append` has no host counterpart at all. `update` is the only entry point that
mounts.

## Decision

**A sealed single-row removal queues the position it removed, and the commit
sweep drains it through the region handle's `removeAt`.** Regions keep the
reconcile for everything else.

### The layer

A removal is already a two-step: the dispatch splices the row table, the
commit sweep reconciles the DOM. Only the second step changes.

The dispatch's removal sequence (`rowRemoveStmts`, shared by the sealed
`remove` action and every ADR-0053 guard hit) stops raising the dirty bit and
instead pushes `[position, key]` onto a new region-record slot. ADR-0092
already resolved that position — the `remove` action by its own key search, a
guard hit by the search its stage stands on — so no search is added and none
is repeated.

The commit sweep drains the queue with `removeAt(position, key, rowContext)`,
in the order the table was spliced, immediately **before** the reconcile.
Before, not instead of: a transaction that also appends or broadcasts still
reconciles, over a table and a host that already agree about the removals.
Before the reconcile rather than after, because the ADR-0051 filter sweep
navigates `childAt(container, i)` by row-table position and only after the
drain do the two agree again.

`removeAt` gets `rowContext`, so an ADR-0075 child-composing region's row
dispose callback splices the live inventory exactly as the reconcile made it.

### The slot

The drops queue is the region record's **last** slot, behind the ADR-0075
inventory, present exactly when the region declares a removing action. Every
slot index ADR-0050, ADR-0051 and ADR-0075 sealed stays where it was, which is
why three of the four labs' region records are the only line of their
artifacts that moved.

### The invalidation obligations, per row

**The wake flags.** A removal is a structural change however it is recorded,
so every flag that read the dirty bit as "the row set moved" now reads the
queue beside it: `region_touched_{r}`, `region_structural_{r}`, and each
ADR-0084 drain class's flag. They are read where they always were — before the
drain and the reconcile consume their signals. This is the obligation that
does *not* announce itself: forget it and every row renders correctly while the
counts, the emptiness sweeps, the filter table and the write-back all sleep
through the removal.

**The pending `updateAt` queue.** The splice shifts every later position down
by one, so a position this same transaction already queued for the ADR-0043
drain would no longer name the row it was read from. Exactly one action branch
runs per dispatch and every commit empties that queue, so it is provably empty
at a removal today. Rather than rest that on a whole-language invariant, the
emission discharges it as code: a removal that finds the pending queue
non-empty raises the dirty bit instead, and the reconcile — which re-renders
every retained row and drops the queue — is correct whatever the mixture was.
The branch costs one length comparison and is emitted only for regions that
have an update action at all.

**The position itself.** `removeAt` validates that the key at the position it
is given is the key it was given (`LRX-REGION-003`, before any callback or DOM
mutation), so the queued position is re-checked against the host's own entries
at drain time rather than trusted.

**The key-miss branch.** The sealed `remove` action's search can return `-1`.
It used to raise the dirty bit anyway; it now queues nothing, because there is
no position to queue. A key the table does not hold changed nothing, so waking
every sweep for it was always wrong.

### What is *not* paid, and why

**`removeIf`, declined on its row count.** Its removals are unbounded, and the
reconcile's `retained === 0` path clears an owned parent in bulk where a
per-row drain would pay N detaches on a shrinking array. Choosing between them
needs a threshold in generated code, and this round has no measurement that
says where it is. It keeps the reconcile, and Toggle Lab now witnesses the
contrast in one test: the ✕ button moves the host's update counter by zero,
Clear-completed still moves it by the survivor count.

**`append`, declined for want of a host export.** Nothing in the handle mounts
a row except `update`. Adding one is an ABI event, and this round did not
build it; the price is recorded in OQ1 rather than guessed.

### What does not move

No host change: `removeAt` has been on the keyed handle since ADR-0026 and is
already classified `removeAt: {}` in the ADR-0094 `LRX-HOST-001` surface —
this is a new *caller*, not a new export, so H3 and H4 stay green and
`runtimeAbi` stays 17. No manifest field and no feature stamp changes. The
ADR-0093 row-order audit is untouched: the drops queue is not a row table, the
splice it queues for is still the single-row `splice` R3 allows, and R5's
kept-filter — the `removeIf` path — is exactly what this ADR declined to
touch.

## Consequences

- Paired A/B against the pre-change emission, both variants in one browser
  process with the leader alternated across seven passes, medians of
  per-cell medians. Removals: **2.9×–4.3×** faster at 1 000 rows and 10 000
  rows (`remove` 3.2–4.1×, guard hits 2.9–4.3×). Every untouched path stays
  within noise: `removeIf` 0.98–1.09×, `append` 0.97–1.00×, `toggle`
  0.95–1.00×. Absolute times on the same instrumented harness as the table
  above, ten thousand rows: `remove` 5.50–5.82 → 0.72–1.14 ms, the `commit`
  guard hit 5.38–7.95 → 0.74–0.98 ms, the `keys` guard hit 9.11–10.19 →
  1.46–1.84 ms. The reconcile is not entered at all — the host's `update` runs
  zero times — so what remains is the counts, the filter sweep and the
  ADR-0063 write-back.
- The region instrumentation says it exactly. Five single-row removals over a
  ten-thousand-row region moved `[mounts, updates, moves, disposals]` by
  `[0, 49985, 0, 5]` and now move it by `[0, 0, 0, 5]`.
- Exactly five generated modules change, and they are exactly the five whose
  components declare a removing row action: `BranchLab.mjs`, `MixLab.mjs`,
  `NestLab.mjs`, `ToggleLab.mjs` and `TwinLab.mjs` gain the drops slot in
  their region records, the drain in each commit sweep, and the queue push at
  each removal site. Regenerating every lab on both sides of the change and
  comparing file by file, every other generated file is byte-identical:
  Counter, Diamond, Echo, Filter, Tabs, Temperature, Validated Form, TodoMVC,
  Notes, Issue Browser, Data Grid and the docs lab, every bundled host file,
  and **every manifest including the five that changed** — no field of the
  manifest moves, `runtimeAbi` included. The js-framework-benchmark size gate
  and baseline are untouched: that backend is hand-written and has emitted
  `removeAt` since ADR-0026.
- The ADR-0053 and ADR-0054 guard-hit witnesses change what they assert: a
  guard hit is now one disposal and *no* survivor update. That is the axis,
  read off the host's own counters.

## Open questions

1. **`append` still reconciles the whole table.** At ten thousand rows a
   single-row append is 6.99 ms, of which 4.52 ms is `update` and 4.35 ms is
   the `updateItem` loop over the ten thousand rows that did not change — the
   same shape this ADR just deleted from the removal side, and now the largest
   remaining one. The handle has no counterpart: mounting a row is `update`'s
   alone. An `appendAt(item, context)` (or an `insertAt`) would be a new host
   export, hence an ABI bump and an ADR-0094 surface entry declaring which of
   its arguments are caller arrays — the row it is handed is one, and H2
   already says rows cross unfrozen. Whether the emission's `push` onto
   `regions[r][1]` and the host's mount should stay two steps or become one is
   the design question that bump would settle.
2. **`removeIf`'s threshold is unmeasured.** A predicate removal that takes one
   row out of ten thousand pays 6.08 ms where the drain would pay about one;
   one that takes all ten thousand would pay N detaches where the reconcile
   pays one `textContent` assignment. The emission could choose at run time on
   the queue's length against the table's, but the crossover is a number this
   round did not measure, and a constant in generated code wants one.
