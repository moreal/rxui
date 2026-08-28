import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component PersistRegionTwice (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  persist items := "leanrx-fixture.items";
  persist items := "leanrx-fixture.other";
  view := jsx% <main> [<ul> [<region items/>]];
}
