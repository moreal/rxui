import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

/- A selection subject is one state field, raw or behind the one sealed trim
unary (ADR-0057); any other applied head is a rejected general predicate. -/
component AttrSelectNonTrimHead (schema := S) where {
  state draft : String := "";
  event go := set draft "";
  view := jsx% <main> [
    <button type="button" onClick={go} disabled={lower draft == ""}> ["Go"]
  ];
}
