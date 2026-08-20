import LeanRx.Backend.FormDom
import LeanRx.Backend.Manifest
import LeanRx.Todo.Model

namespace LeanRx.Backend.Todo

open LeanRx.Js
open LeanRx.Form

structure Emitted where
  private mk ::
  module : Module
  manifest : ComponentManifest
deriving Repr, BEq

private structure RuntimeNames where
  createElement : Ident
  createText : Ident
  setAttribute : Ident
  append : Ident
  childAt : Ident
  setText : Ident
  setProperty : Ident
  listen : Ident
  listenValue : Ident
  listenKey : Ident
  listenDelegated : Ident
  createConditionalRegion : Ident
  createPositionalRegion : Ident
  createKeyedRegion : Ident
  makeDisposer : Ident
  string : Ident
  bigInt : Ident

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))
private def bigint (value : Int) : Expr := .literal (.bigint value)

private def indexAt (target : Expr) (index : Nat) : Expr := .index target (uint index)
private def arrayAt (name : Ident) (index : Nat) : Expr := indexAt (.ident name) index
private def property (target : Expr) (name : String) : Expr :=
  .index target (.literal (.string name))
private def call (name : Ident) (args : List Expr) : Expr := .call (.ident name) (.ofList args)
private def callExpr (callee : Expr) (args : List Expr) : Expr := .call callee (.ofList args)
private def method (target : Expr) (name : String) (args : List Expr) : Expr :=
  callExpr (property target name) args

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def trace (metrics : Ident) (message : String) : Stmt :=
  .expr <| method (arrayAt metrics 7) "push" [.literal (.string message)]

/-- Closed compiler-owned DOM routing vocabulary. Generated data attributes are
strings, but no backend branch may introduce an unchecked action spelling. -/
private inductive DomAction where
  | toggle
  | edit
  | delete
  | save
  | cancel
  | editInput
  | filter

private def DomAction.slug : DomAction → String
  | .toggle => "toggle"
  | .edit => "edit"
  | .delete => "delete"
  | .save => "save"
  | .cancel => "cancel"
  | .editInput => "edit-input"
  | .filter => "filter"

private def DomAction.expr (action : DomAction) : Expr :=
  .literal (.string action.slug)

private def setAttribute (runtime : RuntimeNames) (node : Expr) (name : String)
    (value : Expr) : Stmt :=
  .expr <| call runtime.setAttribute [node, .literal (.string name), value]

private def setProperty (runtime : RuntimeNames) (node : Expr) (kind : DomProperty α)
    (value : Expr) : Stmt :=
  .expr <| FormDom.setProperty runtime.setProperty node kind value

private def runtimeNames : Except Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    append := ← Ident.checked "append"
    childAt := ← Ident.checked "childAt"
    setText := ← Ident.checked "setText"
    setProperty := ← Ident.checked "setProperty"
    listen := ← Ident.checked "listen"
    listenValue := ← Ident.checked "listenValue"
    listenKey := ← Ident.checked "listenKey"
    listenDelegated := ← Ident.checked "listenDelegated"
    createConditionalRegion := ← Ident.checked "createConditionalRegion"
    createPositionalRegion := ← Ident.checked "createPositionalRegion"
    createKeyedRegion := ← Ident.checked "createKeyedRegion"
    makeDisposer := ← Ident.checked "makeDisposer"
    string := ← Ident.checked "String"
    bigInt := ← Ident.checked "BigInt"
  }

private def actionAttrs (runtime : RuntimeNames) (node : Ident) (action : DomAction)
    (key : Expr) : List Stmt := [
  setAttribute runtime (.ident node) "data-lrx-action" action.expr,
  setAttribute runtime (.ident node) "data-lrx-key" key
]

private def countedActionAttrs (runtime : RuntimeNames) (metrics node : Ident)
    (action : DomAction) (key : Expr) : List Stmt :=
  actionAttrs runtime node action key ++ [incrementAt metrics 6, incrementAt metrics 6]

