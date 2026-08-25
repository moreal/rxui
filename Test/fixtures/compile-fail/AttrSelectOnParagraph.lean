import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "mode" String .empty
def mode : Field S String := .here

/- aria-pressed and disabled selections require a native button (ADR-0045). -/
component AttrSelectOnParagraph (schema := S) where {
  state mode : String := "a";
  event go := set mode "b";
  view := jsx% <main> [
    <button type="button" onClick={go}> ["Go"],
    <p disabled={mode == "a"}> ["Bad"]
  ];
}
