import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

/- ADR-0082: `""` is a legal `localStorage` key — the browser stores under
it, enumerates it, and hands it back — so an empty key is not a runtime
error but an origin-wide collision every other unnamed writer joins, and a
same-arity foreign value hydrates as this region's own rows. The key is the
whole namespace guarantee, so the empty one is rejected at compile time. -/
component PersistEmptyKey (schema := S) where {
  state mode : String := "all";
  region items (label) := jsx% <li> [<span> [{label}]];
  persist items := "";
  view := jsx% <main> [<ul> [<region items/>]];
}
