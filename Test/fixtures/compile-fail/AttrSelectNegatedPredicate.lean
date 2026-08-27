import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

/- Negation (and any composed predicate) is not a selection: the sealed
surface is one field, raw or behind trim, against one literal (ADR-0057). -/
component AttrSelectNegatedPredicate (schema := S) where {
  state draft : String := "";
  event go := set draft "";
  view := jsx% <main> [
    <button type="button" onClick={go} disabled={!(trim draft == "")}> ["Go"]
  ];
}
