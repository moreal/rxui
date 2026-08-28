import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "draft" String .empty
def draft : Field S String := .here

/- A label branch is a static string literal, not an expression: the sealed
count label selects between exactly two mount-time strings, so state reads,
concatenation, and every other dynamic value never enter the text position
(ADR-0062). -/
component CountLabelDynamicBranch (schema := S) where {
  state draft : String := "";
  event addItem := append roster (draft, "false");
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <p> [{if count roster (done == "false") == 1 then draft else " items left"}],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
