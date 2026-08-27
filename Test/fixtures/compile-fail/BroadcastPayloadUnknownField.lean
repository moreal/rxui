import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A payload broadcast writes declared row fields only (ADR-0061): the set
target resolves against the region's declared field inventory exactly as the
plain ADR-0050 broadcast's does. -/
component BroadcastPayloadUnknownField (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  event toggleAll (checked : Bool) := update roster (set ghost checked);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <input type="checkbox" ariaLabel="Toggle all" onCheckedChange={toggleAll}/>,
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
