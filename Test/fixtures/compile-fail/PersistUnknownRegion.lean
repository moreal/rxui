import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component PersistUnknownRegion (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  persist ghost := "leanrx-fixture.items";
  view := jsx% <main> [<ul> [<region items/>]];
}
