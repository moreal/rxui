# ADR-0066: Child instrumentation reachability through the parent disposer

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0039's phase-1 composition left one sentence as future work — "the
child's instrumentation is not reachable through the parent disposer" —
and every round since has re-carried it as an invariant rather than a
decision. This round decides it on the reachability axis. The survey
covered the whole disposer path of `<Child/>` composition as generated
today:

**One lab composes children.** `NestLab` is the only component with a
`View.child` reference (`<Pulse title="…"/>`); `EchoLab`, despite
sharing the component-lab gates, is a single component with no child
table, and no other example or bench source contains a capitalized
child head. The js-framework-benchmark bundle in particular composes
nothing — `"child-components"` appears in exactly one manifest pin,
NestLab's — so any change gated on the child table leaves the frozen
benchmark bytes untouched by construction.

**Where the path breaks.** The parent's generated mount calls each
child mid-mount — `const child_off_0 = $lrx_child_0(node_0, ["Pulse
child"]);` — and that child mount return is the child's entire public
surface: the dispose closure carrying `instrumentation()`,
`regionInstrumentation()`, and `gridInstrumentation()`. Today it joins
the parent's `makeDisposer` listener list and nothing else. Disposal
therefore chains correctly (the host splices the list and calls each
entry, and the child's own `disposed` flag keeps the second parent
dispose a no-op), but the handle itself is captured only in the mount
closure: no consumer can reach the child's counters at any point, and
after the parent disposes, the splice has emptied even the array that
held it.

**What generated code can and cannot spell.** The JS AST has no
function expression — `Expr` is ident/literal/unary/binary/conditional/
call/array/index, and functions exist only as top-level declarations,
which cannot close over mount-locals. So the natural-looking join, a
`childInstrumentation()` accessor aggregating child snapshots, is not
representable in generated code; attaching it in the host would extend
`makeDisposer`'s surface, and new host surface means an ABI bump
(ADR-0028 precedent) — both outside this round's freeze constraints.
What *is* representable is `Stmt.assign` with an index target: a
property assignment publishing an array of mount-local identifiers.

**Why merging counters is rejected regardless.** The other join
convention — folding child transaction counters and disposal counts
into the parent's ten-slot metrics array — fails on contract grounds
before representability: parent and child run genuinely separate
transactions over separate state arrays (the point of ADR-0039 phase
1), the exact-count pins across the counter/diamond/echo gates read
parent-only semantics from those slots, and ADR-0039 fixed manifest
counts as parent-only. An aggregate would be a second, divergent
counting contract wearing the first one's array shape.

## Decision

**Adopt reachability, not aggregation, as the one contract: the parent
disposer's `children` property holds the child mount returns in
child-declaration order.** Concretely, a module whose child table is
non-empty emits exactly one statement between the disposer construction
and the return:

```js
const disposer = makeDisposer(node_0, [child_off_0, …], tx, [region_0]);
disposer["children"] = [child_off_0];
return disposer;
```

- The host is unchanged and the runtime ABI stays 17: `makeDisposer`
  still attaches only its three accessors, and the composition layer —
  the generated parent module, which already owns the import and the
  mid-mount call — owns the republication.
- Every instrumentation facet joins at once, because the array element
  *is* the child's mount return: `children[i].instrumentation()`,
  `children[i].regionInstrumentation()`, and — for a future
  grandchild — `children[i].children` compose transitively with no
  further vocabulary.
- The property survives disposal by construction: the parent's dispose
  splices its listener array, but the `children` array is a separate
  reference, so post-dispose inspection reads the child's frozen
  counters — the disposal evidence the gap was about.
- Republishing the child disposer also republishes the ability to
  dispose the child early. That is an affordance, not a new contract:
  the child's mount return is already the child module's public ABI for
  whoever mounts it, the child's `disposed` flag already makes any
  call idempotent, and per the ADR-0065 invariant the dispatch/dispose
  layer stays the only contract — the parent adds reachability, not
  semantics.

The aggregating accessor and the counter merge are rejected as
recorded in the context; no `childInstrumentation`, no summed slots,
and no host helper are introduced.

## Consequences

- `LeanRx/Backend/Component.lean` emits the assignment iff
  `dom.childOffs` is non-empty, so every module without child
  composition — including the whole benchmark bundle — is
  byte-identical, and all manifests (NestLab's included) are unchanged.
  The only generated diff in the repository is one line in
  `NestLab.mjs`.
- `Test/js/nest_artifacts.mjs` pins the emitted line.
  `Test/browser/nest.spec.mjs` gains the reachability gate: after one
  Pulse click, `nestDispose.children` has length one and the child's
  trace holds exactly one `transaction:commit`; after the parent
  disposes, the same handle still answers and a synthetic click on the
  detached child button changes nothing — the full ten-slot snapshot is
  equal before and after, pinning that parent disposal froze the
  child's instrumentation.
- ADR-0039's future-work sentence is discharged: the composed-
  instrumentation surface is this `children` property, and rounds no
  longer carry the gap as an invariant.

## Open questions

1. **Transitivity is untested until a lab nests two levels.** The
   contract composes to grandchildren by construction, but no example
   mounts a child that itself composes; a multi-level lab would pin
   `children[i].children` the day parent→child props (ADR-0039's later
   phases) make one worth writing.
2. **Aggregation stays rejected until a consumer exists.** If a gate
   ever needs whole-tree totals, the summing belongs in the consumer
   walking `children`, not in a second counting contract in the
   generated module or the host.
