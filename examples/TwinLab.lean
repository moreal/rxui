import LeanRx

/-! Twin Lab closes the two questions ADR-0078 left open: what happens when
*two* keyed regions each carry an ADR-0051 filter view, and what happens
when two of those filters are driven by the *same* state field.

The lab is deliberately narrow — three regions, no child components, no
persistence — so the generated module is a direct reading of the
per-region filter contract:

- `left` carries a count cell, so its record is `[handle, rows, nextKey,
  dirty, pending, countRefs, countCache, container]` and its filter
  container rides slot 7.
- `right` carries no count, so its record is `[handle, rows, nextKey,
  dirty, pending, container]` and the *same* container rides slot 5.
  The container slot is `5 + counts?2`, computed inside the per-region
  loop from that region's own feature set; two filtered regions therefore
  read different slot numbers out of records of different widths, and
  nothing about the filter feature is component-wide.
- `solo` also has no count, so its container is at slot 5 too — but its
  filter is driven by a *different* state field, which is what separates
  the two axes below.

`left` and `right` are the twins: both are filtered by `mode`, so one
`set mode …` raises one `changed[1]` flag that wakes *both* sweeps in one
commit. Their arm tables are deliberately inverted — `left` shows the
`flag == "true"` rows under `"on"` while `right` shows the `flag ==
"false"` ones — so a single flip hides complementary rows in the two
regions, which no shared table or hoisted temporary could produce. Each
sweep allocates its own scan and row temporaries — both suffixed with the
region index — and navigates `childAt` from its own container slot, so the
two walks never touch each other's container or row table, and they run in
*region declaration order* inside the one commit.

`solo` is the control: filtered by `tone`, it wakes on `changed[2]` and
on its own region-touch flag alone. A `mode` flip emits no `solo` scan
at all, and a `tone` flip emits no `left` or `right` scan — each sweep's
`if (region_touched_{i} || changed[{field}])` guard names exactly one
region's flag and exactly one field's changed bit.

`stir` mixes the two wake reasons in one transaction: `append solo (…)
then set mode "on" then set added (added + 1)` touches `solo`
structurally while changing the twins' filter field, so one commit runs
three sweeps — two woken by `changed[mode]`, one woken by its own touched
flag — still in declaration order, still once each. Two filters on *one*
region remain rejected (`LRX-TYPE-113`): one region owns one container
and one row table, so a second table over it would be two writers of one
`hidden` property.

ADR-0080 closes the two axes ADR-0079 left open on top of that shape:

- `route mode := when "#/" "all" then when "#/on" "on" then when "#/off"
  "off" then when "#/mixed" "mixed"` routes the *shared* filter field.
  The sealed literal set is the declared default plus the **union** of
  every filter table over the field, not the first-declared table:
  `"mixed"` appears only in `right`'s arm table, so a first-match rule
  would reject `#/mixed` purely because `left` is declared first. Under
  `"mixed"` the region that names the literal filters and the region
  that does not falls through to show-all — exactly what the emitted arm
  chain already does — and one `hashchange` raises one `changed[mode]`
  bit that wakes both twin sweeps inside the one route-arm transaction,
  while `writeHash` rides that same bit, once, regardless of how many
  regions filter on it.
- `row right toggle (checked : String) := set flag checked` puts a
  pending-row drain (`updateAt`) beside a filter sweep at region index
  *1*: the checkbox writes the very field `right`'s filter reads, so one
  commit reconciles the retained row and then re-selects it. The
  `region_touched_1` flag folds the pending array in, so the drain and
  the sweep wake together by construction; `left` and `solo` stay asleep
  even though `left` shares the filter field.

No host change; runtime ABI stays 17. -/

namespace LeanRxExamples.TwinLab

open LeanRx

abbrev TwinSchema : Schema :=
  .field "added" Int (.field "mode" String (.field "tone" String .empty))

def added : Field TwinSchema Int := .here

def mode : Field TwinSchema String := .there .here

def tone : Field TwinSchema String := .there (.there .here)

open scoped LeanRxDsl

component TwinLab (schema := TwinSchema) where {
  state added : Int := 0;
  state mode : String := "all";
  state tone : String := "all";
  event seedOn := append left (s!"L{added}", "true")
    then append right (s!"R{added}", "true")
    then append solo (s!"S{added}", "true")
    then set added (added + 1);
  event seedOff := append left (s!"L{added}", "false")
    then append right (s!"R{added}", "false")
    then append solo (s!"S{added}", "false")
    then set added (added + 1);
  event addLeft := append left (s!"L{added}", "true") then set added (added + 1);
  event showAll := set mode "all";
  event showOn := set mode "on";
  event showOff := set mode "off";
  event toneAll := set tone "all";
  event toneOn := set tone "on";
  event stir := append solo (s!"S{added}", "true")
    then set mode "on"
    then set added (added + 1);
  filter left by mode := when "on" (flag == "true")
    then when "off" (flag == "false");
  filter right by mode := when "on" (flag == "false")
    then when "off" (flag == "true")
    then when "mixed" (flag == "true");
  filter solo by tone := when "on" (flag == "true");
  route mode := when "#/" "all" then when "#/on" "on"
    then when "#/off" "off" then when "#/mixed" "mixed";
  row right toggle (checked : String) := set flag checked;
  region left (label, flag) := jsx% <li class="twin-row"> [
    <span class="twin-label"> [{label}],
    <span class="twin-flag"> [{flag}],
    <span class="twin-actions"> [
      <button type="button" ariaLabel="Remove left" onClick={remove}> ["✕"]
    ]
  ];
  region right (label, flag) := jsx% <li class="twin-row"> [
    <span class="twin-label"> [{label}],
    <span class="twin-flag"> [{flag}],
    <span class="twin-actions"> [
      <input type="checkbox" ariaLabel="Flag right" checked={flag == "true"}
        onChange={toggle}/>
    ]
  ];
  region solo (label, flag) := jsx% <li class="twin-row"> [
    <span class="twin-label"> [{label}],
    <span class="twin-flag"> [{flag}]
  ];
  view := jsx% <main class="twin-lab"> [
    <h1> ["Twin Lab"],
    <button type="button" onClick={seedOn}> ["Seed on"],
    <button type="button" onClick={seedOff}> ["Seed off"],
    <button type="button" onClick={addLeft}> ["Add left"],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showOn}> ["Show on"],
    <button type="button" onClick={showOff}> ["Show off"],
    <button type="button" onClick={toneAll}> ["Tone all"],
    <button type="button" onClick={toneOn}> ["Tone on"],
    <button type="button" onClick={stir}> ["Stir"],
    <p id="left-line"> [{count left}, " left"],
    <ul id="left" ariaLabel="Left"> [<region left/>],
    <ul id="right" ariaLabel="Right"> [<region right/>],
    <ul id="solo" ariaLabel="Solo"> [<region solo/>]
  ];
}

end LeanRxExamples.TwinLab
