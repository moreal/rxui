import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- Only the Bool checked payload may broadcast (ADR-0061): a String payload
flowing into a region broadcast is rejected — the delegated checked boolean
is the one payload the toggle-all parity needs, and it lowers to the
"true"/"false" strings exactly as the ADR-0049 row payload does. -/
component BroadcastPayloadString (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  event toggleAll (checked : String) := update roster (set done checked);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <input type="checkbox" ariaLabel="Toggle all" onCheckedChange={toggleAll}/>,
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
