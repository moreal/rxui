import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A threshold literal is not a visibility subject for the predicate count
either: the sealed hidden reflection compares its row count — total or
predicate — against the zero literal only (ADR-0058/0059). -/
component HiddenPredicateThreshold (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items" hidden={count roster (done == "true") == 1}> [<region roster/>]
  ];
}
