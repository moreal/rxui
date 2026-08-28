import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A threshold literal is not a label subject: the sealed count label
compares its count — total or predicate — against the one literal only.
The singular/plural flip is the whole parity; selecting text at other
thresholds is a different vocabulary nothing in TodoMVC needs
(ADR-0062). -/
component CountLabelThreshold (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <p> [{if count roster == 2 then " item left" else " items left"}],
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
