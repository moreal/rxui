import LeanRx

/-! ADR-0091: the static-id rule follows the multiplication, not the module
boundary. A region mounts one instance of its row template per row, so an
`id` in that template mints one `roster-row` per row exactly as an
id-carrying row child would (`LRX-ELAB-135`) — the region validation rejects
it on the component's own template with `LRX-VIEW-046`, reading the same
`RowNode.hasStaticId` the ADR-0090 trail folds. The `id` on the `<ul>` in the
view is untouched: that element mounts once, so it stays the author's and the
axe gate's business (ADR-0071). -/

open LeanRx
open scoped LeanRxDsl

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

component RegionRowStaticId (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}") then set added (added + 1);
  region roster (label) := jsx%
    <li id="roster-row" class="roster-row"> [
      <span class="roster-label"> [{label}]
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
