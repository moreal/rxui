import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String (.field "tone" String .empty)
def mode : Field S String := .here
def tone : Field S String := .there .here

-- ADR-0081: `location.hash` is one string with one writer, and a route table
-- is a *total* function from that string onto its field's literals, so two
-- route items are two total functions over one string. The emission compiles
-- — arms, dispatch, seed, and write are all indexed by route — but the two
-- `if (changed[field])` write blocks race for the one hash inside a commit,
-- and one `hashchange` wakes both dispatches, the second reading the hash the
-- first just rewrote. Each unknown hash falls to a route's default arm, so the
-- loser's field is reset rather than left alone. The cap is the contract.
component RouteTwice (schema := S) where {
  state mode : String := "all";
  state tone : String := "all";
  region left (label) := jsx% <li> [<span> [{label}]];
  region right (label) := jsx% <li> [<span> [{label}]];
  filter left by mode := when "on" (label == "x");
  filter right by tone := when "hot" (label == "y");
  route mode := when "#/" "all" then when "#/on" "on";
  route tone := when "#/" "all" then when "#/hot" "hot";
  view := jsx% <main> [<ul> [<region left/>], <ul> [<region right/>]];
}
