import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "note" String .empty
def note : Field S String := .here

component SubmitOnButton (schema := S) where {
  state note : String := "";
  event save := set note "saved";
  view := jsx% <button type="button" onSubmit={save}> ["Bad"];
}
