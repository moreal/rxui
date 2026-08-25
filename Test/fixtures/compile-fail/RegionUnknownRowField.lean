import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component RegionUnknownRowField (schema := S) where {
  state n : Int := 0;
  region items (label) := jsx% <li> [<span> [{ghost}]];
  view := jsx% <main> [<ul> [<region items/>]];
}
