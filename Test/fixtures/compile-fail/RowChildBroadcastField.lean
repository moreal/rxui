import LeanRx

/-! ADR-0077: a row child prop is a row-mount constant, and the writer set
behind LRX-VIEW-045 includes region *broadcasts*, not only row event stages
(ADR-0075). A broadcast rewrites every retained row's tuple through the
dirty reconcile, but a retained row never remounts its child — projecting a
broadcast-written field would silently diverge from the row's own
re-rendered text, so the model check rejects the projection. Here `marks`
is written by the `markAll` component-event broadcast. -/

open LeanRx
open scoped LeanRxDsl

abbrev ChipSchema : Schema := .field "chips" Int .empty
def chips : Field ChipSchema Int := .here

component Chip (schema := ChipSchema) where {
  state chips : Int := 0;
  prop tag : String;
  event chip := set chips (chips + 1);
  view := jsx% <div class="chip"> [
    <span class="chip-tag"> [{tag}],
    <button type="button" onClick={chip}> ["Chip"],
    <p class="chip-text"> [{"chipText": rx% s!"Chips: {chips}"}]
  ];
}

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

component RowChildBroadcastField (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  event markAll := update roster (set marks "×");
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label ++ marks}],
      <Chip tag={marks}/>
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <button type="button" onClick={markAll}> ["Mark all"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
