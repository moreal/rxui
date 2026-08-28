import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String (.field "tone" String .empty)
def mode : Field S String := .here
def tone : Field S String := .there .here

-- ADR-0081: routing seals onto the *filter* field, because the filter table
-- is what bounds the field's state literals. `tone` carries no filter, so
-- there is no declared literal set for the hash table to map one-to-one onto
-- and nothing to reject an arbitrary literal against.
component RouteUnfilteredField (schema := S) where {
  state mode : String := "all";
  state tone : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  filter items by mode := when "on" (label == "x");
  route tone := when "#/" "all" then when "#/hot" "hot";
  view := jsx% <main> [<ul> [<region items/>]];
}
