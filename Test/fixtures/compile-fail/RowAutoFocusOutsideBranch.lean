import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- The sealed autoFocus marker sits inside a two-branch cell's subtrees only
(ADR-0048): an unbranched cell's input mounts with its row, and row mount
never focuses. -/
component RowAutoFocusOutsideBranch (schema := S) where {
  state n : Int := 0;
  row items retype (value : String) := set label value;
  region items (label) := jsx% <li> [
    <span> [<input ariaLabel="Editor" value={label} onInput={retype} autoFocus/>]
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
