import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- The sealed row checked reflection writes a checkbox's checked property, so
it requires a type="checkbox" input element (ADR-0049). -/
component RowCheckedReflectOnTextInput (schema := S) where {
  state n : Int := 0;
  region items (label, done) := jsx% <li> [
    <span> [<input type="text" ariaLabel="Done" checked={done == "true"}/>],
    <span> [<button type="button" ariaLabel="Remove" onClick={remove}> ["x"]]
  ];
  view := jsx% <main> [<ul ariaLabel="Items"> [<region items/>]];
}
