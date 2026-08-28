import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

-- ADR-0080: two regions filter on `mode`, so the route's sealed literal set
-- is the declared default plus the *union* of both tables — `{"all", "on",
-- "off"}`. `"mixed"` is in neither table, so `#/mixed` names a state literal
-- the field can never carry and the route is rejected. (Under the superseded
-- first-match rule `"off"` would have been rejected too, purely because
-- `left` is declared before `right`.)
component RouteLiteralOutsideFilterUnion (schema := S) where {
  state mode : String := "all";
  region left (label) := jsx% <li> [<span> [{label}]];
  region right (label) := jsx% <li> [<span> [{label}]];
  filter left by mode := when "on" (label == "x");
  filter right by mode := when "off" (label == "y");
  route mode := when "#/" "all" then when "#/off" "off"
    then when "#/mixed" "mixed";
  view := jsx% <main> [<ul> [<region left/>], <ul> [<region right/>]];
}
