import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

component PersistDuplicateKey (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  region notes (label) := jsx% <li> [<span> [{label}]];
  persist items := "leanrx-fixture.shared";
  persist notes := "leanrx-fixture.shared";
  view := jsx% <main> [<ul> [<region items/>], <ul> [<region notes/>]];
}
