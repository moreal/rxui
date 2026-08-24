import LeanRx

namespace LeanRxExamples.TodoMVC

open LeanRx LeanRx.Region
open LeanRx.Todo

def spec : Spec := Spec.create "LeanRx TodoMVC"

open scoped LeanRxDsl

/-- One todo row as a nested view component with typed props. The staged
logical value is identical to the library reference `Todo.rowLogical`. -/
def TodoRow (todo : Item) (editing : Bool) (draft : String) : LogicalNode :=
  jsx% <li dataKey={toString todo.id}
      class={if todo.completed then "completed" else "active"}
      dataEditing={if editing then "true" else "false"}> [
    { if editing then draft else todo.title }
  ]

/-- The visible rows through the keyed list surface syntax, lowered onto the
keyed region IR (`Region.KeyedItem`). -/
def rows (model : State) : List KeyedItem :=
  jsx% for todo in visible model key todo.id =>
    <TodoRow todo={todo} editing={model.editing == some todo.id}
      draft={model.draft}/>

/-- Keyed rows validated by the region IR's unique-key contract. -/
def keyedRows (model : State) : Except Error KeyedList :=
  KeyedList.create (rows model)

/-- TodoMVC's logical view written in the JSX surface: expanded whitelist
tags/attributes, dynamic text, a keyed list child, and a nested row
component. The value equals the library reference `Todo.logical`. -/
def todoView (componentName : String) (model : State) : LogicalNode :=
  jsx% <main class="leanrx-todo"> [
    <h1> [ {componentName} ],
    <input value={model.newTitle}/>,
    <ul> [
      for todo in visible model key todo.id =>
        <TodoRow todo={todo} editing={model.editing == some todo.id}
          draft={model.draft}/>
    ],
    <footer filter={model.filter.slug}> [
      { s!"{remaining model} items left" },
      { s!"{completedCount model} completed" }
    ]
  ]

end LeanRxExamples.TodoMVC
