import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

/- A predicate-count checked subject projects a declared row field: an
unknown field is rejected at the surface, where the region inventory
exists — the ADR-0050 count-predicate rule carried into the checked
reflection (ADR-0060). -/
component CheckedPredicateUnknownField (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "false")
    then set added (added + 1);
  region roster (label, done) := jsx% <li> [{label}];
  view := jsx% <main> [
    <button type="button" onClick={addItem}> ["Add"],
    <input type="checkbox" ariaLabel="Toggle all"
      checked={count roster (mode == "false") == 0}/>,
    <ul ariaLabel="Items"> [<region roster/>]
  ];
}
