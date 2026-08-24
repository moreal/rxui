import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component UnknownTypedEventBinding (schema := S) where {
  state draft : String := "";
  view := jsx% <input onInput="missing" />;
}
