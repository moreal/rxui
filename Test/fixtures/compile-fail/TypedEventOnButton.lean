import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component TypedEventOnButton (schema := S) where {
  state draft : String := "";
  event setDraft (value : String) := set draft value;
  view := jsx% <button type="button" onInput={setDraft}> ["Bad"];
}