private def branchMountFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_mountTodoBranch"
  let editing ← Ident.checked "editing"
  let item ← Ident.checked "item"
  let root ← Ident.checked "branchRoot"
  let checkbox ← Ident.checked "checkbox"
  let label ← Ident.checked "label"
  let labelText ← Ident.checked "labelText"
  let edit ← Ident.checked "edit"
  let editText ← Ident.checked "editText"
  let remove ← Ident.checked "remove"
  let removeText ← Ident.checked "removeText"
  let input ← Ident.checked "editInput"
  let save ← Ident.checked "save"
  let saveText ← Ident.checked "saveText"
  let cancel ← Ident.checked "cancel"
  let cancelText ← Ident.checked "cancelText"
  let metrics ← Ident.checked "metrics"
  let key := call runtime.string [indexAt (.ident item) 0]
  pure {
    name
    params := #[editing, item]
    body := #[
      .const metrics (indexAt (.ident item) 5),
      .const root (call runtime.createElement [.literal (.string "div")]),
      setAttribute runtime (.ident root) "class"
        (.conditional (.ident editing) (.literal (.string "todo-edit"))
          (.literal (.string "todo-view"))),
      incrementAt metrics 6,
      .ifThen (.unary .not <| .ident editing) <| .ofList <| [
        .const checkbox (call runtime.createElement [.literal (.string "input")]),
        setAttribute runtime (.ident checkbox) "type" (.literal (.string "checkbox")),
        incrementAt metrics 6,
        setAttribute runtime (.ident checkbox) "aria-label" (indexAt (.ident item) 1),
        incrementAt metrics 6,
        setProperty runtime (.ident checkbox) DomProperty.checked (indexAt (.ident item) 2),
        incrementAt metrics 6
      ] ++ countedActionAttrs runtime metrics checkbox .toggle key ++ [
        .expr <| call runtime.append [.ident root, .ident checkbox],
        .const label (call runtime.createElement [.literal (.string "span")]),
        .const labelText (call runtime.createText [indexAt (.ident item) 1]),
        .expr <| call runtime.append [.ident label, .ident labelText],
        .expr <| call runtime.append [.ident root, .ident label],
        .const edit (call runtime.createElement [.literal (.string "button")]),
        setAttribute runtime (.ident edit) "type" (.literal (.string "button")),
        incrementAt metrics 6,
        .const editText (call runtime.createText [.literal (.string "Edit")]),
        .expr <| call runtime.append [.ident edit, .ident editText]
      ] ++ countedActionAttrs runtime metrics edit .edit key ++ [
        .expr <| call runtime.append [.ident root, .ident edit],
        .const remove (call runtime.createElement [.literal (.string "button")]),
        setAttribute runtime (.ident remove) "type" (.literal (.string "button")),
        incrementAt metrics 6,
        .const removeText (call runtime.createText [.literal (.string "Delete")]),
        .expr <| call runtime.append [.ident remove, .ident removeText]
      ] ++ countedActionAttrs runtime metrics remove .delete key ++ [
        .expr <| call runtime.append [.ident root, .ident remove]
      ],
      .ifThen (.ident editing) <| .ofList <| [
        .const input (call runtime.createElement [.literal (.string "input")]),
        setAttribute runtime (.ident input) "type" (.literal (.string "text")),
        incrementAt metrics 6,
        setAttribute runtime (.ident input) "aria-label" (.literal (.string "Edit todo")),
        incrementAt metrics 6,
        setProperty runtime (.ident input) DomProperty.value (indexAt (.ident item) 4),
        incrementAt metrics 6
      ] ++ countedActionAttrs runtime metrics input .editInput key ++ [
        .expr <| call runtime.append [.ident root, .ident input],
        .const save (call runtime.createElement [.literal (.string "button")]),
        setAttribute runtime (.ident save) "type" (.literal (.string "button")),
        incrementAt metrics 6,
        .const saveText (call runtime.createText [.literal (.string "Save")]),
        .expr <| call runtime.append [.ident save, .ident saveText]
      ] ++ countedActionAttrs runtime metrics save .save key ++ [
        .expr <| call runtime.append [.ident root, .ident save],
        .const cancel (call runtime.createElement [.literal (.string "button")]),
        setAttribute runtime (.ident cancel) "type" (.literal (.string "button")),
        incrementAt metrics 6,
        .const cancelText (call runtime.createText [.literal (.string "Cancel")]),
        .expr <| call runtime.append [.ident cancel, .ident cancelText]
      ] ++ countedActionAttrs runtime metrics cancel .cancel key ++ [
        .expr <| call runtime.append [.ident root, .ident cancel]
      ],
      .return (.ident root)
    ]
  }

private def branchUpdateFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_updateTodoBranch"
  let root ← Ident.checked "branchRoot"
  let editing ← Ident.checked "editing"
  let item ← Ident.checked "item"
  let checkbox ← Ident.checked "checkbox"
  let label ← Ident.checked "label"
  let labelText ← Ident.checked "labelText"
  let input ← Ident.checked "editInput"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[root, editing, item]
    body := #[
      .const metrics (indexAt (.ident item) 5),
      .ifThen (.unary .not <| .ident editing) <| .ofList <| [
        .const checkbox (call runtime.childAt [.ident root, uint 0]),
        setAttribute runtime (.ident checkbox) "aria-label" (indexAt (.ident item) 1),
        incrementAt metrics 6,
        setProperty runtime (.ident checkbox) DomProperty.checked (indexAt (.ident item) 2),
        incrementAt metrics 6,
        .const label (call runtime.childAt [.ident root, uint 1]),
        .const labelText (call runtime.childAt [.ident label, uint 0]),
        .expr <| call runtime.setText [.ident labelText, indexAt (.ident item) 1],
        incrementAt metrics 6
      ],
      .ifThen (.ident editing) <| .ofList <| [
        .const input (call runtime.childAt [.ident root, uint 0]),
        setProperty runtime (.ident input) DomProperty.value (indexAt (.ident item) 4),
        incrementAt metrics 6
      ],
      .return (.literal .null)
    ]
  }

private def branchDisposeFunction : Except Error Function := do
  pure {
    name := ← Ident.checked "$lrx_disposeTodoBranch"
    params := #[← Ident.checked "branchRoot", ← Ident.checked "editing"]
    body := #[.return (.literal .null)]
  }

