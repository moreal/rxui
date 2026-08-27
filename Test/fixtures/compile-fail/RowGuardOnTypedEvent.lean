import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component RowGuardOnTypedEvent (schema := S) where {
  state mode : String := "all";
  row items chop (value : String) := if label == "" then remove else (set label value);
  region items (label) := jsx% <li> [<span> [
    <input ariaLabel="Editor" onInput={chop}/>]];
  view := jsx% <main> [<ul> [<region items/>]];
}
