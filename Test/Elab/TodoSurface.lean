import examples.TodoMVC

namespace LeanRxTest.Elab.TodoSurface

open LeanRx LeanRx.Region LeanRx.Todo LeanRxExamples.TodoMVC

private def scenarioStates : List State :=
  let first := update (update initial (.setNewTitle "First")) .add
  let second := update (update first (.setNewTitle "Second")) .add
  let third := update (update second
    (.setNewTitle "<img src=x onerror=\"globalThis.todoXss=true\">")) .add
  let toggled := update third (.toggle 0)
  let editing := update (update toggled (.startEditing 1)) (.setDraft " Edited ")
  let committed := update editing .commitEditing
  [ initial, first, second, third, toggled, editing, committed,
    update committed .reverse,
    update committed (.setFilter .active),
    update committed (.setFilter .completed),
    update committed .clearCompleted,
    update (update committed (.startEditing 2)) (.setDraft ""),
    update committed (.delete 1) ]

private def expectState (model : State) : IO Unit := do
  unless todoView "LeanRx TodoMVC" model == logical "LeanRx TodoMVC" model do
    throw <| IO.userError
      s!"JSX TodoMVC view diverged from the reference logical model: {repr model}"
  let dsl := keyedRows model
  let reference := keyedVisible model
  match dsl, reference with
  | .ok dslRows, .ok referenceRows =>
      unless dslRows.toList == referenceRows.toList do
        throw <| IO.userError "JSX keyed rows diverged from the reference keyed list"
  | .error dslError, .error referenceError =>
      unless dslError.code == referenceError.code do
        throw <| IO.userError "JSX keyed rows diverged on the failure code"
  | _, _ =>
      throw <| IO.userError "JSX keyed rows diverged on keyed-list validation"

/-- The user-surface JSX TodoMVC view must stay extensionally identical to the
library reference model that the browser differential gate projects. -/
def run : IO Unit := do
  for model in scenarioStates do
    expectState model
  unless (rows initial).isEmpty do
    throw <| IO.userError "JSX keyed rows must start empty"

end LeanRxTest.Elab.TodoSurface
