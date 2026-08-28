import LeanRx

open LeanRx
open scoped LeanRxDsl

abbrev ChipSchema : Schema := .field "chips" Int .empty
def chips : Field ChipSchema Int := .here

component Chip (schema := ChipSchema) where {
  state chips : Int := 0;
  prop tag : String;
  event chip := set chips (chips + 1);
  view := jsx% <div class="chip"> [
    <span class="chip-tag"> [{tag}],
    <button type="button" onClick={chip}> ["Chip"],
    <p class="chip-text"> [{"chipText": rx% s!"Chips: {chips}"}]
  ];
}

/-- A checked component reference in the logical reference view used to die
with a raw unknown-identifier error (ADR-0073 OQ2); the logical fallback now
shares the typed guard and names the composition contract (ADR-0074). -/
def logicalWithSpec : LeanRx.Region.LogicalNode :=
  jsx% <main> [<Chip tag="x"/>]
