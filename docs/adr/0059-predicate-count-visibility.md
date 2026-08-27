# ADR-0059: Predicate-count visibility — the clear-completed affordance

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0058 closed TodoMVC's hide-when-empty parity with the sealed
region-subject hidden selection — `hidden={count region == 0}` — and
recorded predicate-driven visibility as its first open question: TodoMVC
also hides the *Clear completed* button while no row is completed, and the
ADR-0058 subject cannot express that. The needed subject already exists in
the vocabulary: the ADR-0050 predicate count — the number of rows whose
one projected field equals one string literal — is what the count texts
display; the affordance needs exactly that number read as a boolean
against zero, the same reading ADR-0058 gave the row total.

The affordance also has a contract shadow: `clearCompleted` is the
ADR-0050 predicate removal, and clicking it while no row matches is
already an observable no-op. Like the ADR-0057 disabled affordance, the
hidden button is only a reflection of a predicate the dispatch layer
already honors — the affordance is not the contract.

## Decision

**Extend the sealed hidden selection with the one predicate-count subject
and nothing else.** `hidden={count region (field == "literal") == 0}` on a
static view element is the `AttrSelect.hiddenIfEmpty` selection carrying
the optional sealed predicate — the ADR-0050 pair of one projected row
field index and one compared string literal, the exact shape
`RegionCount.predicate` carries. The element's `hidden` boolean property
reflects whether no row of the named declared region satisfies the
predicate. The total-count subject of ADR-0058 is unchanged and remains
spelled without a predicate.

The surface is claimed by the same component-command rewrite (the pass
that resolves `{count region}` children and the ADR-0058 form): the
accepted predicate form resolves the region and the field against the
declared inventory and rewrites to the internal
`regionHidden% "region" fieldIndex "literal"` attribute — the
`regionCount%` optional-argument shape. A predicate field outside the
declared row fields reports `LRX-ELAB-119` at the surface and the
out-of-bounds index `LRX-VIEW-042` at the model (the LRX-VIEW-038
count-predicate rule carried into the selection); every other dynamic
`hidden` value still reports `LRX-ELAB-125`.

The lowering is ADR-0058's with the subject swapped:

- **Mount**: the element's ref joins the shared `attrRefs` and its cache
  slot mounts as the literal `true` through the existing `setProperty`
  export — an empty region satisfies no predicate, the same reasoning
  that mounts the total subject hidden and the count texts at `"0"`.
- **Sweep**: the selection reads no state field and joins no planned-graph
  sink. Whenever its region was touched this transaction (the shared
  `region_touched` flag of ADR-0050/0051/0058), the commit sweep runs the
  ADR-0050 predicate scan over the row table, compares the count against
  zero, compares the boolean against the shared attr cache slot, and
  writes the property only on a flip — the same tx[8]/tx[9] counters and
  `attr:{index}:hidden` labels.
- **Filter independence**: a filter change alone never touches the
  region, so the scan does not even run; and because the subject is the
  row table, the affordance follows the done rows wherever an ADR-0051
  filter hides them.

The rejected alternatives:

1. **Other comparison operators and threshold literals — rejected.**
   `!=`, `<`, `>`, and any nonzero literal on either subject read as a
   general numeric-predicate vocabulary; the parity needs "no row
   satisfies it", and the zero literal stays part of the sealed shape
   (`LRX-ELAB-125`).
2. **Negation and composition — rejected.** A `visible`-style negation, a
   conjunction over two predicates, or a predicate over two regions forks
   the selection language into the open frontier every ADR since 0043 has
   declined; the ADR-0057/0058 rejections carry over unchanged.
