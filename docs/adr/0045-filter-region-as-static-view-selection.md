# ADR-0045: Express TodoMVC's filter row as static view with state-scoped selection

- Status: Proposed (decision draft)
- Date: 2026-08-25

## Context

ADR-0040 left one stage-2 question open: `Backend.Todo`'s filter row is a
*positional* region (three statically known buttons whose classes and
`aria-pressed` reflect the selected filter), and the sketch asked whether the
generic backend should express it as a degenerate keyed region or grow a
dedicated positional slot node. The bespoke emitter drives it through
`createPositionalRegion` with a delegated click listener and re-renders the
three buttons from component state on every filter change.

## Decision (draft)

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
3. **Static view + state-scoped attribute selection — adopted direction.**
   The filter row is ordinary static view structure: three buttons with
   plain component events (`set filter …`). The missing capability is a
   *state-scoped* analogue of ADR-0044's row-scoped class selection — a
   sealed attribute selection on static elements driven by an `RxExpr`
   (`class={if rx% filter == "active" then "selected" else ""}` and the same
   for `aria-pressed`/`disabled`), joining the commit sweep beside text
   sinks and reflected properties with the established
   evaluate-compare-write shape. That closes the `disabled`-reflection gap
   recorded since the Echo Lab round with the same mechanism, and the
   hash-routing half of the filter feature stays a separate effects
   question.

Consequence for the ADR-0040 gate list: the "positional or degenerate-keyed
filter region with a selection reflection" capability is re-scoped to
"state-scoped attribute selection on static view elements", and
`createPositionalRegion` stays a bespoke-emitter export that the App IR
migration does not need to generalize.

## Confirmation bar

This draft is confirmed (Status → Accepted) when a follow-up round ships
state-scoped attribute selection through the generic backend and the TodoMVC
filter row renders and reacts through it under the existing browser gates;
it is revised instead if that implementation surfaces a genuine dynamic
positional consumer.
