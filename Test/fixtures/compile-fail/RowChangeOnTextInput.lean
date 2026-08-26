import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- The delegated checked payload originates from checkbox inputs alone, so a
row onChange binding requires a type="checkbox" input element (ADR-0049). -/
component RowChangeOnTextInput (schema := S) where {
  state n : Int := 0;
  row items toggle (checked : String) := set done checked;
  region items (label, done) := jsx% <li> [
    <span> [<input ariaLabel="Toggle" onChange={toggle}/>],
    <span> [{label}]
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
