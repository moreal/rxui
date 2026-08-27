import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component RowTrimGuardSubject (schema := S) where {
  state mode : String := "all";
  row items chop := if trim (draft ++ "!") == "" then remove else (set label "x");
  region items (label, draft) := jsx% <li> [<span> [
    <button type="button" onClick={chop}> ["c"]]];
  view := jsx% <main> [<ul> [<region items/>]];
}
