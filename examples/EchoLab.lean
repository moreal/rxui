import LeanRx

/-! Echo Lab dogfoods the typed event payload surface (ADR-0037) and the
controlled-input surface (ADR-0038): `value={rx% …}`/`checked={rx% …}` reflect
sources back into the inputs through the commit sweep, `onCheckedChange` binds
a `Bool` typed event through `listenChecked`, and a `form` with `onSubmit`
commits the draft through the prevented-submit host adapter, next to the
per-keystroke `onInput`/`onKeyDown`, blur-committed `onChange`, and payload-less
click events that were already here. -/

namespace LeanRxExamples.EchoLab

open LeanRx

abbrev EchoSchema : Schema :=
  .field "draft" String <| .field "lastKey" String <| .field "note" String <|
    .field "loud" Bool <| .field "summary" String .empty

def draft : Field EchoSchema String := .here
def lastKey : Field EchoSchema String := .there .here
def note : Field EchoSchema String := .there (.there .here)
def loud : Field EchoSchema Bool := .there (.there (.there .here))
def summary : Field EchoSchema String := .there (.there (.there (.there .here)))

open scoped LeanRxDsl

component EchoLab (schema := EchoSchema) where {
  state draft : String := "";
  state lastKey : String := "";
  state note : String := "";
  state loud : Bool := false;
  derived summary := rx% if draft == "" then "(empty)" else (if loud then s!"{draft}!" else draft);
  event clear := set draft "" then set note "";
  event saveNote := set note draft;
  event setDraft (value : String) := set draft value;
  event recordKey (value : String) := set lastKey value;
  event commitNote (value : String) := set note value;
  event toggleLoud (checked : Bool) := set loud checked;
  view := jsx% <main class="echo-lab"> [
    <h1> ["Echo Lab"],
    <form onSubmit={saveNote}> [
      <input id="draft" ariaLabel="Draft" value={rx% draft} onInput={setDraft} onKeyDown={recordKey} />,
      <input id="loud" type="checkbox" ariaLabel="Loud" checked={rx% loud} onCheckedChange={toggleLoud} />,
      <button type="submit"> ["Save"]
    ],
    <input id="note" ariaLabel="Note" value={rx% note} onChange={commitNote} />,
    <button type="button" onClick={clear}> ["Clear"],
    <p id="draft-text"> [{"draftText": rx% s!"Draft: {draft}"}],
    <p id="key-text"> [{"keyText": rx% s!"Key: {lastKey}"}],
    <p id="note-text"> [{"noteText": rx% s!"Note: {note}"}],
    <p id="summary-text"> [{"summaryText": rx% s!"Summary: {summary}"}]
  ];
}

end LeanRxExamples.EchoLab