private def rowRootFunction : Except Error Function := do
  let handle ← Ident.checked "handle"
  pure {
    name := ← Ident.checked "$lrx_todoRowRoot"
    params := #[handle]
    body := #[.return (indexAt (.ident handle) 0)]
  }

private def rowMountFunction (runtime : RuntimeNames) (mountBranch updateBranch disposeBranch : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_mountTodoRow"
  let item ← Ident.checked "item"
  let index ← Ident.checked "index"
  let row ← Ident.checked "row"
  let region ← Ident.checked "branchRegion"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[item, index]
    body := #[
      .const metrics (indexAt (.ident item) 5),
      .const row (call runtime.createElement [.literal (.string "li")]),
      setAttribute runtime (.ident row) "data-todo-id" (call runtime.string [indexAt (.ident item) 0]),
      incrementAt metrics 6,
      setAttribute runtime (.ident row) "class"
        (.conditional (indexAt (.ident item) 2) (.literal (.string "completed"))
          (.literal (.string "active"))),
      incrementAt metrics 6,
      .const region (call runtime.createConditionalRegion [
        .ident row, .ident mountBranch, .ident updateBranch, .ident disposeBranch]),
      .expr <| method (.ident region) "update" [indexAt (.ident item) 3, .ident item],
      .return (.array <| .ofList [.ident row, .ident region])
    ]
  }

private def rowUpdateFunction (runtime : RuntimeNames) : Except Error Function := do
  let handle ← Ident.checked "handle"
  let item ← Ident.checked "item"
  let index ← Ident.checked "index"
  let row ← Ident.checked "row"
  let region ← Ident.checked "branchRegion"
  let metrics ← Ident.checked "metrics"
  pure {
    name := ← Ident.checked "$lrx_updateTodoRow"
    params := #[handle, item, index]
    body := #[
      .const metrics (indexAt (.ident item) 5),
      .const row (indexAt (.ident handle) 0),
      .const region (indexAt (.ident handle) 1),
      setAttribute runtime (.ident row) "data-todo-id" (call runtime.string [indexAt (.ident item) 0]),
      incrementAt metrics 6,
      setAttribute runtime (.ident row) "class"
        (.conditional (indexAt (.ident item) 2) (.literal (.string "completed"))
          (.literal (.string "active"))),
      incrementAt metrics 6,
      .expr <| method (.ident region) "update" [indexAt (.ident item) 3, .ident item],
      .return (.literal .null)
    ]
  }

private def rowDisposeFunction : Except Error Function := do
  let handle ← Ident.checked "handle"
  let key ← Ident.checked "key"
  pure {
    name := ← Ident.checked "$lrx_disposeTodoRow"
    params := #[handle, key]
    body := #[
      .expr <| method (indexAt (.ident handle) 1) "dispose" [],
      .return (.literal .null)
    ]
  }

private def filterMountFunction (runtime : RuntimeNames) : Except Error Function := do
  let item ← Ident.checked "item"
  let index ← Ident.checked "index"
  let button ← Ident.checked "button"
  let text ← Ident.checked "text"
  let metrics ← Ident.checked "metrics"
  pure {
    name := ← Ident.checked "$lrx_mountFilter"
    params := #[item, index]
    body := #[
      .const metrics (indexAt (.ident item) 3),
      .const button (call runtime.createElement [.literal (.string "button")]),
      setAttribute runtime (.ident button) "type" (.literal (.string "button")),
      incrementAt metrics 6,
      setAttribute runtime (.ident button) "data-lrx-action" DomAction.filter.expr,
      incrementAt metrics 6,
      setAttribute runtime (.ident button) "data-lrx-key" (indexAt (.ident item) 0),
      incrementAt metrics 6,
      setAttribute runtime (.ident button) "aria-pressed"
        (.conditional (indexAt (.ident item) 2) (.literal (.string "true"))
          (.literal (.string "false"))),
      incrementAt metrics 6,
      .const text (call runtime.createText [indexAt (.ident item) 1]),
      .expr <| call runtime.append [.ident button, .ident text],
      .return (.ident button)
    ]
  }

private def filterUpdateFunction (runtime : RuntimeNames) : Except Error Function := do
  let button ← Ident.checked "button"
  let item ← Ident.checked "item"
  let index ← Ident.checked "index"
  let metrics ← Ident.checked "metrics"
  pure {
    name := ← Ident.checked "$lrx_updateFilter"
    params := #[button, item, index]
    body := #[
      .const metrics (indexAt (.ident item) 3),
      setAttribute runtime (.ident button) "aria-pressed"
        (.conditional (indexAt (.ident item) 2) (.literal (.string "true"))
          (.literal (.string "false"))),
      incrementAt metrics 6,
      .return (.literal .null)
    ]
  }

private def filterDisposeFunction : Except Error Function := do
  pure {
    name := ← Ident.checked "$lrx_disposeFilter"
    params := #[← Ident.checked "button"]
    body := #[.return (.literal .null)]
  }

private def renderName : Except Error Ident := Ident.checked "$lrx_renderTodo"

