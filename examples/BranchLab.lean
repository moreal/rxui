import LeanRx

/-! Branch Lab dogfoods the sealed two-branch row cell (ADR-0047) through the
generic component backend: each task row's first cell is
`{if mode == "view" then <span…/> else <input…/>}`, a sealed selection
between two statically sealed template subtrees on one row-field equality.
The emitter mounts the cell as one wrapper element holding the selected
subtree and marks the rendered branch on the wrapper (`$lrxBranch`, in the
`setKey` style); the retained-row update callback re-evaluates the predicate
and either updates the stable branch in place or replaces the subtree with
one `detach` plus one `append` of the freshly built branch (ADR-0047's
replacement composition, joined under ABI 16 by the ADR-0048 `focus` host
export). The edit input reflects the `draft` row
field into its `value` property (the sealed row reflection, reusing
ADR-0038's WHATWG equal-value caret no-op) and carries the sealed
`autoFocus` marker (ADR-0048): the update callback's replacement arm — and
only that arm — calls the `focus(node)` host export on the freshly mounted
input, so clicking Edit moves keyboard focus into the editor while row
mount, reorder, and the return to the view branch never touch focus.
Typing flows through the ADR-0046 delegated `input` payload: Edit copies
`label` into `draft` and enters the edit branch, `retype (value : String)`
drains one retained-row `updateAt` per keystroke with the caret preserved,
and OK commits `draft` back into `label` and returns to the view branch —
the TodoMVC edit/view transition with retained row identity. Delegated
bindings stay static across branches: the input binding lives in the edit
branch only and the view
branch contains no input (the ADR-0047 one-branch agreement rule), while
every click action sits in its own unbranched cell. Because the sealed cells
never hide, `draft` mirrors `label` outside editing (rows append with
`draft = label` and commit writes `label := draft`), so the always-visible
OK button is a no-op while a row is in the view branch. -/

namespace LeanRxExamples.BranchLab

open LeanRx

abbrev BranchSchema : Schema := .field "added" Int .empty

def added : Field BranchSchema Int := .here

open scoped LeanRxDsl

component BranchLab (schema := BranchSchema) where {
  state added : Int := 0;
  event addTask := append tasks (s!"Task {added}", s!"Task {added}", "view")
    then set added (added + 1);
  row tasks edit := set mode "edit" then set draft label;
  row tasks retype (value : String) := set draft value;
  row tasks commit := set label draft then set mode "view";
  region tasks (label, draft, mode) := jsx%
    <li class={if mode == "view" then "task-row" else "task-row editing"}> [
      {if mode == "view"
        then <span class="task-label"> [{label}]
        else <input ariaLabel="Task editor" value={draft} onInput={retype} autoFocus/>},
      <span class="task-edit"> [
        <button type="button" ariaLabel="Edit task" onClick={edit}> ["Edit"]
      ],
      <span class="task-commit"> [
        <button type="button" ariaLabel="Commit task" onClick={commit}> ["OK"]
      ],
      <span class="task-actions"> [
        <button type="button" ariaLabel="Remove task" onClick={remove}> ["✕"]
      ]
    ];
  view := jsx% <main class="branch-lab"> [
    <h1> ["Branch Lab"],
    <button type="button" onClick={addTask}> ["Add task"],
    <p id="branch-text"> [{"taskText": rx% s!"Tasks added: {added}"}],
    <ul id="tasks" ariaLabel="Tasks"> [<region tasks/>]
  ];
}

end LeanRxExamples.BranchLab
