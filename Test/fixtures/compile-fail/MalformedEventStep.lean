import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "count" Int .empty
def count : Field S Int := .here

component MalformedEventStep (schema := S) where {
  state count : Int := 0;
  event broken := set count (count + 1) then count;
  view := jsx% <main> [<p> [{"countText": rx% s!"Count: {count}"}]];
}
