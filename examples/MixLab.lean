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
field (the row `toggle` event writes only `done`), so the row-mount
prop-stability rule holds — and the view composes a static `<Badge/>`
too, so the shared
inventory seeds with the static disposer first and then one entry per
mounted row in mount order. -/

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
  event showAll := set filter "all";
  event showActive := set filter "active";
  event showDone := set filter "done";
  filter crew by filter := when "active" (done == "false")
    then when "done" (done == "true");
  persist crew := "leanrx-mix-lab.crew";
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
  view := jsx% <main class="mix-lab"> [
    <h1> ["Mix Lab"],
    <button type="button" onClick={addMember}> ["Add member"],
    <button type="button" onClick={clearDone}
      hidden={count crew (done == "true") == 0}> ["Clear done"],
    <p id="crew-line"> [{count crew (done == "true")}, " done of ", {count crew}],
    <ul id="crew" ariaLabel="Crew" hidden={count crew == 0}> [<region crew/>],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showActive}> ["Show active"],
    <button type="button" onClick={showDone}> ["Show done"],
    <Badge tag="static badge"/>
  ];
}

end LeanRxExamples.MixLab
