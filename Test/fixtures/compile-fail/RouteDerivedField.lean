import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "seed" String (.field "mode" String .empty)
def seed : Field S String := .here
def mode : Field S String := .there .here

-- ADR-0081: the routed field is one *state* field. A derived value has no
-- state slot to seed at mount and no `changed` bit a hash write could ride,
-- and `hashchange` would have to write a value the graph recomputes — so a
-- route over a derived value is rejected before any table rule is read.
component RouteDerivedField (schema := S) where {
  state seed : String := "all";
  derived mode := rx% seed;
  region items (label) := jsx% <li> [<span> [{label}]];
  filter items by mode := when "on" (label == "x");
  route mode := when "#/" "all" then when "#/on" "on";
  view := jsx% <main> [<ul> [<region items/>]];
}
