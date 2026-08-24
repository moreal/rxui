import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component ReflectOnParagraph (schema := S) where {
  state draft : String := "";
  view := jsx% <p value={rx% draft}> ["Bad"];
}
