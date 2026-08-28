import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

-- ADR-0081: the other direction of the same one-to-one rule. Two hashes onto
-- one state literal give the flip-only `writeHash` block two `if (state[i]
-- === "on")` tests, so the *last* one wins and the canonical hash a flip
-- writes stops being the hash the user arrived on.
component RouteDuplicateLiteral (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  filter items by mode := when "on" (label == "x");
  route mode := when "#/" "all" then when "#/on" "on"
    then when "#/active" "on";
  view := jsx% <main> [<ul> [<region items/>]];
}
