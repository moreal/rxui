import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String (.field "tone" String .empty)
def mode : Field S String := .here
def tone : Field S String := .there .here

component FilterRegionTwice (schema := S) where {
  state mode : String := "all";
  state tone : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  filter items by mode := when "active" (label == "x");
  filter items by tone := when "loud" (label == "y");
  view := jsx% <main> [<ul> [<region items/>]];
}
