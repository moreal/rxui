# ADR-0098: A component-event append mounts one row

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0097 removed one row at ten thousand rows without re-rendering the other
nine thousand nine hundred and ninety-nine, and closed by naming what it could
not reach:

> **`append`, declined for want of a host export.** Nothing in the handle
> mounts a row except `update`. Adding one is an ABI event, and this round did
> not build it; the price is recorded in OQ1 rather than guessed.

This ADR builds it.

### Where the time is

Measured on Toggle Lab, Chromium, rows seeded through the ADR-0063 hydration
path, seven passes of five repetitions per cell, median of medians, with the
region host's `update` split into its four internal phases by
`performance.now()` under cross-origin isolation. Milliseconds, one commit:

| rows | action | commit | of which `update` | key validation | **updateItem loop** | dispose | place |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 10 000 | `append` | 11.225 | 5.385 | 0.105 | **5.200** | 0.045 | 0.035 |
| 10 000 | `remove` @front | 1.765 | — | — | — | — | — |
| 10 000 | `toggle` | 2.310 | — | — | — | — | — |
| 1 000 | `append` | 1.020 | 0.530 | 0.040 | **0.450** | 0.015 | 0.015 |
| 100 | `append` | 0.130 | 0.065 | 0.005 | **0.055** | 0.000 | 0.005 |
| 10 000 | hydrate | 58.665 | 39.580 | 0.610 | **31.935** | 0.025 | *6.765* |
| 1 000 | hydrate | 6.300 | 3.930 | 0.050 | **3.370** | 0.005 | *0.500* |
| 100 | hydrate | 1.080 | 0.520 | 0.010 | **0.440** | 0.005 | *0.075* |

The `remove` and `toggle` rows are the post-ADR-0097 and post-ADR-0043 paths,
here as the controls they have become.

Four readings.

**The append's loop is the removal's loop, unchanged.** At ten thousand rows
it is 96.6% of `update` and 46% of the whole commit, linear in the row count
at about 0.52 µs per retained row — the same six DOM operations Toggle Lab's
generated row-update callback performs, run on all ten thousand retained
rows to mount one new one.

**Placement is already free for an append too.** `placeInOrder`'s prefix scan
matches every retained row and its suffix scan stops at once, so the whole
call is one `insertBefore` before the anchor: 0.035 ms over ten thousand rows.
ADR-0097 found the same for a removal. What the reconcile costs, at both ends
of the table, is the loop and only the loop.

**Key validation costs a scan the append does not need.** 0.105 ms: the new
key is the first that is not at its previous position, and answering "is this
key elsewhere in the table" runs `monotoneKeys` over all ten thousand and one
items. It is 2% of `update` — worth naming only because a positional insert
skips it entirely rather than making it cheaper.

**Hydration is the opposite shape and must stay on the reconcile.** With
nothing retained the loop is the *mount* loop, and the placement is no longer
free: 6.765 ms at ten thousand rows, because `rebuild` detaches the owned
parent, refills it, and re-attaches it once. Ten thousand `insertAt` calls
into a connected parent cannot match that, and there is no measurement here
that says where the crossover is. The bulk path is the reason hydration keeps
the dirty bit below rather than an oversight.

### The batch axis

A *k*-row append into one region inside one transaction is not expressible in
any lab: `append` is one `regionAppend`, every lab's appending event carries
exactly one of them per region, and Twin Lab's `seedOn` — the widest one —
appends a single row into each of three regions. The batch axis is therefore
*k successive transactions*, each paying the whole loop, and that is what the
result below measures. The language does admit
`append r (…) then append r (…)` through the `sequence` combinator, and the
emission handles it by construction:
the counter counts and the drain's cursor walks, whatever *n* is. That path has
no caller today, so the drain's exact cursor walk is exercised against the real
host in `Test/js/region_runtime.mjs` instead — three rows appended and drained
from `length - 3` upward, with the ADR-0093 order re-checked after each.

### What is left over

Killing the loop cannot take the commit below what the rest of it costs, and
at ten thousand rows the rest is 5.84 ms against `update`'s 5.385 — the
per-commit O(N) sweeps: the ADR-0088 shared predicate pass, the ADR-0051
filter sweep, and the ADR-0063 write-back's encode loop, `join` and
`storageSet` (priced in ADR-0096). An append is a structural change, so all of
them wake, and none of them is this ADR's subject. The predicted ceiling is
therefore about 2×, not the 2.9–4.3× ADR-0097 got on a removal — a removal's
commit had less left in it — and that is what the result below reports.