private def renderFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← renderName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let keyed ← Ident.checked "keyedRegion"
  let filters ← Ident.checked "filterRegion"
  let statusText ← Ident.checked "statusText"
  let metrics ← Ident.checked "metrics"
  let todo ← Ident.checked "todo"
  let items ← Ident.checked "items"
  let remaining ← Ident.checked "remaining"
  let regionMetrics ← Ident.checked "regionMetrics"
  let visible := .binary .or
    (.binary .eq (arrayAt state 2) (.literal (.string "all"))) <|
    .binary .or
      (.binary .and (.binary .eq (arrayAt state 2) (.literal (.string "active")))
        (.unary .not <| indexAt (.ident todo) 2))
      (.binary .and (.binary .eq (arrayAt state 2) (.literal (.string "completed")))
        (indexAt (.ident todo) 2))
  let rowItem := .array <| .ofList [
    indexAt (.ident todo) 0, indexAt (.ident todo) 1, indexAt (.ident todo) 2,
    .binary .eq (arrayAt state 3) (indexAt (.ident todo) 0), arrayAt state 4,
    .ident metrics]
  let filterItems := .array <| .ofList [
    .array <| .ofList [.literal (.string "all"), .literal (.string "All"),
      .binary .eq (arrayAt state 2) (.literal (.string "all")), .ident metrics],
    .array <| .ofList [.literal (.string "active"), .literal (.string "Active"),
      .binary .eq (arrayAt state 2) (.literal (.string "active")), .ident metrics],
    .array <| .ofList [.literal (.string "completed"), .literal (.string "Completed"),
      .binary .eq (arrayAt state 2) (.literal (.string "completed")), .ident metrics]
  ]
  pure {
    name
    params := #[state, context]
    body := #[
      .const keyed (arrayAt context 0),
      .const filters (arrayAt context 1),
      .const statusText (arrayAt context 2),
      .const metrics (arrayAt context 4),
      .const items (.array .nil),
      .const remaining (.array <| .ofList [uint 0]),
      .forOf todo (arrayAt state 0) <| .ofList [
        .ifThen (.unary .not <| indexAt (.ident todo) 2) <| .ofList [
          .assign (.index (.ident remaining) (uint 0))
            (.binary .add (indexAt (.ident remaining) 0) (uint 1))
        ],
        .ifThen visible <| .ofList [
          .expr <| method (.ident items) "push" [rowItem]
        ]
      ],
      .expr <| method (.ident keyed) "update" [.ident items],
      .expr <| method (.ident filters) "update" [filterItems],
      .expr <| call runtime.setText [.ident statusText,
        .binary .add (call runtime.string [indexAt (.ident remaining) 0])
          (.literal (.string " items left"))],
      incrementAt metrics 5,
      incrementAt metrics 5,
      incrementAt metrics 5,
      incrementAt metrics 6,
      trace metrics "todo:render",
      .const regionMetrics (method (.ident keyed) "instrumentation" []),
      .return (.ident regionMetrics)
    ]
  }

private def eventFinish (render state context metrics : Ident) (name : String) : List Stmt := [
  incrementAt metrics 1,
  trace metrics s!"event:{name}",
  .expr <| call render [.ident state, .ident context],
  .return (.literal .null)
]

private def newInputFunction : Except Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let value ← Ident.checked "value"
  let metrics ← Ident.checked "metrics"
  pure {
    name := ← Ident.checked "$lrx_todoNewInput"
    params := #[state, context, value]
    body := #[
      .const metrics (arrayAt context 4),
      .assign (.index (.ident state) (uint 5)) (.ident value),
      incrementAt metrics 2,
      incrementAt metrics 1,
      trace metrics "event:newTitle:input",
      .return (.literal .null)
    ]
  }

private def addFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_todoAdd"
  let render ← renderName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let title ← Ident.checked "title"
  let trim := method (arrayAt state 5) "replace"
    [.literal .asciiTrimPattern, .literal (.string "")]
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 4),
      .const title trim,
      .ifThen (.unary .not <| .binary .eq (.ident title) (.literal (.string ""))) <| .ofList [
        .expr <| method (arrayAt state 0) "push" [
          .array <| .ofList [arrayAt state 1, .ident title,
            .literal (.boolean false)]],
        .assign (.index (.ident state) (uint 1)) (.binary .add (arrayAt state 1) (bigint 1)),
        .assign (.index (.ident state) (uint 5)) (.literal (.string "")),
        incrementAt metrics 2,
        incrementAt metrics 2,
        incrementAt metrics 2,
        setProperty runtime (arrayAt context 3) DomProperty.value (.literal (.string "")),
        incrementAt metrics 6
      ]
    ] ++ (eventFinish render state context metrics "add").toArray
  }

private def newKeyFunction (add : Ident) : Except Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let key ← Ident.checked "key"
  pure {
    name := ← Ident.checked "$lrx_todoNewKey"
    params := #[state, context, key]
    body := #[
      .ifThen (.binary .eq (.ident key) (.literal (.string "Enter"))) <| .ofList [
        .expr <| call add [.ident state, .ident context]
      ],
      .return (.literal .null)
    ]
  }

private structure DelegatedNames where
  state : Ident
  context : Ident
  action : Ident
  keyText : Ident
  value : Ident
  checked : Ident
  keyName : Ident
  metrics : Ident
  id : Ident

