# ADR-0071: Repeated composition of the same child needs no new vocabulary

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0070 sealed fan-out re-forwarding and left its OQ2 open: the
child table deduplicates by name while `childRefs` keeps every
occurrence, so one parent composing the same child module twice
would mount one module twice through one import — plausible, probably
already working, but unwitnessed. Every reference-to-table
relationship in the tree was still one-to-one.

This round surveyed whether repeated composition requires any
pipeline change. It does not, by construction: the elaborator's
`childNames.contains` guard dedups only the table entry (and
therefore the emitted import and the manifest's `hostImports`
specifier), while the jsx lowering keeps one `View.child` reference
per occurrence, each carrying its own `ChildProp` list; the backend's
`mountChildren` resolves every reference through `childMounts.find?`
to the one aliased import and allocates an independent
`child_off_{n}` per reference, and the ADR-0066 republication emits
the whole `childOffs` list. Two references to one table entry are
therefore one import, two mount calls with independent prop arrays,
and two disposer entries — and since each `mount` call builds its own
state array, the two instances are fully independent at runtime.

One witness-shape hazard surfaced (anticipated in the round
directive): the `Chip` template carried static ids
(`chip-tag`/`chip-text`), which two instances would duplicate —
an axe `duplicate-id` violation and ambiguous selectors. That is a
property of the example template, not of the pipeline; the leaf
template switches to classes (`.chip-tag`/`.chip-text`).

## Decision

**Adopt the witness, add no vocabulary.** Repeated composition is
pinned by giving `Tick` a second `Chip` reference with a different
prop shape — `<Chip tag={label}/>, <Chip tag="fixed chip"/>` — so
one witness pins both the shared import and the per-reference
independence of the prop lists (one `.forward 0`, one literal):

- The elab pin fixes the dedup split: child table `["Blip", "Chip"]`
  unchanged, references
  `[("Blip", [3]), ("Chip", [4]), ("Chip", [5])]`, props
  `[[("note", .forward 0)], [("tag", .forward 0)],
  [("tag", .lit "fixed chip")]]`.
- `Test/js/nest_artifacts.mjs` pins the generated `Tick.mjs`: still
  two aliased imports (`$lrx_child_2` is pinned absent), `$lrx_child_1`
  called twice — once with `[props[0]]`, once with
  `["fixed chip"]` — and `disposer["children"] = [child_off_0,
  child_off_1, child_off_2]`.
- The browser gate pins the instance flow: the forwarded instance
  renders the root-supplied literal (`"Pulse child"`) while the
  repeated instance renders its own sealed literal (`"fixed chip"`),
  both `children[0].children[0].children[1]` and `…children[2]` are
  reachable, the two instances' counters are mutually independent
  (each transaction commits in its own state array; neither the
  sibling instance, the first leaf, nor the parent traces a commit),
  and root disposal freezes all three leaves' counters without
  erasing reachability.

## Consequences

- No compiler, host, or ABI change: the diff is the example and the
  gates. Every module outside the nest bundle is byte-identical; the
  benchmark bundle and its size gate stand.
- No manifest change at all this round: the bundle's module set and
  every `hostImports` list are unchanged — the dedup means a repeated
  reference is invisible to the manifest, which is itself part of the
  contract being pinned.
- Static-child composition is now covered in depth (ADR-0069), width
  (ADR-0070), and multiplicity (this ADR): table entries scale by
  distinct module, references scale by occurrence, and the two axes
  are independent. No further static-composition lab is warranted.
- Leaf templates written for composition should prefer classes over
  static ids; the pipeline does not (and should not) police this —
  the axe gate catches the collision where it matters, in the
  composed page.
- ADR-0070 OQ2 is discharged. The remaining prop boundary is
  reactivity alone (carried since ADR-0068 OQ1): constants flow any
  depth, width, and multiplicity, signals do not cross mounts.

## Open questions

1. **Reactive child props stay rejected by construction** (carried
   from ADR-0068): live parent→child data flow needs a subscription
   contract across the mount ABI, not a `ChildProp` relaxation.
