# ADR-0069: Transitive prop re-forwarding needs no new vocabulary

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0068 sealed prop forwarding to one shape — a child prop value may
be one declared immutable prop identifier of the parent — and left its
OQ2 open: a three-level chain, where the forwarded value is itself
received by forwarding (`A` passes a literal → `B` forwards `{p}` →
`C` re-forwards `{q}` → leaf), should work but had no pinned witness.
The two-level NestLab forwarded the root's literal exactly once.

This round surveyed whether re-forwarding requires any pipeline
change. It does not, by construction: `rewriteForwardAttr` resolves
the attr value against the component's *declared prop inventory only*
(`props.idxOf?`), and neither it nor `childElementHead?` ever asks
where the parent's own prop value will come from at runtime — a
literal in the grandparent or a forward from further up produce the
same `propRef% index` rewrite, the same `ChildProp.forward field`
reference, and the same `props[field]` emission. Each level of the
chain reads its own positional mount argument; the chain composes
because every link is locally the ADR-0068 contract.

## Decision

**Adopt the witness, add no vocabulary.** Transitive re-forwarding is
already the composition of per-level ADR-0068 forwards, so the round
extends the NestLab chain by one level and pins the behavior instead
of extending the compiler:

- `Tick` gains a leaf child `Blip` (one `note : String` prop, one
  state, one event — declared before `Tick` in the file, respecting
  the leaf-first elaboration order) and composes
  `<Blip note={label}/>`, re-forwarding the `label` it itself
  receives from `Pulse` by forwarding.
- The generated `Tick.mjs` mounts the leaf with exactly the ADR-0068
  call shape — `$lrx_child_0(node_0, [props[0]])` — pinned in
  `Test/js/nest_artifacts.mjs`; the leaf no-nesting pin moves from
  `Tick` to `Blip`.
- The browser gate pins the three-level flow: `#blip-note` renders
  the root-supplied literal (`"Pulse child"`), the leaf's mount
  return is reachable as `children[0].children[0].children[0]` from
  the root disposer (ADR-0066/0067 republication per level), and root
  disposal removes the leaf's DOM while freezing its counters without
  erasing that reachability.

## Consequences

- No compiler, host, or ABI change: the diff is the example, its
  build entry, and the gates. Every module outside the nest bundle is
  byte-identical; the benchmark bundle and its size gate stand.
- The nest bundle grows one module (`Blip.mjs`); `Tick.mjs.manifest`
  gains `child-components` and the `./Blip.mjs` host import, exactly
  as `Pulse`'s did at ADR-0067 — the manifest shape of "module that
  composes a child" is now witnessed at two chain positions.
- Depth is now argued inductively: the elab pin shows the
  re-forwarding reference (`("note", .forward 0)`) is byte-for-byte
  the shape of a first-level forward, so a chain of any length is a
  stack of witnessed links; no deeper lab is warranted.
- ADR-0068 OQ2 is discharged. The remaining prop boundary is
  reactivity alone (ADR-0068 OQ1): constants flow any depth, signals
  do not cross mounts.

## Open questions

1. **Reactive child props stay rejected by construction** (carried
   from ADR-0068): live parent→child data flow needs a subscription
   contract across the mount ABI, not a `ChildProp` relaxation.
2. **Fan-out re-forwarding is unwitnessed.** One parent forwarding
   the same received prop into two different children (`<Blip
   note={label}/> <Blop tag={label}/>`) should also be the plain
   composition of ADR-0068 links — each child table entry carries its
   own `.forward` index — but no lab pins two forwards from one
   receiving component.
