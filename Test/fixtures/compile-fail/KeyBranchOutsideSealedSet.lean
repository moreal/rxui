import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component KeyBranchOutsideSealedSet (schema := S) where {
  state mode : String := "all";
  row items keys (pressed : String) := when "Tab" (set label "tabbed");
  region items (label) := jsx% <li> [<span> [
    <input ariaLabel="Editor" onKeyDown={keys}/>]];
  view := jsx% <main> [<ul> [<region items/>]];
}
