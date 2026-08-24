import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def count : Field S Int := .here

component UnsupportedStateLiteral (schema := S) where {
  state count : Float := 0;
  view := jsx% <main> [<p> [{"countText": rx% s!"Count: {count}"}]];
}
