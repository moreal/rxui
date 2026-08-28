# ADR-0075: Per-row child composition through the row dispose callback

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0072 sealed row templates against child composition with `LRX-ELAB-131`
and left one open question: per-row composition was "unsupported, not
unsupportable", pending a survey of the lifecycle it would need. This round
ran that survey against the generated code and the region host, and found
every hook already in place:

- **Lifecycle.** Every row removal path already funnels through the host's
  `disposeItem(handle, key, context?)` callback — the reconcile (`update`),
  `removeAt`, and the region's own `dispose` — and the generated dispose
  callback was a no-op placeholder. The component backend emits no
  `swapAt`/`removeAt` calls of its own: `remove`, `removeIf`, `trim`, and
  hydration all mark the region dirty and reconcile, and `swapAt` retains
  handles with their keys, so `disposeItem` is the complete removal story.
- **Mount.** A child's `mount(parent, props)` appends its one root element
  at call time, so mounting inside the row build preserves document order
  and the structural `childAt` navigation and delegated cell-action arrays
  (one DOM node per template cell) without a wrapper — the ADR-0039 shape
  in row scope.
- **Props.** The immutable-prop contract (ADR-0042/0068, OQ1 rejection)
  says props are mount-time constants. Row fields are *row-mount* constants
  exactly when no writer exists: a field rewritten by a row event stage, a
  key-branch arm, or a region broadcast diverges from a mounted child's
  prop on the first `updateAt`, silently. The writer set is fully static.
- **Instrumentation.** ADR-0066's `disposer["children"]` is a static array
  published once; a per-row set needs a live inventory.

## Decision

**Seal per-row composition on the narrowest coherent surface; keep
everything else rejected.** Inside a sealed row template, at most one
self-closing capitalized head whose checked `{name}_spec` is in scope
lowers to the new `RowNode.child` (never the template root, never inside a
two-branch cell). Its props must match the child's declared names and order
(`LRX-ELAB-112`) and each value is a `RowChildProp`: a string literal or
the bare projection of one declared row field. The model check rejects
projecting any field a row event stage or broadcast rewrites
(`LRX-VIEW-045`) — the ADR-0068 OQ1 boundary restated per row: a row child
prop is a row-mount constant, provably never divergent. The child's own
template must carry no static `id` (`LRX-ELAB-135`, evaluated from the
child spec like the prop names) because row instances are unbounded.

Codegen (no host change, ABI stays 17):

- The row template's child joins the component child table (one aliased
  import serves view and row scopes, deduplicated by name). The row mount
  callback calls `$lrx_child_k(cell, [item[i+1] | "lit"])` at its cell
  position, stashes the mount return on the row root as `$lrxRowChild`
  (the `$lrxKey`/`$lrxBranch` convention), and pushes it into the live
  inventory.
- The row dispose callback — reached by every removal path — splices the
  stash out of the inventory when a context rode the call and then invokes
  it. The region's own `dispose` passes no context; by then the whole
  component is going away, and the inventory keeps its disposed entries
  exactly as the static ADR-0066 array does after a root dispose.
- The live inventory is one mount-scope array seeded with the static child
  mount returns in declaration order; each child-composing region's record
  carries it in its last slot (behind the count and filter slots), the
  commit sweep passes that slot as the `update`/`updateAt` context instead
  of `null`, and the disposer republishes the same array on `children` —
  the ADR-0066 reachability contract with the array identity fixed at
  mount and only its contents live: static children first, then mounted
  rows' children in mount order.
- The manifest gains the `row-child-components` feature; modules without a
  row child emit byte-identical code throughout.

The lab is NestLab's roster: a fourth `origin` field (written by no row
event) forwarded into a per-row `<Chip tag={origin}/>` — four `Chip`
instances total through one import, per-row state isolation, inventory
tracking across append/remove/re-append, and frozen-counter reachability
after root dispose, pinned by the derived artifact gate and browser spec.

## Consequences

- The witness set covers each conflict axis: `ChildInRegionRow` (children
  on the head, `LRX-ELAB-131`), `RowChildComposedProp` (composed value,
  `LRX-ELAB-131`), `RowChildTwoPerRow` and `RowChildInBranch`
  (`LRX-VIEW-045`), `RowChildWrittenField` (the immutable-prop boundary,
  `LRX-VIEW-045`), `RowChildStaticId` (`LRX-ELAB-135`).
- `LRX-ELAB-131` narrows from "no composition in rows" to "composition
  outside the sealed row surface"; the spec'd-head misuse map stays
  112 (names/order), 130 (spec-less forwarding), 131 (row surface),
  132 (misshapen reference), 133 (spec-less children).
- Delegated events need no carve-out: a click inside a row child resolves
  the child's own cell, whose action entry is `""`, so the region
  dispatcher ignores it while the child's own listener fires.
- Region metrics are untouched — child mounts/disposes ride the child's
  own instrumentation, reached through the live `children` inventory.

## Open questions

1. **Transitive static-id checking.** `LRX-ELAB-135` walks only the
   composed child's own template; a grandchild with a static id slips
   through. Extend the evaluated predicate transitively only if a lab
   actually composes an id-free wrapper around an id-carrying leaf.
2. **Multiple children per row / children in multiple regions.** The
   one-per-template bound is a sealing choice, not a structural limit —
   the stash and splice generalize to a list. Revisit with a consumer.
