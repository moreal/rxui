import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "n" Int .empty
def n : Field S Int := .here

component PulseFixture (schema := S) where {
  state n : Int := 0;
  prop title : String;
  view := jsx% <p> [{title}];
}

component ChildPropMismatch (schema := S) where {
  state n : Int := 0;
  view := jsx% <main> [<PulseFixture/>];
}
