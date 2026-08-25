# ADR-0047: Conditional structure inside keyed rows (edit input vs label)

- Status: Accepted
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

## Decision

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
3. **Sealed row branch cell — adopted.** A row cell may be a two-branch
   selection mirroring ADR-0044 one level up:
   `{if field == "literal" then <template…/> else <template…/>}` lowers to
   `RowNode.branch` carrying one row field index, one comparison literal,
   and two statically sealed subtrees. Branch cells sit only directly under
   the row root and never nest (`LRX-VIEW-034`, enforced by the depth rule),
   and both subtrees are sealed template elements fixed at elaboration.

The implementation settled the draft's open questions as follows.

**Replacement composes from existing primitives — no host export, ABI 15
unchanged.** The branch cell mounts as one wrapper `span` holding the
selected subtree, so the cell keeps exactly one row-root child index and the
ADR-0046 per-kind cell action arrays stay index-stable. The emitter shares
one builder function per branch
(`$lrx_region_{r}_branch_{b}_t`/`_f`) between the row mount conditional and
the update callback; the retained-row update callback re-evaluates the
predicate against the wrapper's compiler-owned `$lrxBranch` marker property
(written through the existing `setProperty` export, in the `setKey`/
`$lrxKey` style), updates the stable branch in place by ADR-0043
navigate-and-write, and on a branch change performs one
`detach(childAt(cell, 0))` plus one `append(cell, freshBranch)` — `detach`
was already exported by `runtime/leanrx_region.mjs` for the region hosts, so
no new host export and no runtime ABI bump were needed. Components without
branch cells emit byte-identical modules, manifests, and graphs.

**Cross-branch delegated bindings must agree per kind and cell.** The
delegated action arrays are static, so for each branch cell and delegated
kind both branches must bind the same row event, or the unbound branch must
be statically unable to originate that kind: a one-branch `click` binding is
always rejected (any content of the other branch bubbles a click into the
cell), a one-branch `input` binding requires the other branch to contain no
`input` element, and a one-branch `keydown` binding requires it to contain
no `input` or `button` element (the only focusable tags in the sealed
template whitelist). All violations report `LRX-VIEW-034`. A typed row
event still must be bound exactly once in the whole template
(`LRX-VIEW-033`), so a payload-taking event lives in exactly one branch.

**Row value reflection reuses the WHATWG equal-value caret no-op.** A row
`input` may reflect one sealed row expression into its `value` property
(`RowReflect`, surface `value={draft}`; inputs only, at most one per
element, `LRX-VIEW-035`). The reflection writes at branch mount and in the
stable-branch update arm; a row update driven by the input's own delegated
payload writes back the string the input already holds, and the WHATWG
equal-value assignment preserves the caret — the ADR-0038 controlled-input
finding reused in row scope. This lets the edit branch open pre-filled with
the current draft.

**Focus transfer stays a recorded gap.** The generic backend still has no
focus vocabulary, so entering the edit branch does not focus the fresh
input the way the bespoke Todo does; ADR-0048 records the decision draft.

## Confirmation

Confirmed by the Branch Lab round: the sealed branch cell ships through the
generic backend (`RowNode.branch` → wrapper cell, builder functions, marked
replacement), and the Branch Lab browser gate mirrors TodoMVC's edit/view
transition — enter editing, type through the ADR-0046 payload with the
caret preserved mid-text, commit, and observe the label branch return with
retained row identity (the same `li` node) and update-only region
instrumentation. Neither rejected alternative was needed: no always-mounted
branch and no new host primitive.
