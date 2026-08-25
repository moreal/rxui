# ADR-0047: Conditional structure inside keyed rows (edit input vs label)

- Status: Proposed (decision draft)
- Date: 2026-08-25

## Context

The next gap in the ADR-0040 TodoMVC gate list is the row's *structural*
mode switch: a viewing row shows a toggle, a label, and a destroy button; an
editing row shows a text input. The bespoke `Backend.Todo` swaps the branch
subtree on edit/view transitions while retaining the row root, and keeps the
stable branch updated in place. The generic backend's sealed rows (ADR-0041,
0043, 0044, 0046) can change text, class, and fields after mount, but a
row's element structure is fixed at elaboration time. Row scope still cannot
observe component state, so the editing flag must live in a row field, as
TodoMVC's `editing` already effectively does per item.

## Decision (draft)

Adopt a sealed **row branch cell** and reject the alternatives:

1. **Always-mount both branches with class-driven visibility — rejected.**
   ADR-0044/0045 class selections could toggle `display` today, but both
   subtrees stay in the accessibility tree and the DOM (hidden inputs with
   values, doubled delegated cells), the emitter would need a hidden-branch
   convention the safe view deliberately lacks, and the bespoke Todo's
   observable contract (the absent branch does not exist) would silently
   weaken. Visibility is a styling concern, not a structure decision.
2. **Component-level editing outside the region — rejected.** Moving the
   edit input out of the row (one input driven by component state) breaks
   row identity retention during reorder — the retained-input-and-focus
   behavior the TodoMVC browser gate pins — and reopens the sealed-binder
   question by needing the edited row's fields in component scope.
3. **Sealed row branch cell — adopted direction.** A row cell may be a
   two-branch selection mirroring ADR-0044 one level up:
   `{if field == "literal" then <template…/> else <template…/>}` lowers to a
   `RowNode.branch` carrying one row field index, one comparison literal,
   and two statically sealed subtrees. Both branches are fixed at
   elaboration; the branch node occupies exactly one cell position, so the
   ADR-0046 per-kind cell action arrays stay index-stable, with each kind's
   action for that cell drawn from whichever branch binds it (the other
   branch must bind the same or no action for that kind — checked). The row
   mount renders the branch selected by the initial fields; the retained-row
   update callback re-evaluates the predicate, compares it against the
   rendered branch (a compiler-owned marker on the cell node, in the
   `setKey`/`$lrxKey` style), and replaces the cell's subtree only on a
   branch change — the ADR-0043 navigate-and-write shape plus one
   `replaceChild`-shaped host call.

## Open questions the implementation must settle

- Whether `replaceChild` semantics need a new host export or compose from
  existing `append`/removal primitives (the ABI-freeze bar of this round's
  siblings should hold if possible).
- Focus transfer into a newly mounted edit input (the bespoke Todo focuses
  the input on entry; the generic backend has no focus vocabulary yet).
- Whether branch-local delegated bindings may *differ* per branch and kind,
  or must agree exactly — the draft requires agreement to keep the action
  arrays static.

## Confirmation bar

This draft is confirmed (Status → Accepted) when a follow-up round ships the
sealed row branch cell through the generic backend with a browser gate that
mirrors TodoMVC's edit/view transition — enter editing, type through the
ADR-0046 payload, commit, and observe the label branch return with retained
row identity; it is revised instead if the implementation shows the
always-mounted alternative or a new host primitive is unavoidable.
