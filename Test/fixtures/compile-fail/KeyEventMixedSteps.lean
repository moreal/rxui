import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component KeyEventMixedSteps (schema := S) where {
  state draft : String := "";
  event confirm (pressed : String) := when "Enter" (set draft "")
    then set draft "";
  view := jsx% <main> [<input ariaLabel="Draft" onKeyDown={confirm}/>];
}
