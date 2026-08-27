import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component KeyEventPayloadRef (schema := S) where {
  state draft : String := "";
  event confirm (pressed : String) := when "Enter" (set draft pressed);
  view := jsx% <main> [<input ariaLabel="Draft" onKeyDown={confirm}/>];
}
