# ADR-0089: A row template composes a list of children, not one

- Status: Accepted
- Date: 2026-08-29

## Context

ADR-0075 sealed per-row child composition on the narrowest coherent
surface and admitted, in its own second open question, that the
one-per-template bound was "a sealing choice, not a structural limit —
the stash and splice generalize to a list. Revisit with a consumer."

The bound lived in exactly one place: `validateChildComponents` rejected
`rowRefs.length > 1` with `LRX-VIEW-045`. Nothing downstream depended on
it. The elaborator already collects *every* row-scoped head into the
child table (deduplicated by name, so a repeat costs one import), the
row mount statements already emit one `$lrx_child_k(cell, […])` plus one
`context["push"]` per reference at its own cell position, and `RowDom`
already carried `childOffs` as a list. Only two emissions assumed a
single entry: the row root's `$lrxRowChild` stash, written once per
`childOffs` entry so a second would overwrite the first, and the dispose
callback, which read that one stash and called it.

The consumer arrived: Mix Lab wanted a row that carries both a badge and
a stamp, and the same stamp twice.

## Decision

**A row template composes any number of children; the stash is a list
and the dispose callback is a loop.** The arity arm of `LRX-VIEW-045`
retires with no replacement bound and no new diagnostic number.

Inventory and lifecycle, generalized:

- **Mount order.** Each row-scoped reference mounts where it sits in the
  template, in traversal order: `const row_child_k = $lrx_child_j(cell,
  […]); context["push"](row_child_k);`. A child's `mount` appends its one
  root at call time, so document order, the structural `childAt`
  navigation, and the delegated cell-action array all stay the ADR-0039
  shape — a row with three children simply has three more cells, and the
  action array grows three `""` entries. The row's entries therefore
  enter the shared `childInventory` as one contiguous run in template
  order, appended after every earlier row's run.
- **The stash is a list.** The row root carries
  `row["$lrxRowChild"] = [row_child_0, …, row_child_n]` — one assignment
  of an array literal, replacing ADR-0075's one assignment per entry
  (which, at n > 0, silently kept only the last). A row template with no
  child emits no stash at all, so child-free modules are byte-identical.
- **Dispose is one loop.** `for (const row_child of row["$lrxRowChild"])`
  splices each entry out of the context by `indexOf` and then invokes it.
  The loop body is ADR-0075's body verbatim, so the callback's shape no
  longer depends on the template's arity: a single-child region is now
  the one-element case, not a shape of its own.
- **Why the splice touches no neighbour.** A mount return is a fresh
  closure per instance, so `indexOf` is identity lookup on a value no
  other entry can equal — including between two references to the *same*
  child module in the same row, whose two mount calls return two distinct
  functions. Splicing one element shifts later entries left without
  removing them, and the loop re-reads `indexOf` for each remaining
  entry, so the shifts never desynchronize the run being removed.
  Contiguity of a row's run is preserved by both operations (push at the
  end, splice of a whole run) but nothing depends on it — the argument is
  by identity alone, which is what also makes the two child-composing
  regions of ADR-0077 safe against each other.
- **Repeat versus difference.** Two references to different components
  are two entries in the child table and two aliased imports; two
  references to the same component are one table entry and one import
  (ADR-0071's dedup, already row-aware) with two `RowChildProp` lists,
  two `row_child_k` bindings, and two independent states. Nothing in the
  stash, the inventory, or the splice distinguishes the two cases.

**No new upper bound.** A cap would have to be arbitrary: the references
are template-static, so their count is fixed at compile time and bounded
by the source; the per-row costs are one mount call, one push, and one
array literal slot each; and the removal cost is O(children × inventory)
by the same `indexOf` the one-child case already paid. There is no
resource the second child threatens that the first did not.

`LRX-VIEW-045` keeps every other arm unchanged — the row-template root
position, the two-branch-cell placement, an out-of-bounds projected
field, and the written-field boundary (a row event stage, a key-branch
arm, or a region broadcast) — and `LRX-ELAB-112`/`131`/`135` are
untouched. The compile-fail fixture that targeted the retired arm,
`RowChildTwoPerRow`, moves out of `Test/fixtures/compile-fail` and its
shape moves *into* the lab: two references to one child module in one
row template is now a witness, not a rejection.

The lab is Mix Lab's `crew` region: `<Badge tag={tag}/>`,
`<Stamp mark={label}/>`, `<Stamp mark="crew stamp"/>` — three children on
one row, covering difference and repeat at once, projecting two
never-written fields and one literal. `pins` keeps its single child, so
one component holds a one-child and a three-child region against the same
mount-scope inventory. No host change; runtime ABI stays 17.

## Consequences

- The generated dispose callback got shorter and arity-independent; the
  generated row callback got one array literal. Modules with no row child
  are byte-identical, so the benchmark size gate and every manifest stand
  unre-measured.
- The browser witness observes the inventory after each lifecycle event a
  run of three can be desynchronized by: removing a *middle* row splices
  exactly its own run and leaves both neighbours' identities and order
  intact (`[0,1,2,3,7,8,9]`), a broadcast retains every key and touches no
  entry, the next reconcile appends the new row's whole run behind the
  survivors, all three of the removed row's children are disposed (not
  just the first), and the survivors stay live.
- The model-level lift has a Lean witness too: `Test/Elab/Component.lean`
  now checks Mix Lab's deduplicated child table (`Badge`, `Stamp` — two
  names for three references) and both regions' `childRefs` lists in
  template order with their own prop lists.
- The cross-region interleaving gate now pins entries rather than rows:
  `[static, pin, crew badge, crew stamp, crew stamp, pin]`, each told
  apart by its own commit count.
- ADR-0075 OQ2 is closed. OQ1 (transitive static-id checking) stays open
  and is now slightly more likely to matter: a row that composes several
  children composes several templates that `LRX-ELAB-135` checks only one
  level deep.

## Open questions

1. **Transitive static-id checking** (ADR-0075 OQ1, unchanged). A
   grandchild with a static `id` still slips through the evaluated
   predicate. Extend it transitively when a lab composes an id-free
   wrapper around an id-carrying leaf.
