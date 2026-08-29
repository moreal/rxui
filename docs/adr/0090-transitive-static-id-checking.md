# ADR-0090: The static-id rule reads a recorded trail, not a resolved name

- Status: Accepted
- Date: 2026-08-29

## Context

`LRX-ELAB-135` (ADR-0075) rejects composing a child into a sealed row
template when the child's template carries a static `id`: a row mounts
one instance per row, rows are unbounded, so one `id` becomes many. The
check is `componentViewHasStaticId`, an elaboration-time
`Meta.evalExpr` of `{name}_spec.viewHasStaticId` — and `View.hasStaticId`
walks *one* template. A `View.child` node is a name string; the walk
stops there. A grandchild with an `id` slipped through from the day the
rule was written (ADR-0075 OQ1), and ADR-0089 widened the gap by
arithmetic: a row now composes any number of children, so one row opens
as many unchecked templates as it has references.

The obstacle is scope, not effort. `ComponentSpec.children` carries
names (`ChildComponent.name`, `moduleSpecifier`). To answer transitively
at the row's elaboration site, something has to turn the string
`"Chip"` back into `Chip_spec` — and nothing guarantees that identifier
resolves *there*. The parent imports the module that declares its own
child; it need not see, or even be able to name, what that child
composes. In Nest Lab it happens to work (one file); the contract cannot
be written on that accident.

## Decision

**The child table records the answer instead of re-deriving it: each
entry carries the trail its own elaboration computed, and the row rule
reads it.** `LRX-ELAB-135` is extended, not replaced.

Three routes were compared:

- **(a) Recursive resolution at the row site.** Evaluate the child's
  spec, take `spec.children`, resolve each `{name}_spec` from the
  parent's elaboration scope, recurse. Rejected: the resolution can
  fail, and both failure behaviors are wrong. Failing open reinstates
  the hole silently and makes acceptance depend on which modules the
  *parent* happened to open — the same program compiles or not by an
  unrelated `import`. Failing closed rejects correct programs for the
  same reason. A rule whose answer depends on the caller's namespace is
  not a contract.
- **(b) Derived information on the spec, read from the child spec.**
  Compute the answer where it is computable — at the reference site
  inside the *child's* own `component` command, the one place
  `{grandchild}_spec` is guaranteed in scope, because that is exactly
  the condition under which the reference became a `View.child` at all
  (`resolvesToComponentSpec`). Store it; read it one level up. **Chosen.**
- **(c) Lift the check into the model layer.** `ComponentSpec.check`
  would reject the row reference, moving the diagnostic from
  `LRX-ELAB-135` to a `LRX-VIEW-*` code. This requires (b) first —
  `spec.children` must carry more than a name — and then buys nothing
  the elaborator does not already have, while losing the precise
  syntactic span the row head reports today. Not taken; (b) leaves it
  open, since the trail is on the spec and a model-layer consumer could
  read it unchanged.

The stored answer is a *trail*, not a flag: `ChildComponent.idTrail :
List String` is the chain of component names from that child down to the
first component in its mounted tree that carries a static `id`, empty
when the tree is clean. A flag would have sufficed for the rejection;
the trail costs one list and lets the diagnostic name the path, which is
the difference between "`Cuff` is bad" and "`Cuff → Chip` is where the
`id` is".

`ComponentSpec.staticIdTrail` folds three sources, because all three
mount when one instance of the component mounts:

- its own view (`View.hasStaticId`, unchanged);
- the row template of every region it declares (`RowNode.hasStaticId`,
  new — a region instantiates its template once per row, so an `id`
  there is the same unbounded duplication one level in);
- every entry of its child table, through the stored trail.

Own-template answers name the component alone (`["Badge"]`); a child's
answer extends its stored trail (`["Cuff", "Chip"]`), first non-empty
entry winning. The recursion terminates in stored data, so depth is free
and no consumer ever resolves a name it holds only as a string.

`lowerRowChildRef` evaluates `staticIdTrail` where it evaluated
`viewHasStaticId`, and branches on the trail's length: a one-element
trail keeps ADR-0075's message verbatim, a longer one reports the path.
Both are `LRX-ELAB-135`.

**Why extend the number rather than mint one.** The rule is unchanged —
"a row-composed child must not mint document ids" — and so is the
repair: use classes. Only the *location* of the offending attribute
differs, and the author acts identically either way. A second code would
split one contract by an accident of where the id sits, and would have
to be explained in terms of the first. The spec'd-head misuse map stays
112 / 130 / 131 / 132 / 133 / 135. The two branches are pinned apart by
message rather than by code, the way ADR-0081 pins the `LRX-TYPE-117`
branches.

**The hole that stays open, stated.** The check fires on *composed
children* only. A component's own region row template may still carry a
static `id` and nothing rejects it — `<li id="row">` in a region
duplicates across rows exactly as an id-carrying row child would. The
line is deliberate and is ADR-0071's: the compiler polices templates the
author is *not* looking at — a child module's tree, reached by name,
possibly written by someone else — and leaves ids in the template under
the cursor to the author and the axe `duplicate-id` gate, which catches
the collision where it matters. The asymmetry is visible in
`staticIdTrail` itself, which folds a component's own region templates
when answering *for a composer* but is never consulted about the
top-level component. Closing it needs its own diagnostic and its own
fixture.

The witness is Nest Lab's roster, promoted one level: the row composes
`<Cuff mark={origin}/>`, and `Cuff` composes `<Chip tag={mark}/>`. Every
row now opens two templates; the row-mount constant is forwarded one
level further, so `.cuff-mark` and the nested `.chip-tag` render the same
`origin`; and the per-row leaf is reachable as
`children[1 + i].children[0]`, one hop behind the inventory entry. The
row lowering admits it by reading `Cuff`'s recorded `[]`, never resolving
`Chip` — which the generated `NestLab.mjs` confirms by not importing
`Chip.mjs` at all. The same child table holds the contrast: `Pulse`,
composed in the view beside the region, answers `["Pulse"]` for its
`id="pulse-title"` and would be rejected in row scope. No host change;
runtime ABI stays 17.

## Consequences

- No codegen change: every generated module in every bundle is
  byte-identical across the change, including Mix Lab's row children and
  the benchmark, so the size gate and every manifest stand
  unre-measured. The Nest Lab bundle differs only because its source
  did — the four unchanged modules' `.mjs` files are byte-identical and
  only their `graphHash` moves, with the source lines the new component
  shifted.
- `ChildComponent` gains one field and `ComponentSpec.viewHasStaticId`
  is gone, replaced by `staticIdTrail`. The elaborator evaluates the
  trail once per child-table entry, beside the prop-names evaluation it
  already ran there.
- The compile-fail set gains `RowChildNestedStaticId` (an id-free
  `Frame` wrapping an id-carrying `Badge`), pinned on the transitive
  message so it cannot collapse into the direct branch.
  `RowChildStaticId` is unchanged and still reports ADR-0075's wording.
- `Test/Component/Model.lean` pins the fold branch by branch on forged
  specs — clean leaf, id leaf, wrapper, wrapper of wrapper, masked
  sibling, region row template — so the transitivity is a model fact,
  not only an elaboration one. `Test/Elab/Component.lean` pins Nest
  Lab's table holding both answers at once.
- ADR-0075 OQ1 and ADR-0089 OQ1 are closed.

## Open questions

1. **A component's own row template can still carry a static `id`.**
   The rule polices composed children only, by the choice above. A
   region whose template carries an `id` duplicates it per row with no
   diagnostic; only the axe gate sees it. Closing it means a new
   diagnostic number on the region validation, not an extension of
   `LRX-ELAB-135`.
