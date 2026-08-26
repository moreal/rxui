import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component CountUnknownRegion (schema := S) where {
  state n : Int := 0;
  region items (label) := jsx% <li> [<span> [{label}]];
  view := jsx% <main> [<p> [{count ghost}], <ul> [<region items/>]];
}
