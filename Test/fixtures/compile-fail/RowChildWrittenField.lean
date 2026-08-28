import LeanRx

/-! ADR-0075: a row child prop is a row-mount constant — the ADR-0068 OQ1
immutable-prop boundary in row scope. Forwarding a row field that a declared
row event stage rewrites would silently diverge from the row's own
re-rendered text (the row updates, the child's prop does not), so the model
check rejects the projection (LRX-VIEW-045). Here `label` is written by the
`rename` row event. -/

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

component RowChildWrittenField (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  row roster rename (value : String) := set label value;
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label ++ marks}],
      <span class="roster-edit"> [
        <input ariaLabel="Rename row" onInput={rename} />
      ],
      <Chip tag={label}/>
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
