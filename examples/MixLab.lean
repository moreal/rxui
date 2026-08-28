import LeanRx

/-! Mix Lab dogfoods the ADR-0075 row-scoped child composition *combined*
with the region features it had only been exercised apart from: the
ADR-0050 sealed counts, the ADR-0051 filter view, and the ADR-0063
persistence — one `crew` region carrying all four at once (ADR-0076). The
region record therefore takes its widest layout: `[handle, rows, nextKey,
dirty, pending, countRefs, countCache, container, childInventory]` — the
base five slots, the two ADR-0050 count slots, the ADR-0051 container
slot, and the ADR-0075 live children inventory in the last slot, exactly
the `regionChildSlot` formula (5 + counts?2 + filter?1 = 8) the commit
sweep's `update`/`updateAt` call sites read. Every row composes
`<Badge tag={tag}/>` — the prop projects the never-written `tag` row
field (the row `toggle` event writes only `done` and the `markAllDone`
broadcast writes only `done` too), so the row-mount prop-stability rule
holds — and the view composes a static `<Badge/>` too, so the shared
inventory seeds with the static disposer first and then one entry per
mounted row in mount order.

ADR-0077 closes the two open questions ADR-0076 left. The `markAllDone`
broadcast (`update crew (set done "true")`) re-renders every retained
crew row through the dirty reconcile, and the retained path calls only
the update callback — row children never remount, badge state survives,
and the inventory length is untouched, because the reconcile mounts only
entries whose key was not retained. And a *second* child-composing
region, `pins`, shares the one mount-scope `childInventory`: both
records end in the same array identifier, the entries of both regions
interleave after the static seed in actual mount order, and each
region's dispose callback splices by `indexOf` of its own row's stashed
mount return — a per-row function instance — so one region's removal
can never misidentify the other's entries.

ADR-0078 spreads the region features across *both* regions. `pins` now
carries its own count cell, its own emptiness selection, and its own
persist key, so its record is `[handle, rows, nextKey, dirty, pending,
countRefs, countCache, childInventory]` — its inventory at
`regionChildSlot` 5 + 2 + 0 = 7, the slot number that means *container*
in crew's nine-slot record and *inventory* in pins', which is the
sharpest evidence every feature slot is computed from that region's own
feature set. Three contracts follow. Two persist keys are independent:
`persist crew := "leanrx-mix-lab.crew"` and `persist pins :=
"leanrx-mix-lab.pins"` emit one hydrate transaction each, run at mount
in declaration order, and each write-back rides its own region's touched
flag — one region persisting twice, or two regions sharing one key, is
`LRX-TYPE-118`. Counts and selections distribute by record and by
document order: crew's two cells fill crew's own two-slot refs and
cache, pins' single cell fills its own one-slot pair, and the emptiness
selections keep document-order labels across the region boundary (crew
owns attrs 0 and 1, pins attr 2) while each re-evaluates only under its
own region's flag. And one chained event reaches both regions:
`stowDone` appends a pin and then removes the done crew rows inside one
transaction, so the dirty flags are raised in *event* order and drained
by the commit sweep in *region declaration* order, crew before pins,
with one commit and one write-back per region.

The combination pins three orthogonality contracts. Hydration mounts
children: `persist crew := "leanrx-mix-lab.crew"` hydrates through the
ordinary dirty-flag transaction, so the shared commit sweep's reconcile
mounts each hydrated row's Badge at its cell, stashes it on the row root,
and pushes it into the inventory — hydrated rows are full citizens of the
child vocabulary. Filtering never disposes children: the ADR-0051 sweep
writes each row root's `hidden` property by `childAt(container, i)`
navigation — row roots are the container's only element children (the
Badge mounts *inside* the `<li>`, never as a container sibling), so the
index math is untouched and a hidden row's Badge stays mounted with its
state intact — row identity is preserved across filter flips. Counts and
the region-subject selections stay row-table-scoped: `{count crew}`,
`{count crew (done == "true")}`, the `hidden={count crew == 0}` list
wrapper, and the clear-done affordance all read the row table, never the
child inventory — Badge clicks commit in the child's own state array and
touch no region metric, count, or persisted value, while a removal
(✕ or `clearDone`) decrements the count texts and splices the inventory
in the same commit; the `crew` filter flip is likewise crew's alone —
`pins` has no filter, no scan, and no touched flag on a filter change.
No host change; runtime ABI stays 17. -/

