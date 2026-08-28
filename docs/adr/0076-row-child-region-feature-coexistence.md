# ADR-0076: Row-child composition coexists with counts, filters, and persistence

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0075 sealed per-row child composition with the live `childInventory`
riding the region record's *last* slot — a position defined by the
`regionChildSlot` formula `5 + counts?2 + filter?1` — but its only lab was
NestLab's roster, a region with no counts, no filter, and no persistence.
The combined layout was therefore ungated: nothing pinned that the record
construction and the commit sweep's `update`/`updateAt` call sites agree on
the slot arithmetic when the ADR-0050 count slots and the ADR-0051
container slot sit in between, that ADR-0063 hydration mounts row children
at all, or that the filter's `childAt(container, i)` row-root navigation
survives a child living inside each row.

This round surveyed the four suspected interference axes in
`LeanRx/Backend/Component.lean`:

- **Slot arithmetic.** The record construction builds the slots by
  appending — base five, then `countRefs`/`countCache` when counts exist,
  then the container when a filter exists, then `childInventory` — so it
  matches `regionChildSlot` structurally; both sides select counts and
  filters by the same region-name predicates. No divergence to find, but
  also no gate holding it.
- **Hydration.** ADR-0063 hydration pushes parsed rows and sets the dirty
  flag inside an ordinary transaction shell, so the shared commit sweep's
  reconcile — the one call site that forwards the inventory slot as the
  child context — mounts hydrated rows' children exactly as appended rows'.
- **Filter navigation.** A row child mounts *inside* the row root (the
  ADR-0039 no-wrapper shape), never as a container sibling, so the
  container's element children remain exactly the row roots and the
  `childAt(container, i)` index math is untouched; the sweep writes only
  the `hidden` property, so a hidden row's child is neither disposed nor
  spliced — the row-identity invariant of ADR-0051 extends to the child.
- **Count/visibility/persistence subjects.** Counts, `hiddenIfEmpty`,
  `checkedIf`, and the persistence serialization all read the row table
  (record slot 1), never the DOM or the inventory; a child transaction
  commits in the child's own state array and cannot touch the region.

All four axes are coherent — there is no interference to seal, only a
combination to gate.

## Decision

**Gate the combination; change no code.** The backend, elaborator, and
hosts are untouched (ABI stays 17). The new Mix Lab (`examples/MixLab.lean`)
is one `crew` region carrying all four features at once: two ADR-0050 count
texts (total and predicate), an ADR-0051 filter view, ADR-0063 persistence,
an ADR-0058/0059 `hidden` pair, an ADR-0049 row checkbox, and a per-row
`<Badge tag={tag}/>` whose prop projects the never-written `tag` field,
plus one static `<Badge/>` so the inventory seeds ahead of the row entries.

The derived artifact gate (`Test/js/mix_artifacts.mjs`) pins the widest
record literal verbatim —
`[region_0, [], 0, false, [], [count_text_8, count_text_10], [0, 0],
node_11, childInventory]` — together with the `regions[0][8]` child context
at both the `update` and `updateAt` call sites, the `regions[0][7]` filter
navigation, the hydrate function, and the `row-child-components` +
`region-filters` + `persistence` feature list. The browser spec
(`Test/browser/mix.spec.mjs`) pins the behavior: hydrated rows mount live
badges and register in the inventory; filtering hides row roots without
disposing, splicing, or muting their badges (state intact across the flip);
a ✕ removal and a `clearDone` predicate removal decrement the count texts
and splice the inventory in the same commit with the normalized persisted
value; badge clicks touch no region metric, count, or stored value; root
disposal freezes badge counters while the inventory keeps reachability.

## Consequences

- The `regionChildSlot` formula is now held by a gate on its widest case;
  any future slot inserted between the filter slot and the inventory (or a
  reordering of the count/filter slots) breaks `mix_artifacts.mjs` loudly
  instead of corrupting the child context silently.
- Hydration needs no special-casing for children — riding the shared
  commit sweep was the whole design (ADR-0063), and the gate now proves
  the child context rides along.
- The Badge cell's delegated action entry is `""` in both the `click` and
  `change` arrays — the ADR-0075 no-carve-out rule holds under delegated
  checkbox rows too.
- No compile-fail witness joins the set: every surveyed axis was coherent,
  so there is no rejection to pin — the sealing work stays in ADR-0075.

## Open questions

1. **Broadcast × row children.** Mix Lab's `clearDone` covers predicate
   removal; a region *broadcast* (`update crew (…)`) re-renders every
   retained row through the reconcile. The retained-row path never
   remounts children (NestLab pins that for `updateAt`), but no gate pins
   a broadcast leaving the inventory untouched. Add one when a lab
   combines a broadcast with row children.
2. **Multiple child-composing regions sharing one inventory.** The
   inventory is one mount-scope array shared by every child-composing
   region; Mix Lab and NestLab each have one such region. The mount-order
   interleaving of two regions' entries is unexercised.
