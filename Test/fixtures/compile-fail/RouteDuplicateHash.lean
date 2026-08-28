import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

-- ADR-0081: the table is one-to-one in both directions. Two arms on one hash
-- literal make the dispatch chain's first test shadow the second, so the
-- second arm is unreachable code the seed fold would silently agree with.
component RouteDuplicateHash (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  filter items by mode := when "on" (label == "x");
  route mode := when "#/" "all" then when "#/" "on";
  view := jsx% <main> [<ul> [<region items/>]];
}
