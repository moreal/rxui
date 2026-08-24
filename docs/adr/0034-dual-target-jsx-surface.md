# ADR-0034: Lower one JSX surface into typed views and the logical region model

- Status: Accepted
- Date: 2026-08-24

## Context

The `jsx%` surface reached only the schema-typed safe `View` with six tags,
five attributes, and `click`, so the dynamic-region applications (TodoMVC and
its siblings) hand-wrote their reference `Region.LogicalNode` trees and none of
the promised surface conveniences — keyed lists, nested components — existed.
`PLAN.md` M8 ordered keyed regions as semantics without surface syntax, and
DOGFOOD recorded row construction "as validated AST" as accepted friction.

## Decision

Keep one shared grammar and select the lowering from the expected type:

- An expected `LeanRx.View Γ` (or unknown) target keeps the existing typed
  lowering, extended with the new whitelist tags
  (`h2 h3 header footer nav ul li input label strong em`), static `role` and
  `placeholder` attributes, and an `onDblClick` binding (`EventKind.dblclick`),
  which the generic component backend lowers through the same `listen` path.
- An expected `LeanRx.Region.LogicalNode` targets the logical reference model:
  attributes may be dynamic (`class={term}`), children may be dynamic text
  (`{term}`), and the closed attribute vocabulary adds `value`, `filter`, and
  camelCase `data*` idents mapped to `data-*`.
- The keyed list surface syntax
  `for x in items key keyValue => <element ...>` lowers onto the existing
  keyed region IR: it produces `List Region.KeyedItem` (usable directly or
  through `KeyedList.create`), and as a child it splices through the new
  `Region.KeyedItem.nodes` projection.
- A capitalized element head (`<TodoRow todo={todo} .../>`, self-closing
  elements included) nests another component as an ordinary typed Lean
  application with named props. A prop whose declared type is the M6
  `ImmutableProp` wraps its value through `ImmutableProp.of` with the
  attribute name; every other prop elaborates directly against its declared
  type, so prop mismatches are ordinary Lean type errors.

Mode mismatches keep stable diagnostics: `LRX-VIEW-011` (keyed list in a typed
view), `LRX-VIEW-012` (dynamic attribute/text in a typed view), `LRX-VIEW-013`
(event binding in the logical model), `LRX-VIEW-014` (malformed component
props), `LRX-VIEW-015` (named sink in the logical model), with `LRX-VIEW-007`/
`-008`/`-010` shared by both targets.

## Consequences

- `examples/TodoMVC.lean` now defines the TodoMVC user surface in the DSL —
  a nested `TodoRow` component, the keyed row list, and the full logical view —
  and `examples/TodoMVCBuild.lean` generates the differential golden
  projection from that surface. `Test/Elab/TodoSurface.lean` pins the surface
  extensionally equal to the library reference `Todo.logical`/`keyedVisible`,
  and the emitted `TodoMVC.mjs` bundle is byte-identical to the previous
  hand-maintained output.
- `Test/Elab/ViewSurface.lean` pins the expanded typed surface end to end
  through `ComponentSpec.check` and `Backend.Component.emit`.
- The `section` element stays out of the surface because `section` is a Lean
  command keyword; `HtmlTag.section` remains available to the explicit API.
  Surface keywords (`state`, `derived`, `event`, `view`, `key`) remain unusable
  as identifiers in scopes that open `LeanRxDsl`, extending the recorded
  ADR-0006 trade-off.
- The logical target is reference-only: it feeds differential tests and golden
  projections, never a shipped renderer, and carries no event bindings.