private def delegatedNames : Except Error DelegatedNames := do
  pure {
    state := ← Ident.checked "state"
    context := ← Ident.checked "context"
    action := ← Ident.checked "action"
    keyText := ← Ident.checked "keyText"
    value := ← Ident.checked "value"
    checked := ← Ident.checked "checked"
    keyName := ← Ident.checked "keyName"
    metrics := ← Ident.checked "metrics"
    id := ← Ident.checked "id"
  }

private def delegatedParams (names : DelegatedNames) : Array Ident :=
  #[names.state, names.context, names.action, names.keyText, names.value,
    names.checked, names.keyName]

private def clickFunction (runtime : RuntimeNames) : Except Error Function := do
  let names ← delegatedNames
  let name ← Ident.checked "$lrx_todoClick"
  let render ← renderName
  let todo ← Ident.checked "todo"
  let nextTodos ← Ident.checked "nextTodos"
  let title ← Ident.checked "title"
  let idExpr := call runtime.bigInt [.ident names.keyText]
  pure {
    name
    params := delegatedParams names
    body := #[
      .const names.metrics (arrayAt names.context 4),
      .const names.id idExpr,
      .ifThen (.binary .or
          (.binary .eq (.ident names.action) DomAction.toggle.expr)
          (.binary .eq (.ident names.action) DomAction.editInput.expr)) <|
        .ofList [.return (.literal .null)],
      .ifThen (.binary .eq (.ident names.action) DomAction.edit.expr) <| .ofList [
        .forOf todo (arrayAt names.state 0) <| .ofList [
          .ifThen (.binary .eq (indexAt (.ident todo) 0) (.ident names.id)) <| .ofList [
            .assign (.index (.ident names.state) (uint 3)) (.ident names.id),
            .assign (.index (.ident names.state) (uint 4)) (indexAt (.ident todo) 1),
            incrementAt names.metrics 2,
            incrementAt names.metrics 2
          ]
        ]
      ],
      .ifThen (.binary .eq (.ident names.action) DomAction.delete.expr) <| .ofList [
        .const nextTodos (.array .nil),
        .forOf todo (arrayAt names.state 0) <| .ofList [
          .ifThen (.unary .not <| .binary .eq (indexAt (.ident todo) 0) (.ident names.id)) <|
            .ofList [.expr <| method (.ident nextTodos) "push" [.ident todo]]
        ],
        .assign (.index (.ident names.state) (uint 0)) (.ident nextTodos),
        incrementAt names.metrics 2,
        .ifThen (.binary .eq (arrayAt names.state 3) (.ident names.id)) <| .ofList [
          .assign (.index (.ident names.state) (uint 3)) (bigint (-1)),
          .assign (.index (.ident names.state) (uint 4)) (.literal (.string "")),
          incrementAt names.metrics 2,
          incrementAt names.metrics 2
        ]
      ],
      .ifThen (.binary .eq (.ident names.action) DomAction.save.expr) <| .ofList [
        .const title (method (arrayAt names.state 4) "replace"
          [.literal .asciiTrimPattern, .literal (.string "")]),
        .const nextTodos (.array .nil),
        .forOf todo (arrayAt names.state 0) <| .ofList [
          .ifThen (.binary .or
              (.unary .not <| .binary .eq (indexAt (.ident todo) 0) (.ident names.id))
              (.unary .not <| .binary .eq (.ident title) (.literal (.string "")))) <|
            .ofList [
              .ifThen (.binary .eq (indexAt (.ident todo) 0) (.ident names.id)) <| .ofList [
                .assign (.index (.ident todo) (uint 1)) (.ident title),
                incrementAt names.metrics 2
              ],
              .expr <| method (.ident nextTodos) "push" [.ident todo]
            ]
        ],
        .assign (.index (.ident names.state) (uint 0)) (.ident nextTodos),
        .assign (.index (.ident names.state) (uint 3)) (bigint (-1)),
        .assign (.index (.ident names.state) (uint 4)) (.literal (.string "")),
        incrementAt names.metrics 2,
        incrementAt names.metrics 2,
        incrementAt names.metrics 2
      ],
      .ifThen (.binary .eq (.ident names.action) DomAction.cancel.expr) <| .ofList [
        .assign (.index (.ident names.state) (uint 3)) (bigint (-1)),
        .assign (.index (.ident names.state) (uint 4)) (.literal (.string "")),
        incrementAt names.metrics 2,
        incrementAt names.metrics 2
      ]
    ] ++ (eventFinish render names.state names.context names.metrics "todoClick").toArray
  }

private def changeFunction (runtime : RuntimeNames) : Except Error Function := do
  let names ← delegatedNames
  let render ← renderName
  let todo ← Ident.checked "todo"
  pure {
    name := ← Ident.checked "$lrx_todoChange"
    params := delegatedParams names
    body := #[
      .const names.metrics (arrayAt names.context 4),
      .const names.id (call runtime.bigInt [.ident names.keyText]),
      .ifThen (.binary .eq (.ident names.action) DomAction.toggle.expr) <| .ofList [
        .forOf todo (arrayAt names.state 0) <| .ofList [
          .ifThen (.binary .eq (indexAt (.ident todo) 0) (.ident names.id)) <| .ofList [
            .assign (.index (.ident todo) (uint 2))
              (.unary .not <| indexAt (.ident todo) 2)
            , incrementAt names.metrics 2
          ]
        ]
      ]
    ] ++ (eventFinish render names.state names.context names.metrics "todoChange").toArray
  }

