import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- Typed row event payloads are String only (ADR-0046). -/
component IntRowPayload (schema := S) where {
  state n : Int := 0;
  event add := append items ("x");
  row items rename (value : Int) := set label value;
  region items (label) := jsx% <li> [
    <span> [{label}],
    <span> [<input ariaLabel="Edit" onInput={rename} />]
  ];
  view := jsx% <main> [
    <button type="button" onClick={add}> ["Add"],
    <ul ariaLabel="Items"> [<region items/>]
  ];
}
