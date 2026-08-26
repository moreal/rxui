import LeanRx

/-! Toggle Lab dogfoods the two ADR-0049 delegated row event kinds through
the generic component backend: TodoMVC's remaining row interactions on top
of the ADR-0047 branch cell and the ADR-0048 focus transfer. Double-clicking
an item's label enters the edit branch — `onDblClick={edit}` is the
payload-less `dblclick` kind, permitted on the non-button label because the
delegated dispatch is structural (no handler or tabindex ever lands on the
label element itself) — and the checkbox toggles the row's `done` field:
`onChange={toggle}` on the `type="checkbox"` input is the `checkedChange`
kind, whose delegated `checked` boolean lowers to the `"true"`/`"false"`
string payload, so `row items toggle (checked : String) := set done checked`
keeps the sealed `String` update language unchanged. Both kinds ride the
existing `listenDelegatedCells` export — two more listener registrations and
two more static action arrays, no host change and no runtime ABI bump.

The label dblclick takes `click`'s exact cross-branch agreement rule, so the
edit branch binds the same `edit` action on the editor input; because
`draft` mirrors `label` outside editing (rows append with `draft = label`
and commit writes `label := draft`) and `edit` only writes `mode`, a
dblclick inside the editor is an update no-op that cannot clobber the draft
(the ADR-0038 equal-value caret no-op keeps the caret in place). The
checkbox carries the sealed row checked reflection
(`checked={done == "true"}`, the ADR-0045 `disabled` shape in row scope), so
the toggle state survives the retained-row update sweep, appended rows mount
with their `done` state, and the delegated `change` is itself an equal-value
no-op on the checkbox it originated from. The row root's class selection
follows `done`, pinning that the toggle drains one retained-row `updateAt`
with row identity preserved. -/

namespace LeanRxExamples.ToggleLab

open LeanRx

abbrev ToggleSchema : Schema := .field "added" Int .empty

def added : Field ToggleSchema Int := .here

open scoped LeanRxDsl

component ToggleLab (schema := ToggleSchema) where {
  state added : Int := 0;
  event addItem := append items (s!"Item {added}", s!"Item {added}", "false", "view")
    then set added (added + 1);
  row items toggle (checked : String) := set done checked;
  row items edit := set mode "edit";
  row items retype (value : String) := set draft value;
  row items commit := set label draft then set mode "view";
  region items (label, draft, done, mode) := jsx%
    <li class={if done == "true" then "item-row done" else "item-row"}> [
      <span class="item-toggle"> [
        <input type="checkbox" ariaLabel="Toggle item" checked={done == "true"}
          onChange={toggle}/>
      ],
      {if mode == "view"
        then <span class="item-label" onDblClick={edit}> [{label}]
        else <input ariaLabel="Item editor" value={draft} onInput={retype}
          onDblClick={edit} autoFocus/>},
      <span class="item-commit"> [
        <button type="button" ariaLabel="Commit item" onClick={commit}> ["OK"]
      ],
      <span class="item-actions"> [
        <button type="button" ariaLabel="Remove item" onClick={remove}> ["✕"]
      ]
    ];
  view := jsx% <main class="toggle-lab"> [
    <h1> ["Toggle Lab"],
    <button type="button" onClick={addItem}> ["Add item"],
    <p id="toggle-text"> [{"itemText": rx% s!"Items added: {added}"}],
    <ul id="items" ariaLabel="Items"> [<region items/>]
  ];
}

end LeanRxExamples.ToggleLab
