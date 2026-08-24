# ADR-0040: Sketch an App IR to generalize Backend.Todo's event lowering

- Status: Proposed
- Date: 2026-08-25

## Context

`Backend.Todo` (and `Backend.Notes`/`Backend.IssueBrowser` after it) is a
bespoke emitter: it hand-builds the keyed todo region and the positional
filter region, wires four `listenDelegated` listeners with a hand-rolled
action vocabulary, hand-threads the region handles through a private context
layout, and re-implements the transaction bookkeeping that
`Backend.Component` already generates from a checked specification. The
generic backend meanwhile learned typed payloads (ADR-0037), controlled
inputs (ADR-0038), and static children (ADR-0039), but still cannot express a
dynamic region, so every keyed-list application needs a new bespoke backend —
the largest remaining DX gap.

## Proposal

Introduce a checked **App IR** between `ComponentSpec` and the emitted
module, and move Todo's event lowering onto it in three steps:

1. **Region slots in the view.** Extend the safe view with
   `View.keyedRegion` / `View.conditionalRegion` nodes analogous to
   `View.child`: a slot carries a row schema, a row template (an ordinary
   safe sub-view over the row schema), and the source expression producing
   the keyed items. `ComponentSpec.check` validates the row template with the
   existing view gates and plans the row sinks into per-region graphs, so the
   scalar-sink invariants (sources prefix, acyclicity, sink typing) extend to
   rows unchanged.
2. **Delegated events from structure.** Row events are declared on the row
   template with the existing `onClick={…}`/typed attributes, but lower to
   one delegated listener per event type on the region container, resolving
   the action by row structure exactly like the ADR-0030/0032 benchmark path
   (`listenDelegatedCells`, `setKey` carriers) instead of Todo's
   `data-lrx-action` attribute vocabulary. The dispatch functions receive
   `(key, payload)` and reuse the ADR-0037 transaction shell; the keyed
   region's `update` call joins the commit sweep after text and property
   sinks, feeding the ADR-0026/0027 delta machinery.
3. **Retire the bespoke context.** The region handles ride the mount context
   after `propRefs`/`propCache`, the manifests disclose regions as features
   plus per-region counts, and `Backend.Todo` shrinks to a driver that
   builds an App IR value; TodoMVC is the migration gate — its browser and
   differential suites must pass unchanged on the App IR emission before the
   bespoke emitter is deleted. Byte identity is explicitly not promised for
   Todo (the module changes); behavior parity is the bar, and components
   without regions must stay byte-identical throughout.

## Open questions

- Row schemas are dependent (each row reads its item, not the component
  state); whether rows get a separate `Schema` with an embedding or a sealed
  row-scope binder in `RxExpr` decides most of the Lean-side work.
- Todo's filter row (positional region over static content) may be
  expressible as a degenerate keyed region; if not, the positional region
  needs its own slot node.
- Whether `eventCount`/`textSinkCount` should count row-template instances
  (dynamic) or declarations (static) in the manifest.

## Consequences (if accepted)

- Keyed-list applications become writable in the `component` command with no
  raw backend code, closing PLAN.md M8 item 4 from the specification side.
- The delegation path and the benchmark path share one structural mechanism,
  so ADR-0030's performance argument covers applications too.
