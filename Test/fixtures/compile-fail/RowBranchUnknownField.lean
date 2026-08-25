import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- A two-branch row cell selects on a declared row field (ADR-0047). -/
component RowBranchUnknownField (schema := S) where {
  state n : Int := 0;
  region items (label, mode) := jsx% <li> [
    {if missing == "view"
      then <span> [{label}]
      else <span> ["editing"]}
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
