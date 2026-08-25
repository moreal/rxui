import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component RowUpdateUnknownField (schema := S) where {
  state n : Int := 0;
  row items mark := set ghost (label ++ "x");
  region items (label) := jsx% <li> [<span> [{label}]];
  view := jsx% <main> [<ul> [<region items/>]];
}
