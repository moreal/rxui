import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- The sealed autoFocus marker requires a native input element (ADR-0048). -/
component RowAutoFocusOnSpan (schema := S) where {
  state n : Int := 0;
  row items flip := set mode "edit";
  region items (label, mode) := jsx% <li> [
    {if mode == "view"
      then <span autoFocus> [{label}]
      else <span> [{label}]},
    <span> [<button type="button" ariaLabel="Flip" onClick={flip}> ["Flip"]]
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
