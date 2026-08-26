import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- Delegated action arrays are static and dblclick bubbles from any content,
so it takes click's exact cross-branch agreement rule: a dblclick bound in
one branch must be bound identically in the other (ADR-0049). -/
component RowBranchOneSidedDblClick (schema := S) where {
  state n : Int := 0;
  row items edit := set mode "edit";
  region items (label, mode) := jsx% <li> [
    {if mode == "view"
      then <span onDblClick={edit}> [{label}]
      else <span> [{label}]},
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["x"]]
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
