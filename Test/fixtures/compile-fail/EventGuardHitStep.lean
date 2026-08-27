import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component EventGuardHitStep (schema := S) where {
  state draft : String := "";
  event add := if trim draft == "" then set draft "x" else (set draft "");
  view := jsx% <main> [<button type="button" onClick={add}> ["Add"]];
}