## Decision

**A component event's `append` counts itself instead of raising the dirty bit,
and the commit sweep mounts the rows it counted through a new host export,
`insertAt`.** Regions keep the reconcile for everything else.

### The export

`insertAt(index, item, context)` joins `updateAt`, `swapAt` and `removeAt` on
the keyed handle, and completes that family: one row is mounted through
`mountItem(item, index, context)` and placed before the row that holds `index`
now — or before the region's anchor marker at `index === current.length` —
while every other row keeps its handle, its node and its rendering. `index`
must be an integer in `[0, current.length]`; anything else is
`LRX-REGION-003`, thrown before any callback or DOM mutation, exactly as
`removeAt`'s key check is.

It is positional rather than append-only because the position is what the
caller already knows and what it can therefore be *checked against*, and
because a marker-only export would have named itself after the one caller that
exists today rather than after what it does.

A key an existing key index already holds is `LRX-REGION-001`. When no index
exists the caller owns key freshness — the index is built only when an
`update` needed it, and building it here to check one key would cost the O(N)
pass the export is being added to avoid. This is the same division of labour
the handle already runs: `update` trusts the caller for the shape of `items`,
`removeAt` trusts it for the position and checks the key.

The row crosses as a *caller array*, classified `insertAt: { 1: "row" }` in
the ADR-0094 `LRX-HOST-001` surface — H2's unfrozen crossing, because the host
forwards it to `mountItem`, which owns the ADR-0085/0086 cache slots, and only
slot 0 is the order's business. The region's own table is not handed over at
all: the drain reads one row out of it and passes that.

### The count, not a position

The record's **last** slot, behind the ADR-0097 drops queue, present exactly
when some component event appends into the region. It holds a *number*.

A `regionAppend` is a tail `push` — the only insertion the language has — and
a tail push shifts nothing, so the rows a transaction added are the last *n*
of whatever table it ends with. There is no position to store, so there is no
position that a later splice in the same transaction can leave naming the
wrong row. The drain walks a cursor from `length - n` to `length`, upward, so
each `insertAt` addresses a host whose entries already hold every row before
it.

It runs **after** the reconcile and **before** the ADR-0043 `updateAt` drain
and the ADR-0051 filter sweep, both of which address rows by row-table
position: only after the drain do the table and the host agree again.

The tail is also what keeps an ADR-0075 child-composing region's live
inventory in row order: the drain forwards the inventory as `rowContext`, so
each mounted row's children are pushed onto its end, exactly where the
reconcile's own in-order mount loop would have put them. A caller that
inserted into the *middle* would have to say something about that; this one
does not, and the export's generality is therefore ahead of its callers by
that one sentence.

### The invalidation obligations

**The wake flags.** An append is a structural change however it is recorded,
so every flag that read the dirty bit as "the row set moved" now reads the
counter beside it and beside ADR-0097's queue: `region_touched_{r}`,
`region_structural_{r}`, and each ADR-0084 drain class's flag. This is
ADR-0097's obligation again, and it fails the same silent way: every row
renders correctly while the counts, the emptiness sweeps, the filter table and
the write-back sleep through the append.

**The dirty branch zeroes the counter.** Whatever raised the dirty bit — an
ADR-0050 broadcast, a predicate removal, a hydration, or a removal that fell
back — the reconcile mounts every counted row along with everything else, so
the drain must not mount a second time. The counter is dropped exactly where
the ADR-0043 pending positions are dropped, and for the same reason.

**A removal that sees a non-zero counter falls back to the dirty bit.** The
splice a removal performs could be taking out a row this transaction appended,
and then the counter would name rows the table no longer ends with. Exactly
one action branch runs per dispatch and a row event can only name a row that
already has a DOM node, so this is unreachable today; rather than rest it on a
whole-language invariant, the emission discharges it as one comparison beside
ADR-0097's pending-queue comparison, and the reconcile — correct whatever the
mixture was — takes over.

The last two are unreachable together, and this ADR knows it rather than
assuming it: deleting the counter reset leaves all ninety-three Toggle, Twin
and Mix browser tests **passing**, because no lab can put an append and a
dirty-raiser into one transaction on the same region. They are guards against
programs the language cannot currently write, and they are code so that the
language can grow without the guard having to be rediscovered.

### What is *not* paid, and why

**Hydration, declined on the measurement above.** Its rows arrive as a whole
table into an empty region, where the reconcile's `retained === 0` path clears
and refills an owned parent *detached*: 6.765 ms of placement for ten thousand
rows that a per-row drain would pay one connected `insertBefore` at a time.
Choosing between them needs a threshold in generated code and this round has
no measurement that says where it is — the same sentence ADR-0097 wrote about
`removeIf`, for the same reason, at the other end of the table.

