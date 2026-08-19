import LeanRx.Region.Keyed

namespace LeanRx.Todo

open LeanRx.Region

structure Item where
  id : Nat
  title : String
  completed : Bool
deriving Repr, BEq

inductive Filter where
  | all
  | active
  | completed
deriving Repr, BEq, DecidableEq

def Filter.slug : Filter → String
  | .all => "all"
  | .active => "active"
  | .completed => "completed"

inductive Msg where
  | setNewTitle (value : String)
  | add
  | toggle (id : Nat)
  | delete (id : Nat)
  | clearCompleted
  | setFilter (filter : Filter)
  | startEditing (id : Nat)
  | setDraft (value : String)
  | commitEditing
  | cancelEditing
deriving Repr, BEq

structure State where
  private mk ::
  todos : List Item
  nextId : Nat
  filter : Filter
  editing : Option Nat
  draft : String
  newTitle : String
deriving Repr, BEq

def initial : State := ⟨[], 0, .all, none, "", ""⟩

private def trimmed (value : String) : String := value.trimAscii.toString

private def containsId (todos : List Item) (id : Nat) : Bool :=
  todos.any (·.id == id)

private def titleFor (todos : List Item) (id : Nat) : Option String :=
  todos.find? (·.id == id) |>.map (·.title)

private def updateTitle (todos : List Item) (id : Nat) (title : String) : List Item :=
  todos.map fun todo => if todo.id == id then { todo with title } else todo

private def deleteId (todos : List Item) (id : Nat) : List Item :=
  todos.filter (·.id != id)

def update (state : State) : Msg → State
  | .setNewTitle value => { state with newTitle := value }
  | .add =>
      let title := trimmed state.newTitle
      if title.isEmpty then state
      else { state with
        todos := state.todos ++ [{ id := state.nextId, title, completed := false }]
        nextId := state.nextId + 1
        newTitle := "" }
  | .toggle id =>
      { state with todos := state.todos.map fun todo =>
          if todo.id == id then { todo with completed := ¬todo.completed } else todo }
  | .delete id =>
      { state with
        todos := deleteId state.todos id
        editing := if state.editing == some id then none else state.editing
        draft := if state.editing == some id then "" else state.draft }
  | .clearCompleted =>
      let kept := state.todos.filter (¬·.completed)
      { state with
        todos := kept
        editing := state.editing.bind fun id => if containsId kept id then some id else none
        draft := state.editing.bind (titleFor kept) |>.getD "" }
  | .setFilter filter => { state with filter }
  | .startEditing id =>
      match titleFor state.todos id with
      | some title => { state with editing := some id, draft := title }
      | none => state
  | .setDraft value =>
      if state.editing.isSome then { state with draft := value } else state
  | .commitEditing =>
      match state.editing with
      | none => state
      | some id =>
          let title := trimmed state.draft
          { state with
            todos := if title.isEmpty then deleteId state.todos id
              else updateTitle state.todos id title
            editing := none
            draft := "" }
  | .cancelEditing => { state with editing := none, draft := "" }

def visible (state : State) : List Item :=
  match state.filter with
  | .all => state.todos
  | .active => state.todos.filter (¬·.completed)
  | .completed => state.todos.filter (·.completed)

def remaining (state : State) : Nat := state.todos.countP (¬·.completed)

def completedCount (state : State) : Nat := state.todos.countP (·.completed)

private def rowLogical (state : State) (todo : Item) : LogicalNode :=
  let editing := state.editing == some todo.id
  .element "li" [
    ("data-key", toString todo.id),
    ("class", if todo.completed then "completed" else "active"),
    ("data-editing", if editing then "true" else "false")
  ] [
    .text (if editing then state.draft else todo.title)
  ]

def keyedVisible (state : State) : Except Error KeyedList :=
  KeyedList.create <| visible state |>.map fun todo =>
    { key := todo.id, node := rowLogical state todo }

def logical (state : State) : LogicalNode :=
  .element "main" [("class", "leanrx-todo")] [
    .element "h1" [] [.text "Todos"],
    .element "input" [("value", state.newTitle)] [],
    .element "ul" [] (visible state |>.map (rowLogical state)),
    .element "footer" [("filter", state.filter.slug)] [
      .text s!"{remaining state} remaining",
      .text s!"{completedCount state} completed"
    ]
  ]

structure Spec where
  private mk ::
  name : String

namespace Spec

def create (name : String) : Spec := ⟨name⟩

structure Checked where
  private mk ::
  spec : Spec
  initial : State

def check (spec : Spec) : Except Error Checked :=
  if spec.name.isEmpty then .error {
    code := "LRX-REGION-002"
    message := "TodoMVC component name must not be empty"
  } else .ok ⟨spec, Todo.initial⟩

end Spec

end LeanRx.Todo
