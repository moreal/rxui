import LeanRx

/-! ADR-0090: `LRX-ELAB-135` answers about the composed child's whole mounted
tree, not about its own template alone. `Frame`'s own view is id-free, so the
ADR-0075 predicate admitted it — but `Frame` composes `Badge`, whose template
carries a static `id`, so a row mounting one `Frame` per row would mint one
`badge-tag` per row all the same. The row lowering never resolves `Badge`
here: it reads the trail `Frame` recorded when `Frame` itself elaborated, and
rejects the reference naming the path it found. -/

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

abbrev FrameSchema : Schema := .field "frames" Int .empty
def frames : Field FrameSchema Int := .here

component Frame (schema := FrameSchema) where {
  state frames : Int := 0;
  prop mark : String;
  event frame := set frames (frames + 1);
  view := jsx% <div class="frame"> [
    <span class="frame-mark"> [{mark}],
    <button type="button" onClick={frame}> ["Frame"],
    <Badge tag={mark}/>
  ];
}

abbrev S : Schema := .field "added" Int .empty
def added : Field S Int := .here

component RowChildNestedStaticId (schema := S) where {
  state added : Int := 0;
  event addItem := append roster (s!"Item {added}", "") then set added (added + 1);
  region roster (label, marks) := jsx%
    <li class="roster-row"> [
      <span class="roster-label"> [{label ++ marks}],
      <Frame mark="x"/>
    ];
  view := jsx% <main class="host"> [
    <button type="button" onClick={addItem}> ["Add item"],
    <ul id="roster" ariaLabel="Roster"> [<region roster/>]
  ];
}
