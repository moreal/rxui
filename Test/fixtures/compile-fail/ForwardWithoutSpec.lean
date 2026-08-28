import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component ForwardWithoutSpec (schema := S) where {
  state n : Int := 0;
  prop title : String;
  view := jsx% <main> [<Ghost label={title}/>];
}
