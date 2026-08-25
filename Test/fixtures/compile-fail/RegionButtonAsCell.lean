import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component RegionButtonAsCell (schema := S) where {
  state n : Int := 0;
  event add := append items (s!"Row {n}") then set n (n + 1);
  region items (label) := jsx% <li> [
    <button type="button" onClick={remove}> ["✕"]
  ];
  view := jsx% <main> [
    <ul> [<region items/>],
    <button type="button" onClick={add}> ["Add"]
  ];
}
