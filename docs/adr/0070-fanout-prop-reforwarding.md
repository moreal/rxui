# ADR-0070: Fan-out prop re-forwarding needs no new vocabulary

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0069 sealed transitive re-forwarding — a chain of forwards is the
per-level composition of ADR-0068 links — and left its OQ2 open: one
receiving component forwarding the same received prop into *two*
different children should also be plain composition, but no lab
pinned two forwards from one receiving component. The gap was wider
than the forwarding question alone: multi-static-child composition
itself was unwitnessed — the NestLab root composes one `Pulse`, and
`Pulse` and `Tick` each compose exactly one child — so every
`disposer["children"]` array in the tree had length one and every
child table had one entry.

This round surveyed whether fan-out requires any pipeline change. It
does not, by construction: the elaborator collects capitalized child
heads into `ComponentSpec.children` in first-occurrence order
(deduplicated by name), the backend allocates one aliased import
(`$lrx_child_{index}`) per table entry and one `child_off_{n}` per
reference in document order, each reference carries its own
`ChildProp` list so two `.forward 0` entries are independent reads of
the same positional mount argument, and the ADR-0066 republication
emits the whole `childOffs` list — `disposer["children"] =
[child_off_0, child_off_1]` — in declaration order. Nothing in the
pipeline assumes one child anywhere.

## Decision

**Adopt the witness, add no vocabulary.** Fan-out composition and
fan-out re-forwarding are pinned by one witness — a second leaf in
the three-level NestLab chain:

- `Tick` gains a second leaf child `Chip` (one `tag : String` prop,
  one state, one event — declared next to `Blip`, respecting the
  leaf-first elaboration order) and fans out
  `<Blip note={label}/>, <Chip tag={label}/>` — the same received
  `label` forwarded twice.
- The elab pin fixes the scaled shapes: child table
  `["Blip", "Chip"]`, references `[("Blip", [3]), ("Chip", [4])]`,
  forwards `[[("note", .forward 0)], [("tag", .forward 0)]]`.
- `Test/js/nest_artifacts.mjs` pins the generated `Tick.mjs`: two
  aliased imports, two `[props[0]]` mount calls, and
  `disposer["children"] = [child_off_0, child_off_1]`; the leaf
  no-nesting pin now covers both `Blip` and `Chip`.
- The browser gate pins the fan-out flow: both leaves render the
  root-supplied literal (`"Pulse child"`), the sibling is reachable
  as `children[0].children[0].children[1]`, the two leaves' states
  are mutually independent (a Chip transaction commits in its own
  state array; neither the sibling nor the parent traces a commit),
  and root disposal freezes both leaves' counters without erasing
  reachability.

## Consequences

- No compiler, host, or ABI change: the diff is the example, its
  build entry, and the gates. Every module outside the nest bundle is
  byte-identical; the benchmark bundle and its size gate stand.
- The nest bundle grows one module (`Chip.mjs`); `Tick.mjs.manifest`
  keeps its feature list and gains the `./Chip.mjs` host import —
  the manifest's `hostImports` is now witnessed with two child
  specifiers in first-occurrence order.
- Width now composes with depth: ADR-0069 argued arbitrary chain
  depth inductively from one witnessed link, and this witness shows
  the per-level step also scales in width (n children are n
  independent table entries), so arbitrary static trees of forwards
  are covered by the two witnesses together; no wider lab is
  warranted.
- ADR-0069 OQ2 is discharged. The remaining prop boundary is
  reactivity alone (carried since ADR-0068 OQ1): constants flow any
  depth and width, signals do not cross mounts.

## Open questions

1. **Reactive child props stay rejected by construction** (carried
   from ADR-0068): live parent→child data flow needs a subscription
   contract across the mount ABI, not a `ChildProp` relaxation.
2. **Repeated composition of the same child is silently deduplicated
   at the spec level but not at the reference level.** The child
   table dedups by name while `childRefs` keeps every occurrence, so
   `<Blip note={label}/>, <Blip note={label}/>` would mount one
   module twice through one import. That shape is plausible and
   probably already works, but no lab pins two references to one
   table entry.
