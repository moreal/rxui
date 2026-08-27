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
with row identity preserved.

The lab also dogfoods the ADR-0050 aggregates and broadcasts. The items-left
line carries both sealed count forms — `{count items (done == "false")}` is
the predicate count and `{count items}` the row total — recomputed by the
commit sweep whenever the region was touched and written through the
existing `setText` export. `completeAll` is a region broadcast
(`update items (set done "true")`): every row's `done` takes the sealed row
expression and the dirty reconcile re-renders every retained row — checkbox
and class selection follow with row identity preserved. `clearCompleted` is
the predicate removal (`remove items (done == "true")`): the reconcile
disposes exactly the done rows and the survivors keep their DOM nodes. All
three ride the existing region record and `update(items)` path — no host
change and no runtime ABI bump.

The ADR-0051 filter view selects which rows are displayed:
`filter items by filter := when "active" (done == "false") then
when "completed" (done == "true")` maps the `filter` state literals to
row-field equality predicates, and the unmatched `"all"` shows every row.
The commit sweep applies the table after the reconcile and drain — whenever
the region was touched or `filter` changed — by writing each row root's
`hidden` property through the existing `setProperty` export, navigating
`childAt(container, i)` from the container element recorded in the region
record's filter slot. Rows never mount or dispose on a filter change, so
row identity, focus, and the region metrics stay untouched, and the counts
keep reading the full row table — `items-left` is filter-independent by
construction. Still no host change and no runtime ABI bump.

The ADR-0052 key-branched row event closes the editor's keyboard loop:
`row items keys (pressed : String) := when "Enter" (…) then when "Escape"
(set draft label, set mode "view")` binds `onKeyDown={keys}` beside
`retype` — the declared parameter is the discriminant, named in the head and
compared implicitly by each arm, the ADR-0051 filter-table shape in row
scope. Enter commits the draft exactly as the OK button does; Escape
restores the draft from the pre-edit label (the retype writes are discarded,
and the next edit entry reflects the restored draft through the ADR-0047
value reflection); a key outside the sealed Enter/Escape set is a no-op —
no row scan, no `updateAt`, no region trace. The equality branches run
inside the generated dispatch function over the `eventKey` argument
`listenDelegatedCells` has passed since ABI 15, so once more: no host change
and no runtime ABI bump.

The ADR-0053 remove-if guard completes the editor with TodoMVC's
destroy-on-empty-commit: both commit paths — the OK button's `commit` event
and the Enter key arm — carry `if draft == "" then remove else (set label
draft, set mode "view")`, the sealed single-field guard whose hit removes
the dispatching row through the same kept-filter the ✕ button's `remove`
runs, and whose miss commits the assignments exactly as before. The guard
equality is evaluated inside the generated dispatch function against the
row resolved by the existing key scan, so a nonempty draft's commit is
byte-for-byte the unguarded sequence and an empty draft's Enter (or OK)
disposes the row through the ordinary dirty reconcile — row identity of the
survivors preserved. Escape stays unguarded: reverting an empty draft
restores the label instead of destroying the row. Still no host change and
no runtime ABI bump. -/

namespace LeanRxExamples.ToggleLab

open LeanRx

abbrev ToggleSchema : Schema := .field "added" Int <| .field "filter" String .empty

def added : Field ToggleSchema Int := .here
def filter : Field ToggleSchema String := .there .here

open scoped LeanRxDsl

component ToggleLab (schema := ToggleSchema) where {
  state added : Int := 0;
  state filter : String := "all";
  event addItem := append items (s!"Item {added}", s!"Item {added}", "false", "view")
    then set added (added + 1);
  event completeAll := update items (set done "true");
  event clearCompleted := remove items (done == "true");
  event showAll := set filter "all";
  event showActive := set filter "active";
  event showCompleted := set filter "completed";
  filter items by filter := when "active" (done == "false")
    then when "completed" (done == "true");
  row items toggle (checked : String) := set done checked;
  row items edit := set mode "edit";
  row items retype (value : String) := set draft value;
  row items commit := if draft == "" then remove else (set label draft, set mode "view");
  row items keys (pressed : String) :=
    when "Enter" (if draft == "" then remove else (set label draft, set mode "view"))
    then when "Escape" (set draft label, set mode "view");
  region items (label, draft, done, mode) := jsx%
    <li class={if done == "true" then "item-row done" else "item-row"}> [
      <span class="item-toggle"> [
        <input type="checkbox" ariaLabel="Toggle item" checked={done == "true"}
          onChange={toggle}/>
      ],
      {if mode == "view"
        then <span class="item-label" onDblClick={edit}> [{label}]
        else <input ariaLabel="Item editor" value={draft} onInput={retype}
          onKeyDown={keys} onDblClick={edit} autoFocus/>},
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
    <button type="button" onClick={completeAll}> ["Complete all"],
    <button type="button" onClick={clearCompleted}> ["Clear completed"],
    <button type="button" onClick={showAll}> ["Show all"],
    <button type="button" onClick={showActive}> ["Show active"],
    <button type="button" onClick={showCompleted}> ["Show completed"],
    <p id="toggle-text"> [{"itemText": rx% s!"Items added: {added}"}],
    <p id="items-left"> [
      <strong> [{count items (done == "false")}], " left of ", {count items}
    ],
    <ul id="items" ariaLabel="Items"> [<region items/>]
  ];
}

end LeanRxExamples.ToggleLab
