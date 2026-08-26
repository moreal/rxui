import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component FilterDuplicateLiteral (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  filter items by mode := when "active" (label == "x")
    then when "active" (label == "y");
  view := jsx% <main> [<ul> [<region items/>]];
}
