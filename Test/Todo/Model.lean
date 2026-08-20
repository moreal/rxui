import LeanRx.Todo.Model

namespace LeanRxTest.Todo.Model

open LeanRx.Todo

def run : IO Unit := do
  let one := update (update initial (.setNewTitle "  First  ")) .add
  let two := update (update one (.setNewTitle "Second")) .add
  unless two.todos.map (·.title) == ["First", "Second"] && two.nextId == 2 &&
      two.newTitle.isEmpty do
    throw <| IO.userError "Todo add/trim/identity semantics changed"
  let toggled := update two (.toggle 0)
  unless completedCount toggled == 1 && remaining toggled == 1 do
    throw <| IO.userError "Todo toggle counts changed"
  let active := update toggled (.setFilter .active)
  unless (visible active).map (·.id) == [1] do
    throw <| IO.userError "Todo active filter changed"
  let editing := update (update active (.startEditing 1)) (.setDraft " Edited ")
  let clearedWhileEditing := update editing .clearCompleted
  unless clearedWhileEditing.todos.map (·.id) == [1] &&
      clearedWhileEditing.editing == some 1 && clearedWhileEditing.draft == " Edited " do
    throw <| IO.userError "clear-completed discarded a retained edit draft"
  let committed := update editing .commitEditing
  unless committed.todos.map (·.title) == ["First", "Edited"] && committed.editing.isNone do
    throw <| IO.userError "Todo edit commit changed"
  let reversed := update committed .reverse
  unless reversed.todos.map (·.id) == [1, 0] do
    throw <| IO.userError "Todo reorder action changed"
  let cleared := update reversed .clearCompleted
  unless cleared.todos.map (·.id) == [1] && completedCount cleared == 0 do
    throw <| IO.userError "Todo clear-completed changed"
  let deletedByEmpty := update
    (update (update cleared (.startEditing 1)) (.setDraft "  ")) .commitEditing
  unless deletedByEmpty.todos.isEmpty do
    throw <| IO.userError "empty edit no longer deletes its Todo"
  match (Spec.create "").check with
  | .ok _ => throw <| IO.userError "empty TodoMVC component name was accepted"
  | .error error =>
      unless error.code == "LRX-REGION-002" do
        throw <| IO.userError "TodoMVC diagnostic changed"
  match keyedVisible two with
  | .error error => throw <| IO.userError s!"valid Todo keys failed: {error.code}"
  | .ok keyed =>
      unless keyed.keys == [0, 1] do
        throw <| IO.userError "Todo keyed projection changed"
  unless logical "LeanRx TodoMVC" reversed ==
      .element "main" [("class", "leanrx-todo")] [
        .element "h1" [] [.text "LeanRx TodoMVC"],
        .element "input" [("value", "")] [],
        .element "ul" [] [
          .element "li" [("data-key", "1"), ("class", "active"),
            ("data-editing", "false")] [.text "Edited"]],
        .element "footer" [("filter", "active")] [
          .text "1 items left", .text "1 completed"]] do
    throw <| IO.userError "Todo logical DOM projection changed"

end LeanRxTest.Todo.Model
