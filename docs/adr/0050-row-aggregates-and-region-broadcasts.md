# ADR-0050: Sealed row aggregates and region broadcasts

- Status: Draft
- Date: 2026-08-26

## Context

The remaining TodoMVC migration gaps are no longer per-row interactions
(ADR-0049 closed those) but whole-region observations and mutations: the
`items-left` counter derives a count from the keyed rows, toggle-all writes
one field of every row at once, and clear-completed removes every row
matching a predicate. The sealed vocabulary has no way to say any of the
three: component derived values are `RxExpr` over component state and cannot
observe region rows, and the only component-event region step is
`regionAppend` — bulk mutation today means dispatching one delegated row
event per row from the outside, which is not expressible either.

The host already carries everything the three need. The region record is
`[handle, items, nextKey, dirty, pending]`: `items` is the whole row table
in target order, a dirty commit calls `handle.update(items)`, and the keyed
reconcile retains every row whose key survives — keeping its handle and DOM
node — while re-running the retained-row update callback on it and disposing
rows whose keys disappeared (ADR-0041/0043). So writing row fields in
`items` and raising `dirty` re-renders every retained row with identity
preserved, filtering `items` disposes exactly the filtered rows, and a count
over `items` needs only a text node and the existing `setText` export.

## Decision

Three sealed extensions over the existing region record and commit sweep,
expected to need **no host change and no runtime ABI bump**, with the
alternatives rejected:

1. **Mirror region state into component state — rejected.** Deriving counts
   by maintaining a shadow `Int` source per aggregate would make every
   append/remove/toggle event a two-place update the compiler cannot check
   for agreement; the row table is the single source of truth and the
   aggregate must read it.
2. **An open fold/reduce expression over rows — rejected.** A general
   aggregation language would leak arbitrary user programs into the commit
   sweep. The vocabulary stays sealed: the row count of a region, or the
   count of rows whose projected field equals one string literal — the same
   single-field `String` equality predicate every other sealed selection
   uses (ADR-0044/0045/0047/0049).
3. **Broadcast as a host primitive (`updateAll`) — rejected.** The keyed
   reconcile already is the broadcast path: retained keys keep row identity
   and re-run the update callback. A bespoke host loop would duplicate
   `update(items)` for no observable difference and cost an ABI bump.
4. **The sealed aggregate and broadcast vocabulary — adopted direction.**
   - A **region count** is a component text position, `{count region}` or
     `{count region (field == "literal")}`, lowered to a sealed
     `View.regionCount`. It mounts as a `"0"` text node (regions mount
     empty by construction) and joins the commit sweep beside the text
     sinks: whenever the region was touched this transaction (structurally
     dirty or holding pending row updates), the count is recomputed from
     `items`, compared against a cache, and written through the existing
     `setText` export. The region record grows two region-local slots —
     `[…, countRefs, countCache]` — emitted only for regions with counts.
   - A **region broadcast** is a component event step,
     `update region (set field (expr), …)`, whose right-hand sides are the
     ADR-0043 sealed row expressions (fields, literals, `++` — payload-free)
     evaluated simultaneously against each row's current tuple. The emitted
     step writes every row in `items` and raises the dirty flag; the keyed
     reconcile then re-renders every retained row with identity preserved.
     A broadcast makes a region's rows mutable, so it forces the real
     update-callback body (and the `childAt` import) exactly as a `row`
     update event does.
   - A **region removal** is a component event step,
     `remove region (field == "literal")`, keeping the rows whose projected
     field does not equal the literal and raising the dirty flag; the
     reconcile disposes exactly the removed keys and retains the survivors
     untouched apart from their update-callback pass.

Counts must name a declared region and project declared fields
(`LRX-VIEW-038`); broadcasts must target a declared region with nonempty,
distinct, in-bounds, payload-free assignments (`LRX-TYPE-111`); removals
must target a declared region and an in-bounds field (`LRX-TYPE-112`).
Row expressions stay `String`-only and equality stays the single predicate
form, so `items-left` counts the rows whose canonical field equals its
literal (`done == "false"`); a negated predicate or arithmetic over counts
remains out of the vocabulary and is recorded as a gap.

## Open questions

1. Should a broadcast that provably writes every row to its current value
   (e.g. `set done done`) still dirty the region? The draft says yes —
   per-row change detection would put a comparison loop in the event path
   for a case the author can avoid.
2. Should counts join the trace vocabulary with their own labels? The draft
   reuses the sink counters (`tx[5]`/`tx[6]`) with `count:{region}:{index}`
   labels so instrumentation gates can pin them.
