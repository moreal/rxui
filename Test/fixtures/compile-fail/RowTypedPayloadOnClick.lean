import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

/- A payload-taking row event cannot serve a click binding (ADR-0046). -/
component RowTypedPayloadOnClick (schema := S) where {
  state n : Int := 0;
  event add := append items ("x");
  row items rename (value : String) := set label value;
  region items (label) := jsx% <li> [
    <span> [{label}],
    <span> [<button type="button" ariaLabel="Rename" onClick={rename}> ["r"]]
  ];
  view := jsx% <main> [
    <button type="button" onClick={add}> ["Add"],
    <ul ariaLabel="Items"> [<region items/>]
  ];
}
