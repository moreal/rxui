import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component TypedEventIgnoresPayload (schema := S) where {
  state draft : String := "";
  event setDraft (value : String) := set draft other;
  view := jsx% <input onInput={setDraft} />;
}
