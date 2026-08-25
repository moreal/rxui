import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component RowClassSelectDynamic (schema := S) where {
  state n : Int := 0;
  region items (label, other) := jsx%
    <li class={if label == other then "a" else "b"}> [<span> [{label}]];
  view := jsx% <main> [<ul> [<region items/>]];
}
