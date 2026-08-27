import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- The checked reflection demands a static type="checkbox" input — the
ADR-0049 origin rule in static scope (ADR-0060): the `checked` property
originates from checkbox inputs alone, so a list wrapper cannot carry it. -/
component CheckedOnNonCheckbox (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <ul ariaLabel="Items" checked={count roster == 0}> [<region roster/>]
  ];
}