**The broadcast and the predicate removal**, unchanged: both re-render every
retained row by construction.

## Consequences

- Paired A/B against the pre-change emission, both variants in one browser
  process, **ABBA within every cell of every pass** over six passes, medians
  of per-cell medians. Appends: **2.31×** at 1 000 rows and **2.11×** at
  10 000 (a single-row `append` 0.958 → 0.415 ms and 11.130 → 5.288 ms); five
  successive single-row appends 1.84× and **2.20×** (52.985 → 24.040 ms at
  10 000). Every untouched path stays within noise: `removeMiddle` 1.03× and
  1.14×, `removeIf` 1.00× and 1.01×, `toggle` 0.97× and 1.02×, and hydration
  55.0 → 56.7 ms at ten thousand rows. What remains of the append is the
  per-commit O(N) sweeps named above; the host's `update` is not entered at
  all.
- The harness needed fixing before those ratios could be read, and the fix is
  the reusable part. An **A/A control** — the same dist against a byte-copy of
  itself — reported the 10 000-row `toggle` at 0.79×, because on a
  storage-dominated cell the variant that runs *second* pays for the first's
  250 kB of `localStorage` writes, and merely alternating the leader across an
  odd number of passes leaves that bias in. Running ABBA within each cell of
  each pass brings the same control to 0.95–1.00×.
- The region instrumentation says it exactly. Five single-row appends over a
  ten-thousand-row region moved `[mounts, updates, moves, disposals]` by
  `[5, 50010, 5, 0]` and now move it by `[5, 0, 5, 0]`.
- **`runtimeAbi` moves 17 → 18**, the first change under `runtime/` since
  ADR-0063. Every manifest changes and nothing else in them does; twenty-six
  mechanical references move with it — `LeanRx/Core/Version.lean`, sixteen
  artifact tests' manifest assertions, the differential check, six Lean backend
  tests, the CLI doctor's expected output, and the Expression Playground
  example's own manifest check.
- Exactly five generated modules change, and they are exactly the five whose
  components declare an appending event: `BranchLab.mjs`, `MixLab.mjs`,
  `NestLab.mjs`, `ToggleLab.mjs` and `TwinLab.mjs` gain the counter slot in
  their region records, the count at each append site, the drain in each
  commit sweep, the counter in each wake flag, and — where the region also
  removes — the extra conjunct in the removal's fallback. Regenerating every
  lab on both sides and comparing file by file, every other generated
  *module* is byte-identical: Counter, Diamond, Echo, Filter, Tabs,
  Temperature, Validated Form, TodoMVC, Notes, Issue Browser, Data Grid and
  the docs lab. `leanrx_region.mjs` changes in all eight bundles that ship it,
  which is the export.
- **The js-framework-benchmark size gate moves and the baseline is updated**:
  that backend inlines the whole keyed host into one file, so `main.mjs` grows
  by the export it never calls — raw 8 444 → 8 776 bytes (+332, +3.9%),
  brotli 3 103 → 3 200 (+97), gzip 3 450 → 3 547 (+97). The benchmark's own
  emission is unchanged apart from the minifier's name assignments shifting
  around the new method.
- The ADR-0093 row-order audit is untouched: the counter is not a row table,
  the drain reads the table's `length` and one element and hands neither the
  table nor a whole record anywhere, and R5's kept-filter — the `removeIf`
  path — is again exactly what this ADR declined to touch.

## Open questions

1. **The per-commit O(N) sweeps.** With the reconcile gone from both
   single-row paths, a ten-thousand-row structural commit is 5.3 ms of which
   none is the region host: the ADR-0088 predicate pass, the ADR-0051 filter
   sweep and the ADR-0063 write-back each walk the whole table for a change
   that touched one row. Each of the three already knows *which* row moved —
   the drains hold it — so the question is whether a structural change can
   carry a row-scoped signal the way ADR-0084 made a field write carry one,
   and what that costs a transaction that moves many rows at once.
2. **The bulk threshold, now asked from both ends.** ADR-0097 declined
   `removeIf` because its row count is unbounded and the reconcile's
   `retained === 0` path clears in bulk; this ADR declines hydration for the
   mirror reason, and now has the number that ADR-0097 did not: 6.765 ms of
   detached placement against ten thousand connected inserts. A threshold in
   generated code would close both, and needs the crossover measured.
