# ADR-0078: Region features distribute per region, and a component persists one key per region

- Status: Accepted
- Date: 2026-08-28

## Context

ADR-0077 made Mix Lab the repository's first two-region component, but
both regions carried their features asymmetrically by *omission*: `crew`
held counts, a filter, and persistence, and `pins` held none of them.
Every region feature — the ADR-0050 counts, the ADR-0051 filter view,
the ADR-0058/0059 region-subject selections, the ADR-0063 persistence —
was therefore still exercised on exactly one region at a time. What
happens when two regions each carry a feature was unpinned in five
places, and this round surveyed all five before touching anything:

- **Per-region sweep identifiers.** The filter sweep allocates
  `filter_scan_{regionIndex}` / `filter_row_{regionIndex}`, the count
  sweep `count_next_{regionIndex}_{slot}`, the persistence sweep
  `persist_rows_{regionIndex}` — every emitted temporary already carries
  the region index, so two filtered regions cannot collide.
- **Per-region feature slots.** The filter container slot
  (`5 + counts?2`) and the child inventory slot (`regionChildSlot`,
  `5 + counts?2 + filter?1`) are computed *inside* the per-region loop
  from that region's own feature set. Two regions with different feature
  sets therefore read different slot numbers out of records of different
  widths.
- **Per-region records.** `countRefs` and `countCache` are that region's
  own arrays, sized by the count cells whose `region` field names it, so
  `{count crew}` and `{count pins}` cells land in different records at
  region-local slot indices with `count:{region}:{slot}` labels.
- **Document-order attr labels.** Region-subject selections
  (ADR-0058/0059) live in the *global* `attrSelects` table and keep
  document-order indices; the per-region loop filters them by
  `regionSubject?`, so a selection over the second region keeps its
  document position while re-evaluating under the second region's
  touched flag.
- **Chained cross-region events.** `Update.sequence` composes region
  actions freely, and each action raises its own region's dirty flag;
  the commit sweep then walks regions in declaration order, so event
  order and sweep order are independent by construction.

All five are coherent. The survey found exactly one axis that was not
merely ungated but *unrepresentable*: `validatePersists` capped the
whole component at one persist item (`spec.persists.size ≤ 1`,
`LRX-TYPE-118`), even for two different regions under two different
keys — while the backend was already index-generalized
(`hydrateFunction … persistIndex`, `hydrateName persistIndex`, a mount
loop over `persists.zipIdx`, a write-back inside the per-region sweep).
The cap was stage-1 scaffolding, not a contract.

## Decision

**Lift the persist cap to one key per region, and gate the whole
feature distribution in Mix Lab.**

`validatePersists` now rejects two persist items *on one region* ("a
keyed region carries at most one persist item") and two items *sharing a
storage key* ("two persist items share one storage key; each persisted
region owns its own key") — both `LRX-TYPE-118`, both for the same
reason: one commit sweep would emit two write-backs racing for one
localStorage slot. Distinct keys on distinct regions pass. No backend,
elaborator, or host change; runtime ABI stays 17.

Mix Lab's `pins` region gains its own count cell (`{count pins}`), its
own emptiness selection (`hidden={count pins == 0}`), its own persist
key (`leanrx-mix-lab.pins`), and the component gains one chained
cross-region event, `stowDone` — `append pins (…) then remove crew
(…) then set added (…)`.

The derived artifact gate (`Test/js/mix_artifacts.mjs`) pins the
two-record literal verbatim: crew's nine slots with the container at 7
and the inventory at 8, next to pins' eight slots with its *inventory*
at 7 — the same slot number meaning two different things in the two
records, which is the sharpest available evidence that every feature
slot is computed per region. It also pins the per-region count writes
(`regions[0][5][1]` beside `regions[1][5][0]`), the document-order
`attr:2` label over the second region, both hydrate functions with their
own `storageGet` keys and their adjacent mount-time calls, both
`storageSet` write-backs, and the chained event body with its
event-order dirty flags.

The browser spec (`Test/browser/mix.spec.mjs`) pins the behavior: two
stored keys hydrate into their own regions in declaration order and
seed the shared inventory crew-first, a write in one region rewrites its
key alone; the chained event produces exactly one commit whose trace
shows `region:pins:append` before `region:crew:removeIf` (event order)
but `region:crew:update` before `region:pins:update` and
`storage:crew:write` before `storage:pins:write` (sweep order); and a
crew filter flip leaves every pins row, pins child instance, pins metric
and the pins key untouched.

## Consequences

- Persistence is now a per-region feature like counts and filters, not a
  per-component one. The two rejections make the remaining constraint
  explicit — the invariant is *one writer per key*, not *one key per
  component*.
- The two-record slot literal is load-bearing in a new way: a codegen
  that ever hoisted a feature slot to a component-wide constant would
  break it loudly, because slot 7 is simultaneously crew's container and
  pins' inventory.
- Event order and commit-sweep order are now contractually distinct and
  gated. A future sweep that walked regions in first-touched order
  instead of declaration order would fail the chained-event trace.
- Mix Lab is now the widest single component in the repository — two
  child-composing regions, four region features spread across them, and
  eight events — which makes it the natural place to gate any further
  region-feature combination.

## Open questions

1. **Two *filtered* regions** remain ungated: keeping `pins` unfiltered
   is what produces the divergent slot numbers this round pins, and one
   lab cannot have both. The mechanism is per-region by construction
   (`filter_scan_{regionIndex}`, a per-region container slot, a
   per-region touched flag), and the crew-filter-flip spec shows an
   unfiltered neighbour is untouched; a second filtered region would add
   a second scan and nothing else.
2. **Two filters over one state field** — two regions filtered by the
   same `filter` state — would make one `changed[field]` drive both
   sweeps in one commit. Coherent by the same construction, unexercised.
