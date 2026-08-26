import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component BroadcastUnknownRowField (schema := S) where {
  state n : Int := 0;
  event completeAll := update items (set ghost "x");
  region items (label, done) := jsx% <li> [<span> [{label}]];
  view := jsx% <main> [<ul> [<region items/>]];
}
