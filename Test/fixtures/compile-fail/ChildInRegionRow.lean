import LeanRx

/-! ADR-0075: a row child reference takes no children — the child's content
lives in its own component view, so a children block on a row-composed head
stays rejected (the ADR-0072 boundary refined to the sealed surface's edge).
The checked `Chip` spec is in scope, pinning that the rejection is about the
reference shape, not a missing `_spec`. -/

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

component ChildInRegionRow (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label ++ marks}],
      <Chip tag="x"> ["content"]
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
