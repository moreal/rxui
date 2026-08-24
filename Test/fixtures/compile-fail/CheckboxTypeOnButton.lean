import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "note" String .empty
def note : Field S String := .here

component CheckboxTypeOnButton (schema := S) where {
  state note : String := "";
  event save := set note "saved";
  view := jsx% <button type="checkbox" onClick={save}> ["Bad"];
}
