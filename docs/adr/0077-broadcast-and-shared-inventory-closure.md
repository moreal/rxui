# ADR-0077: Broadcasts retain row children, and child-composing regions share one inventory

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0076 gated per-row child composition against counts, filters, and
persistence but left two open questions. First, **broadcast × row
children**: a region broadcast (`update crew (…)`) rewrites every row
tuple in place and rides the dirty reconcile — nothing pinned that the
retained-row path leaves row children mounted, stateful, and
un-respliced. Second, **multiple child-composing regions**: the live
`childInventory` is one mount-scope array shared by every
child-composing region's record, but no component had ever declared two
such regions — the mount-order interleaving of their entries and the
isolation of their dispose splices were unexercised (no example in the
repository had two regions of *any* kind in one component).

This round surveyed both axes before touching anything:

- **Retained rows never remount.** `createKeyedRegion.update(items,
  context)` calls `mountItem` only for entries whose key was not
  retained; a retained entry goes through `updateItem` alone. A
  broadcast retains every key (it rewrites tuples, never keys), so the
  reconcile it triggers re-renders rows through the update callback and
  the inventory is untouched — the child context forwarded to the call
  site is consumed only by mounts and disposals, of which a broadcast
  causes none.
- **The update callback cannot reach a child.** `rowUpdateTargets`
  yields nothing for a `.child` cell — the retained-row callback
  re-renders texts, class selections, reflections, and branch cells
  only. And LRX-VIEW-045 already rejects a child prop projecting any
  broadcast-written field, so a broadcast cannot even invalidate a
  child's mount-time prop (the `done`-written / `tag`-projected
  combination passes by construction).
- **One inventory identifier, per-region slots.** The record
  construction emits a single `const childInventory` and appends
  `Expr.ident childInventory` to *every* child-composing region's
  record, each at its own `regionChildSlot` position — the records
  share the array by identifier, not by copy. The commit sweep reads
  each region's own record (`regions[i][slotᵢ]`), so two regions with
  different feature sets read different slot numbers into the same
  array.
- **Dispose splices cannot cross regions.** Each region's dispose
  callback splices by `indexOf(row["$lrxRowChild"])` — the stashed
  mount return is a per-row closure instance, so even two regions
  composing the *same* child component can never misidentify each
  other's entries.

All four are coherent — again a combination to gate, not an
interference to seal.

## Decision

**Gate both axes in Mix Lab; change no code.** The backend, elaborator,
and hosts are untouched (ABI stays 17). Mix Lab gains a `markAllDone`
broadcast (`update crew (set done "true")` — `done` written, `tag`
still never written, so the row-child prop-stability rule holds) and a
second child-composing region, `pins`, whose rows compose
`<Badge tag={note}/>` with no counts, filter, persistence, or row
events — the bare record next to crew's widest one, and the first
two-region component in the repository.

The derived artifact gate (`Test/js/mix_artifacts.mjs`) pins the
two-record literal verbatim — crew's nine slots and pins'
`[region_1, [], 0, false, [], childInventory]` ending in the same
inventory identifier at slot 5 next to crew's slot 8 — together with
the `regions[1][5]` child context at the pins reconcile call site, the
broadcast's write-and-dirty body with its `region:crew:broadcast`
trace, both dispose functions' full `indexOf`-splice bodies, and the
pins no-op retained-row callback.

The browser spec (`Test/browser/mix.spec.mjs`) pins the behavior: a
broadcast updates every retained row's text, class, and checkbox while
the badge instances stay identical (array-identity check), their hit
counts survive, the inventory length is unchanged, and the region
metrics show mounts/disposals frozen with updates +N; the two regions'
entries interleave in the shared inventory as static seed first, then
actual mount order across regions (pinned by driving each badge's
commit count to its inventory position); and a removal in either
region splices exactly its own entry — the other region's entries and
metrics are untouched in both directions.

## Consequences

- ADR-0076's two open questions are closed as gates, not seals: the
  retained-row/mount split in `createKeyedRegion.update` is now held
  against broadcasts, and the shared-inventory design of ADR-0075 is
  held against its first multi-region consumer.
- The mount-order interleaving is now contractual: the inventory is
  chronological across regions (static seed, then whichever row mounts
  next, in transaction order), not grouped by region. A future
  region-grouped inventory would be a breaking change caught by the
  interleaving spec.
- The per-row closure identity behind `indexOf` is now load-bearing in
  a gated way — a future codegen that shared or memoized row-child
  mount returns across rows would break the cross-region isolation
  spec loudly.
- Multi-region components are exercised for the first time; the
  per-region dispatch tables, delegated listeners, dispose functions,
  and commit-sweep entries all index cleanly by region position.

## Open questions

1. **Broadcast into a child-composing region with a written projected
   field** is unrepresentable by LRX-VIEW-045, not just ungated — the
   `RowChildWrittenField` witness covers the row-event writer; a
   broadcast-writer witness would make the rejection's broadcast arm
   explicit if the diagnostic ever regresses.
2. **Three-plus child-composing regions** add no new mechanism (the
   two-region gates pin identifier sharing and splice isolation), but
   if a future lab ever declares one, the interleaving spec pattern
   here extends directly.
