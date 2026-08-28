# ADR-0067: Transitive child composition through per-level republication

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0066 adopted the parent disposer's `children` array as the one
reachability contract but left OQ1 open: transitivity was untested
because no lab mounted a child that itself composes. This round
surveyed the whole two-level path and closed the question by
execution.

**The survey found no level-1 special cases.** Every stage of the
`<Child/>` pipeline is component-generic rather than root-component-
specific: the elaborator collects capitalized heads into the child
table wherever a `{Name}_spec` resolves in scope (the same
`collectComponentHeads` walk runs for `Pulse`'s view as for
`NestLab`'s), the ADR-0042 prop check evaluates the referenced spec's
`propNames` regardless of nesting depth, the LRX-VIEW-023/024
validations read only the component's own child table, and the backend
mounts each child through an aliased import — `import { mount as
$lrx_child_0 } from "./Tick.mjs"` — so a module that both exports
`mount` and imports a child's `mount` never collides. The ADR-0066
emission itself is keyed on `dom.childOffs`, which any child-composing
module populates. Nothing in the path knows whether the module being
emitted is a root or somebody's child.

**What two levels actually require.** The grandchild's `_spec` must be
elaborated before the child that references it (same-file declaration
order, the existing convention), the same-directory `./{Name}.mjs`
specifier rule applies per level, and props stay sealed literals at
each mount site — `Pulse` passes `label="Tick child"` as its own
literal; forwarding the parent's prop into the grandchild remains
ADR-0039's unimplemented later phase and is out of scope here.

## Decision

**Adopt no new vocabulary: transitive reachability is the ADR-0066
republication applied independently at every child-composing level,
and the composed surface is the `children[i].children[j]…` path.**
NestLab is the pinned witness: `Tick` (state, one event, one immutable
prop) is composed by `Pulse`, which is composed by `NestLab`, so the
generated `Pulse.mjs` — an intermediate module — carries the full
child-composing shape (aliased import, mid-mount `$lrx_child_0(node_0,
["Tick child"])`, the child offset in its `makeDisposer` list, and
`disposer["children"] = [child_off_0]`) while remaining itself a
mountable child. The root disposer reaches the grandchild as
`children[0].children[0]`, every instrumentation facet rides along
because each array element *is* a mount return, and root disposal
chains through both levels while freezing the grandchild's counters
without erasing the path.

## Consequences

- No compiler, host, or ABI change: the diff is the NestLab example
  (a `Tick` component and one `<Tick label="…"/>` element in `Pulse`),
  its build registration, and the gates. Every module outside the nest
  bundle — the benchmark bundle included — is byte-identical, and no
  manifest outside the nest bundle changes.
- Inside the bundle, `Pulse.mjs` gains the child-composing shape,
  `Pulse.mjs.manifest.json` gains `child-components` and the
  `./Tick.mjs` host import, `Tick.mjs` and its manifest/graph are new,
  and `NestLab.mjs` stays byte-identical (its manifest moves only by
  graph-span offsets).
- `Test/js/nest_artifacts.mjs` pins the intermediate module's aliased
  grandchild import, mount call, and republication line, and moves the
  no-nesting pin to the leaf (`Tick.mjs`). `Test/browser/nest.spec.mjs`
  gains the transitivity gate: after one Tick click,
  `children[0].children[0].instrumentation()` shows exactly one
  `transaction:commit` while the intermediate child shows zero (state
  arrays stay separate across levels); after the root disposes, the
  grandchild's DOM is detached, a synthetic click changes nothing, and
  the ten-slot snapshot is frozen — reachability survives two levels
  of disposal.
- ADR-0066 OQ1 is discharged; rounds no longer carry grandchild
  reachability as an open question.

## Open questions

1. **Prop forwarding stays the boundary.** A parent cannot yet thread
   its own prop or state into a child's prop; when ADR-0039's later
   phases open that path, the two-level lab is the natural place to
   pin its transitive form.
2. **Tree aggregation stays with the consumer (ADR-0066 OQ2).** The
   transitivity gate walks `children` explicitly; no summed counters
   were added at either level.
