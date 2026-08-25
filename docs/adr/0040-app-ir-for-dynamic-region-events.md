# ADR-0040: Sketch an App IR to generalize Backend.Todo's event lowering

- Status: Accepted (stage 1 shipped via ADR-0041; stages 2–3 remain planned)
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

## Open questions (resolutions after stage 1)

- ~~Row scope representation~~ — **decided in ADR-0041**: a sealed row binder
  (`RowNode.fieldText` projections plus a closed `RowAction` vocabulary), not
  a schema embedding; `RxExpr`/`DepSet`/proofs stay untouched. General
  row-scope staged expressions remain the recorded gap.
- Todo's filter row (positional region over static content) may be
  expressible as a degenerate keyed region; if not, the positional region
  needs its own slot node. Still open; stage 2.
- ~~Manifest counting~~ — **decided in ADR-0041**: manifests disclose the
  `keyed-regions` feature and the `./leanrx_region.mjs` host import only;
  `eventCount`/`textSinkCount` keep counting static component declarations,
  and per-region counts stay out of the manifest until a schema bump is
  worth taking.

## TodoMVC migration scope (stage 3 gate list)

Behavior parity — not byte identity — is the bar for deleting the bespoke
emitter. The generic backend must pass every gate below on an App IR emission
of TodoMVC before `Backend.Todo` shrinks to a driver:

1. **Browser gates** (`Test/browser/todo.spec.mjs`): keyed identity across
   reorder/filter (retained rows keep DOM nodes and focus), hash routing for
   the filter selection, local region ownership on dispose, delegated
   keyboard edits scoped to the editing row, and retained drafts across
   reconciliation.
2. **Differential suite** (`check_differential.sh` over `Todo.Model`): the
   generated event lowering must agree with the pure Lean
   `Todo.update`/`visible`/`remaining` semantics on generated message traces,
   including trim-and-delete on empty commit, editing-id retention across
   `clearCompleted`, and reverse-order reconciliation.
3. **Artifact pins** (`Test/js/todo_artifacts.mjs` and
   `check_component_codegen.sh`): deterministic emission, manifest schema,
   and the banned-construct sweep, re-pinned to the App IR output.
4. **Region runtime invariants**: LRX-REGION-001 unique keys and the
   LRX-REGION-003 retained-key checks must hold on the App IR paths that call
   `updateAt`/`swapAt`/`removeAt`.

Capabilities the generic backend still lacks for this migration, in
dependency order: row field mutation (rows are immutable in stage 1 —
`updateAt` is never emitted), row-scoped dynamic attributes/classes
(`completed`/`editing`), conditional structure inside rows (edit input vs
label), typed payload row events (`input`/`keydown`/`change` delegation with
values), a positional or degenerate-keyed filter region with a selection
reflection, and focus scheduling on edit start. Each lands as its own
ADR-0041-style sealed extension.

## Consequences (if accepted)

- Keyed-list applications become writable in the `component` command with no
  raw backend code, closing PLAN.md M8 item 4 from the specification side.
- The delegation path and the benchmark path share one structural mechanism,
  so ADR-0030's performance argument covers applications too.