private def inputFunction : Except Error Function := do
  let names ← delegatedNames
  pure {
    name := ← Ident.checked "$lrx_todoInput"
    params := delegatedParams names
    body := #[
      .const names.metrics (arrayAt names.context 4),
      .ifThen (.binary .eq (.ident names.action) DomAction.editInput.expr) <| .ofList [
        .assign (.index (.ident names.state) (uint 4)) (.ident names.value),
        incrementAt names.metrics 2,
        incrementAt names.metrics 1,
        trace names.metrics "event:todoEditInput"
      ],
      .return (.literal .null)
    ]
  }

private def keyFunction (click : Ident) : Except Error Function := do
  let names ← delegatedNames
  let save := DomAction.save.expr
  let cancel := DomAction.cancel.expr
  pure {
    name := ← Ident.checked "$lrx_todoKey"
    params := delegatedParams names
    body := #[
      .ifThen (.binary .eq (.ident names.action) DomAction.editInput.expr) <|
        .ofList [
          .ifThen (.binary .eq (.ident names.keyName) (.literal (.string "Enter"))) <| .ofList [
            .expr <| call click [.ident names.state, .ident names.context, save,
              .ident names.keyText, .ident names.value, .ident names.checked,
              .ident names.keyName]
          ],
          .ifThen (.binary .eq (.ident names.keyName) (.literal (.string "Escape"))) <| .ofList [
            .expr <| call click [.ident names.state, .ident names.context, cancel,
              .ident names.keyText, .ident names.value, .ident names.checked,
              .ident names.keyName]
          ]
        ],
      .return (.literal .null)
    ]
  }

private def filterFunction : Except Error Function := do
  let names ← delegatedNames
  let render ← renderName
  pure {
    name := ← Ident.checked "$lrx_todoFilter"
    params := delegatedParams names
    body := #[
      .const names.metrics (arrayAt names.context 4),
      .ifThen (.binary .eq (.ident names.action) DomAction.filter.expr) <| .ofList [
        .assign (.index (.ident names.state) (uint 2)) (.ident names.keyText),
        incrementAt names.metrics 2
      ]
    ] ++ (eventFinish render names.state names.context names.metrics "filter").toArray
  }

private def clearFunction : Except Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let todos ← Ident.checked "todos"
  let todo ← Ident.checked "todo"
  let editingKept ← Ident.checked "editingKept"
  let render ← renderName
  pure {
    name := ← Ident.checked "$lrx_todoClear"
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 4),
      .const todos (.array .nil),
      .const editingKept (.array <| .ofList [.literal (.boolean false)]),
      .forOf todo (arrayAt state 0) <| .ofList [
        .ifThen (.unary .not <| indexAt (.ident todo) 2) <| .ofList [
          .expr <| method (.ident todos) "push" [.ident todo],
          .ifThen (.binary .eq (indexAt (.ident todo) 0) (arrayAt state 3)) <| .ofList [
            .assign (.index (.ident editingKept) (uint 0)) (.literal (.boolean true))
          ]
        ]
      ],
      .assign (.index (.ident state) (uint 0)) (.ident todos),
      incrementAt metrics 2,
      .ifThen (.unary .not <| indexAt (.ident editingKept) 0) <| .ofList [
        .assign (.index (.ident state) (uint 3)) (bigint (-1)),
        .assign (.index (.ident state) (uint 4)) (.literal (.string "")),
        incrementAt metrics 2,
        incrementAt metrics 2
      ]
    ] ++ (eventFinish render state context metrics "clearCompleted").toArray
  }

private def reverseFunction : Except Error Function := do
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let render ← renderName
  pure {
    name := ← Ident.checked "$lrx_todoReverse"
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 4),
      .assign (.index (.ident state) (uint 0)) (method (arrayAt state 0) "slice" []),
      .expr <| method (arrayAt state 0) "reverse" [],
      incrementAt metrics 2
    ] ++ (eventFinish render state context metrics "reverse").toArray
  }

private def hash (value : String) : Nat :=
  value.toList.foldl
    (fun current char => (current * 16777619 + char.toNat) % 4294967296) 2166136261

private def manifest (moduleName : String) (checked : LeanRx.Todo.Spec.Checked) :
    ComponentManifest :=
  { compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := toString (hash checked.spec.name)
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := #[.list (.record "TodoItem"), .nat, .string, .int, .string, .string]
    sourceCount := 6
    derivedCount := 0
    textSinkCount := 2
    eventCount := 10
    hostImports := #["./leanrx_dom.mjs", "./leanrx_region.mjs", "./leanrx_host.mjs"]
    features := #["dynamic-regions", "conditional", "positional", "keyed",
      "delegated-events", "typed-form-properties", "reference-propagation",
      "instrumentation", "trace"] }

