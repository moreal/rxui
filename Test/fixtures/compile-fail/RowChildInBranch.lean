import LeanRx

/-! ADR-0075: a row child reference cannot sit inside a two-branch row cell's
subtrees — the branch replacement arm rebuilds the cell's subtree with a
`detach` plus `append` and never runs a dispose path for what it detaches, so
a child mounted there would leak its listeners and instrumentation. The model
check rejects the placement (LRX-VIEW-045). -/

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

component RowChildInBranch (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  row roster mark := set marks (marks ++ " ★");
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label}],
      {if marks == "" then
        <span class="plain"> [<Chip tag="branch chip"/>]
      else
        <span class="marked"> [{marks}]},
      <span class="roster-mark"> [
        <button type="button" ariaLabel="Mark row" onClick={mark}> ["★"]
      ]
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
