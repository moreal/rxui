import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A predicate count is not a visibility subject: the sealed hidden
reflection reads one declared region's total row count against the zero
literal and nothing else (ADR-0058). -/
component HiddenPredicateCount (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items" hidden={count roster (done == "true") == 0}> [<region roster/>]
  ];
}
