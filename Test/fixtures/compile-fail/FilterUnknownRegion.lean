import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component FilterUnknownRegion (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  filter ghost by mode := when "active" (label == "x");
  view := jsx% <main> [<ul> [<region items/>]];
}
