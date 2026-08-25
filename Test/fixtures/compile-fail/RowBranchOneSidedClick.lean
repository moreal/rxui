import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- Delegated action arrays are static, so a click bound in one branch must be
bound identically in the other: any content of the unbound branch could
originate a bubbling click (ADR-0047). -/
component RowBranchOneSidedClick (schema := S) where {
  state n : Int := 0;
  row items edit := set mode "edit";
  region items (label, mode) := jsx% <li> [
    {if mode == "view"
      then <span> [<button type="button" ariaLabel="Edit" onClick={edit}> ["e"]]
      else <span> [{label}]}
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
