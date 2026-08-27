import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

component EventGuardLiteral (schema := S) where {
  state draft : String := "";
  event add := if trim draft == "x" then skip else (set draft "");
  view := jsx% <main> [<button type="button" onClick={add}> ["Add"]];
}
