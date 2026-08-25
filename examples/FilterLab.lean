import LeanRx

/-! Filter Lab dogfoods state-scoped attribute selection (ADR-0045): the
TodoMVC-shaped filter row is ordinary static view structure — three native
buttons with plain component events — whose `class` and `aria-pressed`
follow the selected filter through sealed selections
(`class={if filter == "all" then "selected" else ""}`,
`ariaPressed={filter == "all"}`), and a Reset button whose `disabled`
property reflects `filter == "all"` through the same mechanism. All seven
selections join the commit sweep beside text sinks and reflected properties
with the evaluate-compare-write shape, with no runtime ABI change. -/

namespace LeanRxExamples.FilterLab

open LeanRx

abbrev FilterSchema : Schema := .field "filter" String .empty

def filter : Field FilterSchema String := .here

open scoped LeanRxDsl

component FilterLab (schema := FilterSchema) where {
  state filter : String := "all";
  event showAll := set filter "all";
  event showActive := set filter "active";
  event showCompleted := set filter "completed";
  view := jsx% <main class="filter-lab"> [
    <h1> ["Filter Lab"],
    <div role="group" ariaLabel="Filters"> [
      <button type="button" onClick={showAll}
          class={if filter == "all" then "selected" else ""}
          ariaPressed={filter == "all"}> ["All"],
      <button type="button" onClick={showActive}
          class={if filter == "active" then "selected" else ""}
          ariaPressed={filter == "active"}> ["Active"],
      <button type="button" onClick={showCompleted}
          class={if filter == "completed" then "selected" else ""}
          ariaPressed={filter == "completed"}> ["Completed"]
    ],
    <button type="button" id="reset" onClick={showAll}
        disabled={filter == "all"}> ["Reset"],
    <p id="filter-text"> [{"filterText": rx% s!"Filter: {filter}"}]
  ];
}

end LeanRxExamples.FilterLab
