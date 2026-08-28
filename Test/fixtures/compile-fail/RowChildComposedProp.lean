import LeanRx

/-! ADR-0075: a row child prop is a string literal or the bare projection of
one declared row field — never a composed row expression; composition stays
inside the child's own view or the row's own text positions. The row
lowering rejects the value shape (LRX-ELAB-131). -/

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

component RowChildComposedProp (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label}],
      <Chip tag={label ++ marks}/>
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
