import LeanRx

/-! Twin Lab closes the two questions ADR-0078 left open: what happens when
*two* keyed regions each carry an ADR-0051 filter view, and what happens
when two of those filters are driven by the *same* state field.

The lab is deliberately narrow — three regions, no child components, one
persisted region out of the three — so the generated module is a direct
reading of the per-region filter contract:

- `left` carries two count cells, so its record is `[handle, rows, nextKey,
  dirty, pending, countRefs, countCache, container]` — the two count slots
  hold arrays of two — and its filter container rides slot 7.
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

ADR-0081 closes the last combination on top of that shape:
`persist right := "leanrx-twin-lab.right"` persists *one* of the two
regions the routed field drives. The two write paths never meet: the
`storageSet` rides `region_touched_1` alone, while the canonical hash
write rides `changed[mode]` inside the commit prologue, ahead of every
region block. So a `mode` flip runs both twin sweeps and one
`route:mode:write` and persists nothing, while a `right` row toggle
persists once and writes no hash — and mount does both in order, seeding
`mode` from the hash before the DOM exists and hydrating `right`'s rows
after the listeners are wired, so the hydrate transaction's own sweep
applies the routed literal to the rows it just mounted. `left` and
`solo` remain unpersisted, so the persist feature is no more
component-wide than the filter or count features are: `right`'s record
is still the same six slots with its container at 5, because persistence
adds no region-record slot at all.

The one-route cap the component rests on is not scaffolding: two route
items compile, but their two `writeHash` blocks race for one
`location.hash` inside a commit and one `hashchange` wakes both
dispatches, the second reading the hash the first just rewrote
(ADR-0081).

`row left mark := set label (label ++ "*")` is the last shape on top of
that: a drain path on a *filtered* region that writes a field no arm of
its table reads. A region's touched flag folds two events together — the
row set changed, or a row's fields did — and the second can only move a
sweep that reads a field the drain writes. ADR-0083 makes that a per-sweep
question, and `left` is the region where every answer comes out the same
way: `{count left}` reads the row array's length, `{count left (flag ==
"true")}` reads `flag`, and the filter arms read `flag`, while the only
drain path writes `label`. So `left` binds *one* flag and it is the
narrow one —

```js
    const region_structural_0 = regions[0][3];
```

— and its count block and its filter sweep both read it. `right` is the
control on that axis: its `toggle` writes the very field its arms read, so
it keeps `region_touched_1 || changed[1]`, and its persistence write-back
reads every field and could never narrow anyway; `solo` has no drain path
at all, so its pending slot is provably empty and the two flags would be
one value. Three regions, three different flag sets, all derived from the
declared read sets.

A `mark` therefore drains one row and runs no scan at all — neither the
selection walk nor the `flag` count — and the `hidden` the last sweep wrote
survives on both the displayed and the hidden row, because `updateAt`
re-runs the retained handle in place. Mix Lab and Toggle Lab are the mixed
case the same rule produces: there a row toggle writes the field the
predicate counts and the filter read, so those sweeps keep the touched flag
while the row totals beside them move behind the structural bit, and one
region's block list interleaves the two.

The ADR-0086 displayed-state cache is what this lab witnesses next, and it
witnesses it in one module because the three regions disagree about
everything the cache's slot depends on. Every one of them is filtered, so
every one of their rows carries the cell holding the `hidden` the sweep last
wrote; only `right` is persisted, so only `right` carries the ADR-0085
serialization cell in front of it — `shown` sits at slot 3 in `left` and
`solo` and at slot 4 in `right`. The sweep evaluates its table for every row
and writes only the rows whose value moved, reporting the number as
`filter:{region}:written:{n}`, so each of the first two appends writes
exactly the row it just mounted, a `mode` flip writes exactly the one row per
twin whose selection inverted, and a ✕ removal writes **zero** — the row
array is rebuilt around unchanged tuples whose DOM nodes were never touched,
which is the identity keying made observable. A `right` toggle puts the two
per-row caches in one commit, `storage:right:encode:1` beside
`filter:right:written:1`. And because `right`'s `"off"` and `"mixed"` arms
select the same predicate while `left` names no `"mixed"` arm at all, the
hash flip between them wakes both sweeps, evaluates every row, and writes
nothing: the state-change path — the one no cell can be pre-staled for,
since the value depends on the filter field as well as the row's — still
crossing into the DOM exactly zero times.

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
  persist right := "leanrx-twin-lab.right";
  row right toggle (checked : String) := set flag checked;
  row left mark := set label (label ++ "*");
  region left (label, flag) := jsx% <li class="twin-row"> [
    <span class="twin-label"> [{label}],
    <span class="twin-flag"> [{flag}],
    <span class="twin-actions"> [
      <button type="button" ariaLabel="Remove left" onClick={remove}> ["✕"]
    ],
    <span class="twin-marks"> [
      <button type="button" ariaLabel="Mark left" onClick={mark}> ["★"]
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
    <p id="left-line"> [{count left}, " left, ", {count left (flag == "true")}, " on"],
    <ul id="left" ariaLabel="Left"> [<region left/>],
    <ul id="right" ariaLabel="Right"> [<region right/>],
    <ul id="solo" ariaLabel="Solo"> [<region solo/>]
  ];
}

end LeanRxExamples.TwinLab
