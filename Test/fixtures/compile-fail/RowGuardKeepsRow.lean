import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component RowGuardKeepsRow (schema := S) where {
  state mode : String := "all";
  row items chop := if label == "" then set label "x" else (set label "y");
  region items (label) := jsx% <li> [<span> [
    <button type="button" onClick={chop}> ["c"]]];
  view := jsx% <main> [<ul> [<region items/>]];
}
