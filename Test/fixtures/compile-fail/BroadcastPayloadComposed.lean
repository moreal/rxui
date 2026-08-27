import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- The broadcast payload stands alone on a set right-hand side (ADR-0061):
trim, concatenation, comparison, and every other composition over the
payload identifier is rejected — the sealed row expressions gain the bare
payload reference and nothing else. -/
component BroadcastPayloadComposed (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  event toggleAll (checked : Bool) := update roster (set done (trim checked));
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <input type="checkbox" ariaLabel="Toggle all" onCheckedChange={toggleAll}/>,
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
