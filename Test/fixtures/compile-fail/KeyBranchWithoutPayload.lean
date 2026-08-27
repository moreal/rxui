import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component KeyBranchWithoutPayload (schema := S) where {
  state mode : String := "all";
  row items keys := when "Enter" (set label "committed");
  region items (label) := jsx% <li> [<span> [
    <input ariaLabel="Editor" onKeyDown={keys}/>]];
  view := jsx% <main> [<ul> [<region items/>]];
}
