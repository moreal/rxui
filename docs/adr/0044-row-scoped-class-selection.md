# ADR-0044: Row-scoped static class selection in sealed row templates

- Status: Accepted
- Date: 2026-08-25

## Context

TodoMVC rows toggle `completed`/`editing` classes from row state, and the
ADR-0040 gate list records row-scoped dynamic attributes as a required
capability before `Backend.Todo` can shrink to a driver. ADR-0041 row
templates admit only static attributes, so a row's appearance cannot react to
the row updates ADR-0043 just introduced. Arbitrary dynamic attributes would
reopen the sealed-binder decision (attribute names or values flowing from row
expressions); the gate only needs a selection between statically known
classes.

## Decision

Row elements may carry one sealed **class selection** instead of a static
`class`: `class={if field == "literal" then "a" else "b"}` in the row
template lowers to `RowClassSelect` — a field index, a comparison literal,
and the two class strings, all fixed at elaboration time. The generated row
mount emits `setAttribute(node, "class", item[field+1] === literal ? a : b)`,
and the ADR-0043 retained-row update callback re-emits it on `updateAt`, so
the class tracks row field updates. Both selected values are ordinary static
class strings; the attribute name is compiler-owned; the predicate vocabulary
is exactly equality of one row field against one string literal (`!=` is
written by swapping the branches). A class selection counts as the element's
`class` attribute for duplicate detection (`LRX-VIEW-001`), its field is
bounds-checked (`LRX-VIEW-026`), and any other conditional shape is rejected
at the surface (`LRX-ELAB-116`).

## Consequences and limitations

- The TodoMVC `completed` class becomes expressible: a `String` row field
  holding `""`/a marker plus one selection on the row root, driven by an
  ADR-0043 update action.
- No new host export and no ABI change: `setAttribute` and the conditional
  expression already exist in the validated JS subset; components without
  regions stay byte-identical.
- One selection per element, `class` only, equality against one literal:
  attribute selection for other names (`disabled`, `aria-*`), multi-way
  selection, and predicates over several fields are out of scope until a
  gate needs them. State-scoped (non-row) attribute selection on static view
  elements is a separate future decision recorded in ADR-0045.
