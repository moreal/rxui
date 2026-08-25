import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component IntImmutableProp (schema := S) where {
  state n : Int := 0;
  prop count : Int;
  view := jsx% <p> ["x"];
}
