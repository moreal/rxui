import LeanRx

/-! ADR-0075: a row-composed child mounts one instance per row, so its own
template must not carry a static `id` attribute — unbounded instances would
duplicate document ids. The row lowering evaluates the child spec's template
predicate and rejects the reference (LRX-ELAB-135). -/

open LeanRx
open scoped LeanRxDsl

abbrev BadgeSchema : Schema := .field "hits" Int .empty
def hits : Field BadgeSchema Int := .here

component Badge (schema := BadgeSchema) where {
  state hits : Int := 0;
  prop tag : String;
  event hit := set hits (hits + 1);
  view := jsx% <div class="badge"> [
    <span id="badge-tag"> [{tag}],
    <button type="button" onClick={hit}> ["Hit"],
    <p class="badge-text"> [{"badgeText": rx% s!"Hits: {hits}"}]
  ];
}

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

component RowChildStaticId (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label ++ marks}],
      <Badge tag="x"/>
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