def emit (moduleName : String) (checked : LeanRx.Todo.Spec.Checked) : Except Error Emitted := do
  let runtime ← runtimeNames
  let mountBranch ← branchMountFunction runtime
  let updateBranch ← branchUpdateFunction runtime
  let disposeBranch ← branchDisposeFunction
  let rowRoot ← rowRootFunction
  let mountRow ← rowMountFunction runtime mountBranch.name updateBranch.name disposeBranch.name
  let updateRow ← rowUpdateFunction runtime
  let disposeRow ← rowDisposeFunction
  let mountFilter ← filterMountFunction runtime
  let updateFilter ← filterUpdateFunction runtime
  let disposeFilter ← filterDisposeFunction
  let render ← renderFunction runtime
  let newInputHandler ← newInputFunction
  let add ← addFunction runtime
  let newKey ← newKeyFunction add.name
  let click ← clickFunction runtime
  let change ← changeFunction runtime
  let input ← inputFunction
  let key ← keyFunction click.name
  let filter ← filterFunction
  let clear ← clearFunction
  let reverse ← reverseFunction
  let mount ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let state ← Ident.checked "state"
  let root ← Ident.checked "root"
  let title ← Ident.checked "title"
  let titleText ← Ident.checked "titleText"
  let newInput ← Ident.checked "newInput"
  let addButton ← Ident.checked "addButton"
  let addText ← Ident.checked "addText"
  let list ← Ident.checked "list"
  let filterRoot ← Ident.checked "filterRoot"
  let status ← Ident.checked "status"
  let statusText ← Ident.checked "statusText"
  let clearButton ← Ident.checked "clearButton"
  let clearText ← Ident.checked "clearText"
  let reverseButton ← Ident.checked "reverseButton"
  let reverseText ← Ident.checked "reverseText"
  let metrics ← Ident.checked "metrics"
  let keyed ← Ident.checked "keyedRegion"
  let filters ← Ident.checked "filterRegion"
  let context ← Ident.checked "context"
  let offNewInput ← Ident.checked "offNewInput"
  let offNewKey ← Ident.checked "offNewKey"
  let offAdd ← Ident.checked "offAdd"
  let offListClick ← Ident.checked "offListClick"
  let offListChange ← Ident.checked "offListChange"
  let offListInput ← Ident.checked "offListInput"
  let offListKey ← Ident.checked "offListKey"
  let offFilter ← Ident.checked "offFilter"
  let offClear ← Ident.checked "offClear"
  let offReverse ← Ident.checked "offReverse"
  let disposer ← Ident.checked "disposer"
  let body : Array Stmt := #[
    .const state (.array <| .ofList [
      .array .nil, bigint 0, .literal (.string "all"), bigint (-1),
      .literal (.string ""), .literal (.string "")]),
    .const root (call runtime.createElement [.literal (.string "main")]),
    setAttribute runtime (.ident root) "class" (.literal (.string "leanrx-todo")),
    .const title (call runtime.createElement [.literal (.string "h1")]),
    .const titleText (call runtime.createText [.literal (.string checked.spec.name)]),
    .expr <| call runtime.append [.ident title, .ident titleText],
    .expr <| call runtime.append [.ident root, .ident title],
    .const newInput (call runtime.createElement [.literal (.string "input")]),
    setAttribute runtime (.ident newInput) "type" (.literal (.string "text")),
    setAttribute runtime (.ident newInput) "aria-label" (.literal (.string "New todo")),
    setProperty runtime (.ident newInput) DomProperty.value (.literal (.string "")),
    .expr <| call runtime.append [.ident root, .ident newInput],
    .const addButton (call runtime.createElement [.literal (.string "button")]),
    setAttribute runtime (.ident addButton) "type" (.literal (.string "button")),
    .const addText (call runtime.createText [.literal (.string "Add")]),
    .expr <| call runtime.append [.ident addButton, .ident addText],
    .expr <| call runtime.append [.ident root, .ident addButton],
    .const list (call runtime.createElement [.literal (.string "ul")]),
    setAttribute runtime (.ident list) "aria-label" (.literal (.string "Todo items")),
    .expr <| call runtime.append [.ident root, .ident list],
    .const filterRoot (call runtime.createElement [.literal (.string "div")]),
    setAttribute runtime (.ident filterRoot) "aria-label" (.literal (.string "Todo filters")),
    .expr <| call runtime.append [.ident root, .ident filterRoot],
    .const status (call runtime.createElement [.literal (.string "p")]),
    setAttribute runtime (.ident status) "role" (.literal (.string "status")),
    .const statusText (call runtime.createText [.literal (.string "0 items left")]),
    .expr <| call runtime.append [.ident status, .ident statusText],
    .expr <| call runtime.append [.ident root, .ident status],
    .const clearButton (call runtime.createElement [.literal (.string "button")]),
    setAttribute runtime (.ident clearButton) "type" (.literal (.string "button")),
    .const clearText (call runtime.createText [.literal (.string "Clear completed")]),
    .expr <| call runtime.append [.ident clearButton, .ident clearText],
    .expr <| call runtime.append [.ident root, .ident clearButton],
    .const reverseButton (call runtime.createElement [.literal (.string "button")]),
    setAttribute runtime (.ident reverseButton) "type" (.literal (.string "button")),
    .const reverseText (call runtime.createText [.literal (.string "Reverse order")]),
    .expr <| call runtime.append [.ident reverseButton, .ident reverseText],
    .expr <| call runtime.append [.ident root, .ident reverseButton],
    .const metrics (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil]),
    .const keyed (call runtime.createKeyedRegion [
      .ident list, .ident mountRow.name, .ident updateRow.name, .ident disposeRow.name,
      .ident rowRoot.name]),
    .const filters (call runtime.createPositionalRegion [
      .ident filterRoot, .ident mountFilter.name, .ident updateFilter.name,
      .ident disposeFilter.name]),
    .const context (.array <| .ofList [
      .ident keyed, .ident filters, .ident statusText, .ident newInput, .ident metrics]),
    .expr <| call runtime.append [.ident target, .ident root],
    .expr <| call render.name [.ident state, .ident context],
    .assign (.index (.ident metrics) (uint 0)) (uint 0),
    .assign (.index (.ident metrics) (uint 1)) (uint 0),
    .assign (.index (.ident metrics) (uint 2)) (uint 0),
    .assign (.index (.ident metrics) (uint 3)) (uint 0),
    .assign (.index (.ident metrics) (uint 4)) (uint 0),
    .assign (.index (.ident metrics) (uint 5)) (uint 0),
    .assign (.index (.ident metrics) (uint 6)) (uint 0),
    .assign (.index (.ident metrics) (uint 7)) (.array .nil),
    .const offNewInput (call runtime.listenValue [
      .ident newInput, .literal (.string "input"), .ident state, .ident context,
      .ident newInputHandler.name]),
    .const offNewKey (call runtime.listenKey [
      .ident newInput, .literal (.string "keydown"), .ident state, .ident context,
      .ident newKey.name]),
    .const offAdd (call runtime.listen [
      .ident addButton, .literal (.string "click"), .ident state, .ident context, .ident add.name]),
    .const offListClick (call runtime.listenDelegated [
      .ident list, .literal (.string "click"), .ident state, .ident context, .ident click.name]),
    .const offListChange (call runtime.listenDelegated [
      .ident list, .literal (.string "change"), .ident state, .ident context, .ident change.name]),
    .const offListInput (call runtime.listenDelegated [
      .ident list, .literal (.string "input"), .ident state, .ident context, .ident input.name]),
    .const offListKey (call runtime.listenDelegated [
      .ident list, .literal (.string "keydown"), .ident state, .ident context, .ident key.name]),
    .const offFilter (call runtime.listenDelegated [
      .ident filterRoot, .literal (.string "click"), .ident state, .ident context,
      .ident filter.name]),
    .const offClear (call runtime.listen [
      .ident clearButton, .literal (.string "click"), .ident state, .ident context,
      .ident clear.name]),
    .const offReverse (call runtime.listen [
      .ident reverseButton, .literal (.string "click"), .ident state, .ident context,
      .ident reverse.name]),
    .const disposer (call runtime.makeDisposer [
      .ident root,
      .array <| .ofList <| [offNewInput, offNewKey, offAdd, offListClick,
        offListChange, offListInput, offListKey, offFilter, offClear, offReverse].map Expr.ident ++
        [property (.ident keyed) "dispose", property (.ident filters) "dispose"],
      .ident metrics,
      .array <| .ofList [.ident keyed, .ident filters]]),
    .return (.ident disposer)
  ]
  let declarations : Array Decl := #[
    .function mountBranch, .function updateBranch, .function disposeBranch,
    .function rowRoot, .function mountRow, .function updateRow, .function disposeRow,
    .function mountFilter, .function updateFilter, .function disposeFilter,
    .function render, .function newInputHandler, .function add, .function newKey,
    .function click, .function change, .function input, .function key, .function filter,
    .function clear, .function reverse,
    .function { name := mount, params := #[target], body }
  ]
  let module : Module :=
    { globals := #[runtime.string, runtime.bigInt]
      imports := #[
        { source := "./leanrx_dom.mjs", names := #[
            (runtime.createElement, runtime.createElement),
            (runtime.createText, runtime.createText),
            (runtime.setAttribute, runtime.setAttribute),
            (runtime.append, runtime.append),
            (runtime.childAt, runtime.childAt),
            (runtime.setText, runtime.setText),
            (runtime.setProperty, runtime.setProperty),
            (runtime.listen, runtime.listen),
            (runtime.listenValue, runtime.listenValue),
            (runtime.listenKey, runtime.listenKey),
            (runtime.listenDelegated, runtime.listenDelegated)
          ] },
        { source := "./leanrx_region.mjs", names := #[
            (runtime.createConditionalRegion, runtime.createConditionalRegion),
            (runtime.createPositionalRegion, runtime.createPositionalRegion),
            (runtime.createKeyedRegion, runtime.createKeyedRegion)
          ] },
        { source := "./leanrx_host.mjs", names := #[
            (runtime.makeDisposer, runtime.makeDisposer)
          ] }
      ]
      declarations
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Todo
