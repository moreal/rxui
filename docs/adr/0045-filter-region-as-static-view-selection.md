# ADR-0045: Express TodoMVC's filter row as static view with state-scoped selection

- Status: Accepted
- Date: 2026-08-25

## Context

ADR-0040 left one stage-2 question open: `Backend.Todo`'s filter row is a
*positional* region (three statically known buttons whose classes and
`aria-pressed` reflect the selected filter), and the sketch asked whether the
generic backend should express it as a degenerate keyed region or grow a
dedicated positional slot node. The bespoke emitter drives it through
`createPositionalRegion` with a delegated click listener and re-renders the
three buttons from component state on every filter change.

## Decision

Neither. The filter row is not a region in the generic backend:

1. **Degenerate keyed region — rejected.** The rows would need constant
   synthetic keys and, decisively, their content reacts to *component* state
   (the selected filter), which the ADR-0041 seal deliberately forbids row
   templates from observing. Admitting component-state reads into row scope
   to model three static buttons would reopen the sealed-binder decision for
   no cardinality benefit — the row set never changes.
2. **Dedicated positional slot node — rejected for now.** A positional slot
   earns its complexity when the *number* of positions is dynamic. Todo's
   filter row has static cardinality three; every runtime obligation
   (`createPositionalRegion`, per-position update callbacks, container
   ownership) would encode what the static view already knows. No other
   application on the roadmap needs dynamic positional content.
3. **Static view + state-scoped attribute selection — adopted and shipped.**
   The filter row is ordinary static view structure: three buttons with
   plain component events (`set filter …`). The missing capability was a
   *state-scoped* analogue of ADR-0044's row-scoped class selection, and it
   ships as the sealed `AttrSelect` vocabulary on static view elements:

   - `class={if field == "literal" then "a" else "b"}` selects between two
     statically known class strings;
   - `ariaPressed={field == "literal"}` reflects the equality as
     `"true"`/`"false"`;
   - `disabled={field == "literal"}` reflects the equality as the boolean
     element property, reusing the existing `setProperty` host export
     because a `disabled` *attribute* cannot be cleared by assignment.

   The predicate vocabulary is exactly equality of one `String` component
   value (source or derived — the guard is the value's `changed` flag, so
   both work) against one string literal; the field is a typed
   `Field Γ String`, so a cross-typed predicate is unrepresentable in Lean.
   Selections join the commit sweep beside text sinks and reflected
   properties with the established evaluate-compare-write shape: they share
   the reflected-property counters (`tx[8]` evaluations, `tx[9]` writes),
   keep their last written value in an `attrCache` context slot pair
   allocated after the prop slots, and re-emit only differing values. That
   closes the `disabled`-reflection gap recorded since the Echo Lab round
   with the same mechanism, and the hash-routing half of the filter feature
   stays a separate effects question.

Consequence for the ADR-0040 gate list: the "positional or degenerate-keyed
filter region with a selection reflection" capability is re-scoped to
"state-scoped attribute selection on static view elements" and is now
shipped, and `createPositionalRegion` stays a bespoke-emitter export that the
App IR migration does not need to generalize.

## Consequences and limitations

- No new host export and no ABI change: `setAttribute`, `setProperty`, and
  the conditional expression already exist in the validated JS subset;
  components without selections stay byte-identical, and the context layout
  moves only for components that use them (regions ride two slots later).
- A selection counts as its attribute for duplicate detection
  (`LRX-VIEW-001`), so at most one selection per attribute per element and
  no static attribute beside one. `aria-pressed` and `disabled` selections
  require a native button (`LRX-VIEW-032`); `class` selections are valid on
  any element. Selections appear as `attr:{index}:{name}` sink nodes in the
  planned graph.
- Multi-way selection, predicates over several fields or non-`String`
  values, other attribute names, and selections inside row templates stay
  out of scope until a gate needs them (`LRX-VIEW-012` reports the sealed
  surface shapes).

## Confirmation

The Filter Lab example mirrors the TodoMVC filter row exactly (three
all/active/completed buttons carrying class and `aria-pressed` selections,
plus a `disabled`-selected Reset button) and is gated in Chromium: initial
reflection, selection movement on click and keyboard activation, the
evaluate-seven-write-five sweep shape, the no-op reselection, and disposal.
Running the TodoMVC filter row itself through the generic backend remains
the ADR-0040 migration gate list's business.