namespace LeanRxExamples.MixLab

open LeanRx

abbrev BadgeSchema : Schema := .field "hits" Int .empty

def hits : Field BadgeSchema Int := .here

abbrev MixSchema : Schema := .field "added" Int (.field "filter" String .empty)

def added : Field MixSchema Int := .here

def filter : Field MixSchema String := .there .here

open scoped LeanRxDsl

component Badge (schema := BadgeSchema) where {
  state hits : Int := 0;
  prop tag : String;
  event hit := set hits (hits + 1);
  view := jsx% <div class="badge"> [
    <span class="badge-tag"> [{tag}],
    <button type="button" onClick={hit}> ["Hit"],
    <p class="badge-text"> [{"badgeText": rx% s!"Hits: {hits}"}]
  ];
}

component MixLab (schema := MixSchema) where {
  state added : Int := 0;
  state filter : String := "all";
  event addMember := append crew (s!"Member {added}", "false", s!"Tag {added}")
    then set added (added + 1);
  event clearDone := remove crew (done == "true");
  event markAllDone := update crew (set done "true");
  event addPin := append pins (s!"Pin {added}")
    then set added (added + 1);
  event stowDone := append pins (s!"Stowed {added}")
    then remove crew (done == "true")
    then set added (added + 1);
  event showAll := set filter "all";
  event showActive := set filter "active";
  event showDone := set filter "done";
  filter crew by filter := when "active" (done == "false")
    then when "done" (done == "true");
  persist crew := "leanrx-mix-lab.crew";
  persist pins := "leanrx-mix-lab.pins";
  row crew toggle (checked : String) := set done checked;
  region crew (label, done, tag) := jsx%
    <li class={if done == "true" then "crew-row done" else "crew-row"}> [
      <span class="crew-label"> [{label}],
      <span class="crew-toggle"> [
        <input type="checkbox" ariaLabel="Toggle member" checked={done == "true"}
          onChange={toggle}/>
      ],
      <span class="crew-actions"> [
        <button type="button" ariaLabel="Remove member" onClick={remove}> ["✕"]
      ],
      <Badge tag={tag}/>
    ];
  region pins (note) := jsx% <li class="pin-row"> [
    <span class="pin-note"> [{note}],
    <span class="pin-actions"> [
      <button type="button" ariaLabel="Remove pin" onClick={remove}> ["✕"]
    ],
    <Badge tag={note}/>
  ];
  view := jsx% <main class="mix-lab"> [
    <h1> ["Mix Lab"],
    <button type="button" onClick={addMember}> ["Add member"],
    <button type="button" onClick={clearDone}
      hidden={count crew (done == "true") == 0}> ["Clear done"],
    <button type="button" onClick={markAllDone}> ["Mark all done"],
    <p id="crew-line"> [{count crew (done == "true")}, " done of ", {count crew}],
    <ul id="crew" ariaLabel="Crew" hidden={count crew == 0}> [<region crew/>],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showActive}> ["Show active"],
    <button type="button" onClick={showDone}> ["Show done"],
    <button type="button" onClick={addPin}> ["Add pin"],
    <button type="button" onClick={stowDone}> ["Stow done"],
    <p id="pins-line"> [{count pins}, " pinned"],
    <ul id="pins" ariaLabel="Pins" hidden={count pins == 0}> [<region pins/>],
    <Badge tag="static badge"/>
  ];
}

end LeanRxExamples.MixLab
