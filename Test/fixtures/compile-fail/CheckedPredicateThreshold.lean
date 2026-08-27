import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A threshold literal is not a checked subject either: the sealed toggle-all
checked reflection compares its row count — total or predicate — against the
zero literal only (ADR-0060). -/
component CheckedPredicateThreshold (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <input type="checkbox" ariaLabel="Toggle all"
      checked={count roster (done == "false") == 1}/>,
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
