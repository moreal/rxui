import LeanRx

/-! Echo Lab dogfoods the typed event payload surface (ADR-0037): `onInput`,
`onKeyDown`, and `onChange` bind M6 `TypedEventSpec` declarations by reference
and lower through the generic component backend onto the form-event host
adapters, next to an ordinary payload-less click event in the same component. -/

namespace LeanRxExamples.EchoLab

open LeanRx

abbrev EchoSchema : Schema :=
  .field "draft" String <| .field "lastKey" String <| .field "note" String <|
    .field "summary" String .empty

def draft : Field EchoSchema String := .here
def lastKey : Field EchoSchema String := .there .here
def note : Field EchoSchema String := .there (.there .here)
def summary : Field EchoSchema String := .there (.there (.there .here))

open scoped LeanRxDsl

component EchoLab (schema := EchoSchema) where {
  state draft : String := "";
  state lastKey : String := "";
  state note : String := "";
  derived summary := rx% if draft == "" then "(empty)" else draft;
  event clear := set draft "" then set note "";
  event setDraft (value : String) := set draft value;
  event recordKey (value : String) := set lastKey value;
  event commitNote (value : String) := set note value;
  view := jsx% <main class="echo-lab"> [
    <h1> ["Echo Lab"],
    <input id="draft" ariaLabel="Draft" onInput={setDraft} onKeyDown={recordKey} />,
    <input id="note" ariaLabel="Note" onChange={commitNote} />,
    <button type="button" onClick={clear}> ["Clear"],
    <p id="draft-text"> [{"draftText": rx% s!"Draft: {draft}"}],
    <p id="key-text"> [{"keyText": rx% s!"Key: {lastKey}"}],
    <p id="note-text"> [{"noteText": rx% s!"Note: {note}"}],
    <p id="summary-text"> [{"summaryText": rx% s!"Summary: {summary}"}]
  ];
}

end LeanRxExamples.EchoLab
