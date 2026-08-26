# ADR-0051: Select keyed row visibility through a sealed filter table

- Status: Accepted
- Date: 2026-08-27

## Context

TodoMVC's filter feature spans three axes. ADR-0045 shipped the filter *row*
(static buttons with state-scoped attribute selections), ADR-0050 shipped the
whole-region aggregates the footer needs, and the remaining axis is the
display set itself: the keyed region must *show* only the rows matching the
selected filter while `items-left` keeps counting over every row. The sealed
vocabulary cannot say this today: row templates are sealed against component
state by design (ADR-0041), so no row-scoped selection can observe the
selected filter, and every existing region step (`append`, broadcasts,
removals) changes the row *table*, not its visibility.

The shape of the missing capability is a correspondence: one `String`
component state field (`filter ∈ all/active/completed`) mapped to row-field
equality predicates — the same single-field `String` equality every sealed
selection uses (ADR-0044/0045/0047/0049/0050) — where the `all` case carries
no predicate and shows everything.

## Decision

A **sealed region filter view**, expected to need **no host change and no
runtime ABI bump**, with the alternatives rejected:

1. **Reconcile the visible subset — rejected.** Passing
   `items.filter(predicate)` to the existing `handle.update` would make the
   keyed reconcile the visibility mechanism, but it disposes every hidden
   row and remounts it on the way back, so row identity, DOM nodes, and
   focus survive only within one visible set — the opposite of what the
   retained-key machinery exists to guarantee. Decisively, it breaks the
   region record's positional invariants: the pending slot drains `updateAt`
   with positions into the *full* `items` and the delegated dispatcher
   resolves keys against it, so a filtered handle would need a
   position-translation layer or a forced structural reconcile on every
   transaction under an active filter.
2. **Admit component state into row templates — rejected.** A row-scoped
   `hidden={filter == "active" && …}` selection would reopen the ADR-0041
   seal for one attribute, and the retained-row update callback cannot see
   component state either — the callback signature is part of the host
   contract.
3. **A class-based visibility hook — rejected.** The row root's `class`
   attribute belongs to the template's sealed class selection (ADR-0044);
   a second writer would race it, and a compiler-owned utility class would
   push a stylesheet obligation into the host.
4. **The sealed filter table over row-node `hidden` recording — adopted.**
   - A **region filter** is a component item,
     `filter region by field := when "literal" (rowField == "literal")
     then …`, mapping distinct state literals to row-field equality
     predicates. A state value outside the table — TodoMVC's `"all"` —
     carries no predicate and shows every row. At most one filter per
     region; the table field is a typed `Field Γ String` (source or
     derived — the guard is the value's changed flag, as in ADR-0045), so a
     cross-typed selector is unrepresentable in Lean.
   - The **commit sweep applies the table** after the region's reconcile
     and `updateAt` drain, whenever the region was touched this transaction
     (the ADR-0050 dirty-or-pending flag, read before the reconcile and
     drain consume it) or the filter field changed: it walks `items` in
     order and writes each row root's `hidden` property through the
     existing `setProperty` export, navigating `childAt(container, i)` —
     sound because a region owns its whole container (LRX-VIEW-029), rows
     precede the anchor marker in `items` order, and every row root is one
     element. Rows never mount or dispose on a filter change, so identity,
     focus, and the region metrics are untouched by construction.
   - The **container element rides one new region-local record slot**
     behind the ADR-0050 count slots — `[handle, items, nextKey, dirty,
     pending, countRefs?, countCache?, containerEl?]` — emitted only for
     regions with a filter, because dispatch functions reach DOM references
     through the context's region records only.
   - **Instrumentation**: the sweep is one region-level selection riding
     the ADR-0045 selection counters — one `tx[8]` evaluation and one
     `tx[9]` write per run, labelled `filter:{region}:evaluated` and
     `dom:filter:{region}:write`. Per-row `hidden` assignments carry no
     per-row cache: the equal-value property write is a WHATWG no-op, the
     ADR-0050 equal-value-broadcast rationale reused.

Filters must name a declared region and project declared row fields, with
nonempty arms over distinct state literals and at most one filter per region
(`LRX-TYPE-113`); the surface shapes are pinned by `LRX-ELAB-120`. Each
filter joins the planned graph as a `filter:{index}:{region}` sink node over
its state field, beside the ADR-0045 selection sinks.

Consistency with the aggregates is by construction: counts read the full
`items` (ADR-0050) and the filter only hides row nodes, so `items-left`
counts the canonical `done == "false"` set regardless of the selected
filter, and the displayed set is exactly the predicate's rows. Appended rows
mount unhidden and take their visibility inside the same commit (the append
raises the touched flag); a row update that changes a predicated field
re-hides or reveals exactly that row's node; broadcasts and removals flow
through the same touched flag.

## Open questions

Both resolved by the implementing round as drafted:

1. **The sweep carries no per-row visibility cache.** The unconditional
   walk is O(rows) only on touched-or-switched transactions, equal-value
   `hidden` writes are WHATWG no-ops at the DOM layer, and a cache would be
   positional, needing invalidation across structural reconciles for no
   observable difference.
2. **No explicit empty-predicate arm.** Unmatched state values show all
   rows, so `all` needs no arm; an explicit no-predicate arm would be a
   second spelling of the default.

## Consequences and limitations

- No new host export and no ABI change: `childAt`, `setProperty`, and the
  region record already exist; components without filters emit byte-identical
  modules, and the js-framework-benchmark bundle stays byte-identical under
  the performance freeze.
- The predicate vocabulary stays single-field `String` equality — no
  negation, no multi-field conjunction — so an `active` filter tests the
  canonical `done == "false"` form; a state literal maps to at most one
  predicate, and at most one filter watches a region. Hidden rows keep their
  DOM nodes and per-row state; they cannot originate delegated events while
  hidden (`display: none` is unreachable by pointer), which is the intended
  reading of "not displayed".

## Confirmation

Confirmed by the filter-view round as drafted: the extension ships through
the generic backend with no host change and no ABI bump — Toggle Lab's
emitted import lines are byte-identical to the ADR-0050 round's, and every
file of the js-framework-benchmark bundle (`main.mjs` and manifest
included) is byte-identical to the HEAD baseline under the performance
freeze (compared via a separate git worktree build; only the
`.leanrx-bundle-owner` marker differs, and it embeds the output directory
name). Toggle Lab's browser gates show the filter switch hiding exactly
the non-matching rows with zero region-metrics movement (no mounts,
updates, moves, or disposals — the sweep writes `hidden` only), the same
DOM nodes surviving hide/reveal round trips, a checked row leaving the
active set live through the `updateAt` drain's touched flag, appended rows
taking their visibility inside the appending commit, broadcasts and
removals composing with an active filter, and `items-left` counting the
full row table throughout. `LRX-TYPE-113` is pinned by five model gates
plus one compile-fail fixture, `LRX-ELAB-120` by two compile-fail
fixtures, and the sweep shape, the extended region record, and the
unchanged import lines by the artifact gate. The recorded gaps stand:
single-field `String` equality arms, at most one filter per region, and no
explicit empty-predicate arm.