3. **Multiple predicates per subject — rejected.** The predicate is the
   one sealed row-field-to-string-literal equality (ADR-0050's); predicate
   algebra is unrepresentable by construction.
4. **General aggregate expressions — rejected.** `hidden={expr}` over
   arbitrary aggregates makes the re-evaluation set open-ended; the sealed
   subject keeps one region, one optional predicate, one touched flag, one
   cache slot.
5. **A visibility-specific host export — rejected.** The property write
   reuses the existing `setProperty` export on the existing element; no
   host change and no runtime ABI bump.
6. **Restricting the selection away from buttons — rejected.** The
   ADR-0058 rule stands: only `aria-pressed` and `disabled` demand a
   native button (`LRX-VIEW-032`); `hidden` is valid on any static
   element, and TodoMVC's clear-completed affordance is a button.

## Open questions

1. **The affordance stays a reflection.** The hidden button and the
   `clearCompleted` no-op agree by construction (both read the same
   predicate against the same table), but nothing ties them: a component
   may hide an element whose predicate matches no event's. Whether
   affordance-contract agreement should be checkable is untouched.
2. **The subject stays one region and at most one predicate.** Visibility
   over several regions, over a region plus state, or over composed
   predicates is unrepresentable.
3. **Row-scope selections stay untouched.** The ADR-0044 row class
   selection and ADR-0049 checked reflection still compare raw projected
   fields.

## Consequences and limitations

- TodoMVC's clear-completed visibility parity is expressible: Toggle
  Lab's Clear completed button carries
  `hidden={count items (done == "true") == 0}`, mounts hidden, is
  revealed by the first done toggle, re-hides when the last done row
  untoggles, clears, or is removed, ignores filter changes (the region is
  untouched), and stays revealed under the `completeAll` broadcast.
- A predicate hidden selection costs one row-table scan per
  region-touching transaction — the ADR-0050 count-text cost — and only
  there; the boolean cache keeps every non-flip write-free.
- A user can no longer *click* a hidden clear-completed button, so a gate
  exercising the no-op removal dispatches the click structurally; the
  dispatch-layer no-op contract itself is unchanged.
- The dispatcher, `reconcile6`, the row vocabulary, and the host ABI are
  untouched; the key set stays sealed at Enter/Escape; the guard literal
  stays `""`; row guards stay single-field remove-or-commit; row scope
  still has no `s!`; branch cells stay single-level two-branch with exact
  click/dblclick agreement; and the parent-disposer instrumentation gap
  is unchanged.

## Confirmation

Confirmed by the affordance-visibility round as drafted: the extension
ships through the generic backend with no host change and no runtime ABI
bump — every file of every other lab and of the js-framework-benchmark
bundle (`main.mjs` and manifest included) is byte-identical to the HEAD
baseline under the performance freeze; only Toggle Lab's module, manifest
(gaining the `predicate-visibility` feature), and graph (source spans
only — the selection joins no graph node) change. Toggle Lab's browser
gates pin the button hidden at mount, the not-done append's evaluate-only
sweep (one `attr:1:hidden:evaluated`, no write), the first done toggle's
reveal, the re-hide through untoggling the last done row, through
`clearCompleted` itself, and through the ✕ removal of the last done row,
the filter-change non-evaluation with the button revealed while its done
row is filter-hidden, and the `completeAll` broadcast's evaluate-only
revealed steady state. The model gates pin the forged predicate
selection's mounted position, `select:hidden:r:0:true` debug marker,
boolean value type, graph exclusion, and out-of-bounds predicate field
(`LRX-VIEW-042`); the elaborator gate pins Toggle Lab's mounted triple
(the trimmed `disabled`, the predicate `hidden` at the button's path, and
the total `hidden` at the wrapper's) and the guide's `CountedRosterMini`
pair; compile-fail fixtures pin the sealed surface (a predicate count
against a nonzero threshold, `LRX-ELAB-125`, and an unknown predicate
field, `LRX-ELAB-119`); and the artifact gate pins the three-slot mount
block, the region-touch sweep with the predicate scan beside the
emptiness subject, and the `predicate-visibility` manifest feature beside
the unchanged import shape.
