import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- A sealed row value reflection writes the value property of a native input
only (ADR-0047). -/
component RowReflectOnSpan (schema := S) where {
  state n : Int := 0;
  region items (label) := jsx% <li> [
    <span value={label}> [{label}]
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
