import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A threshold literal is not a visibility subject: the sealed hidden
reflection compares the row total against the zero literal only — hiding
below a count is a different vocabulary nothing in TodoMVC needs
(ADR-0058). -/
component HiddenThresholdLiteral (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items" hidden={count roster == 1}> [<region roster/>]
  ];
}
