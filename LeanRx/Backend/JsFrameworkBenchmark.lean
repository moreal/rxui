import LeanRx.Backend.Manifest
import LeanRx.JsFrameworkBenchmark.Model

namespace LeanRx.Backend.JsFrameworkBenchmark

open LeanRx.Js

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
  setText : Ident
  firstChild : Ident
  nextSibling : Ident
  cloneTemplate : Ident
  setKey : Ident
  listenDelegated : Ident
  createKeyedRegion : Ident
  makeDisposer : Ident
  array : Ident
  bigInt : Ident
  document : Ident
  math : Ident
  string : Ident

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))
private def bigint (value : Nat) : Expr := .literal (.bigint (Int.ofNat value))
private def bool (value : Bool) : Expr := .literal (.boolean value)
private def null : Expr := .literal .null
private def negativeOne : Expr := .unary .neg (uint 1)

private def indexAt (target : Expr) (index : Nat) : Expr := .index target (uint index)
private def arrayAt (name : Ident) (index : Nat) : Expr := indexAt (.ident name) index
private def property (target : Expr) (name : String) : Expr :=
  .index target (.literal (.string name))
private def call (name : Ident) (args : List Expr) : Expr := .call (.ident name) (.ofList args)
private def callExpr (callee : Expr) (args : List Expr) : Expr := .call callee (.ofList args)
private def method (target : Expr) (name : String) (args : List Expr) : Expr :=
  callExpr (property target name) args
private def equals (left right : Expr) : Expr := .binary .eq left right
private def notEquals (left right : Expr) : Expr := .unary .not (equals left right)

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def addAt (array : Ident) (index : Nat) (amount : Expr) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) amount)

private def stringArray (values : List String) : Expr :=
  .array <| .ofList (values.map fun value => .literal (.string value))

private def runtimeNames : Except Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    append := ← Ident.checked "append"
    setText := ← Ident.checked "setText"
    firstChild := ← Ident.checked "firstChild"
    nextSibling := ← Ident.checked "nextSibling"
    cloneTemplate := ← Ident.checked "cloneTemplate"
    setKey := ← Ident.checked "setKey"
    listenDelegated := ← Ident.checked "listenDelegated"
    createKeyedRegion := ← Ident.checked "createKeyedRegion"
    makeDisposer := ← Ident.checked "makeDisposer"
    array := ← Ident.checked "Array"
    bigInt := ← Ident.checked "BigInt"
    document := ← Ident.checked "document"
    math := ← Ident.checked "Math"
    string := ← Ident.checked "String"
  }

private def setAttribute (runtime : RuntimeNames) (node : Expr) (name : String)
    (value : Expr) : Stmt :=
  .expr <| call runtime.setAttribute [node, .literal (.string name), value]

private def randomFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkRandom"
  let max ← Ident.checked "max"
  let random := method (.ident runtime.math) "random" []
  let rounded := method (.ident runtime.math) "round" [
    .binary .mul random (uint 1000)]
  pure {
    name
    params := #[max]
    body := #[.return <| .binary .rem rounded (.ident max)]
  }

private def buildDataFunction (runtime : RuntimeNames) (random : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkBuildData"
  let state ← Ident.checked "state"
  let count ← Ident.checked "count"
  let adjectives ← Ident.checked "adjectives"
  let colours ← Ident.checked "colours"
  let nouns ← Ident.checked "nouns"
  let rows ← Ident.checked "rows"
  let index ← Ident.checked "index"
  let id ← Ident.checked "id"
  let label ← Ident.checked "label"
  let pick (array : Ident) : Expr :=
    .index (.ident array) (call random [property (.ident array) "length"])
  let labelValue := .binary .add
    (.binary .add
      (.binary .add
        (.binary .add (pick adjectives) (.literal (.string " ")))
        (pick colours))
      (.literal (.string " ")))
    (pick nouns)
  pure {
    name
    params := #[state, count]
    body := #[
      .const adjectives <| stringArray [
        "pretty", "large", "big", "small", "tall", "short", "long", "handsome",
        "plain", "quaint", "clean", "elegant", "easy", "angry", "crazy", "helpful",
        "mushy", "odd", "unsightly", "adorable", "important", "inexpensive", "cheap",
        "expensive", "fancy"],
      .const colours <| stringArray [
        "red", "yellow", "blue", "green", "pink", "brown", "purple", "brown", "white",
        "black", "orange"],
      .const nouns <| stringArray [
        "table", "chair", "house", "bbq", "desk", "car", "pony", "cookie", "sandwich",
        "burger", "pizza", "mouse", "keyboard"],
      .const rows (.array .nil),
      .forOf index (method (call runtime.array [.ident count]) "keys" []) <| .ofList [
        .const id (arrayAt state 1),
        .assign (.index (.ident state) (uint 1))
          (.binary .add (arrayAt state 1) (bigint 1)),
        .const label labelValue,
        .expr <| method (.ident rows) "push" [
          .array <| .ofList [.ident id, .ident label]]
      ],
      .return (.ident rows)
    ]
  }

private def findIndexFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkFindIndex"
  let rows ← Ident.checked "rows"
  let key ← Ident.checked "key"
  let found ← Ident.checked "found"
  let index ← Ident.checked "index"
  pure {
    name
    params := #[rows, key]
    body := #[
      .const found (.array <| .ofList [negativeOne]),
      .forOf index (method (.ident rows) "keys" []) <| .ofList [
        .ifThen (equals (.index (.index (.ident rows) (.ident index)) (uint 0)) (.ident key)) <|
          .ofList [.assign (.index (.ident found) (uint 0)) (.ident index)]
      ],
      .return (arrayAt found 0)
    ]
  }

private def rowTemplateFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkRowTemplate"
  let root ← Ident.checked "rowRoot"
  let idCell ← Ident.checked "idCell"
  let labelCell ← Ident.checked "labelCell"
  let selectLink ← Ident.checked "selectLink"
  let removeCell ← Ident.checked "removeCell"
  let removeLink ← Ident.checked "removeLink"
  let removeIcon ← Ident.checked "removeIcon"
  let fillerCell ← Ident.checked "fillerCell"
  let emptyText := call runtime.createText [.literal (.string "")]
  pure {
    name
    params := #[]
    body := #[
      .const root (call runtime.createElement [.literal (.string "tr")]),
      .const idCell (call runtime.createElement [.literal (.string "td")]),
      setAttribute runtime (.ident idCell) "class" (.literal (.string "col-md-1")),
      .expr <| call runtime.append [.ident idCell, emptyText],
      .expr <| call runtime.append [.ident root, .ident idCell],
      .const labelCell (call runtime.createElement [.literal (.string "td")]),
      setAttribute runtime (.ident labelCell) "class" (.literal (.string "col-md-4")),
      .const selectLink (call runtime.createElement [.literal (.string "a")]),
      setAttribute runtime (.ident selectLink) "data-lrx-action" (.literal (.string "select")),
      .expr <| call runtime.append [.ident selectLink, emptyText],
      .expr <| call runtime.append [.ident labelCell, .ident selectLink],
      .expr <| call runtime.append [.ident root, .ident labelCell],
      .const removeCell (call runtime.createElement [.literal (.string "td")]),
      setAttribute runtime (.ident removeCell) "class" (.literal (.string "col-md-1")),
      .const removeLink (call runtime.createElement [.literal (.string "a")]),
      setAttribute runtime (.ident removeLink) "data-lrx-action" (.literal (.string "remove")),
      .const removeIcon (call runtime.createElement [.literal (.string "span")]),
      setAttribute runtime (.ident removeIcon) "class"
        (.literal (.string "glyphicon glyphicon-remove")),
      setAttribute runtime (.ident removeIcon) "aria-hidden" (.literal (.string "true")),
      .expr <| call runtime.append [.ident removeLink, .ident removeIcon],
      .expr <| call runtime.append [.ident removeCell, .ident removeLink],
      .expr <| call runtime.append [.ident root, .ident removeCell],
      .const fillerCell (call runtime.createElement [.literal (.string "td")]),
      setAttribute runtime (.ident fillerCell) "class" (.literal (.string "col-md-6")),
      .expr <| call runtime.append [.ident root, .ident fillerCell],
      .return (.ident root)
    ]
  }

/-- The selection flag of a row item: the mount-local context carries the model
state in slot 3, whose slot 2 is the selected id (`null` for none). -/
private def selectedFlag (context item : Ident) : Expr :=
  equals (indexAt (arrayAt context 3) 2) (arrayAt item 0)

/-- Mounts one row by cloning the static template that `mount` built once
(carried in the mount-local context that the keyed region forwards with every
update) and writing only the per-row key, texts, and selection class. The row
item is the model row itself; the selection flag is derived from the context.
The row root carries the delegated key, so both action links resolve it through
their nearest keyed ancestor. -/
private def mountRowFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkMountRow"
  let item ← Ident.checked "item"
  let _index ← Ident.checked "index"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let keyText ← Ident.checked "keyText"
  let root ← Ident.checked "rowRoot"
  let idCell ← Ident.checked "idCell"
  let selectLink ← Ident.checked "selectLink"
  let labelText ← Ident.checked "labelText"
  let selected ← Ident.checked "selected"
  pure {
    name
    params := #[item, _index, context]
    body := #[
      .const metrics (arrayAt context 1),
      .const keyText (call runtime.string [arrayAt item 0]),
      .const root (call runtime.cloneTemplate [arrayAt context 2]),
      .expr <| call runtime.setKey [.ident root, .ident keyText],
      .const idCell (call runtime.firstChild [.ident root]),
      .expr <| call runtime.setText [call runtime.firstChild [.ident idCell], .ident keyText],
      .const selectLink (call runtime.firstChild [call runtime.nextSibling [.ident idCell]]),
      .const labelText (call runtime.firstChild [.ident selectLink]),
      .expr <| call runtime.setText [.ident labelText, arrayAt item 1],
      .const selected (selectedFlag context item),
      .ifThen (.ident selected) <| .ofList [
        setAttribute runtime (.ident root) "class" (.literal (.string "danger")),
        incrementAt metrics 6
      ],
      addAt metrics 6 (uint 3),
      .return <| .array <| .ofList [
        .ident root, .ident labelText, arrayAt item 1, .ident selected]
    ]
  }

private def updateRowFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkUpdateRow"
  let handle ← Ident.checked "handle"
  let item ← Ident.checked "item"
  let _index ← Ident.checked "index"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let selected ← Ident.checked "selected"
  let selectedClass := .conditional (.ident selected)
    (.literal (.string "danger")) (.literal (.string ""))
  pure {
    name
    params := #[handle, item, _index, context]
    body := #[
      .const metrics (arrayAt context 1),
      .const selected (selectedFlag context item),
      incrementAt metrics 5,
      .ifThen (notEquals (arrayAt handle 2) (arrayAt item 1)) <| .ofList [
        .expr <| call runtime.setText [arrayAt handle 1, arrayAt item 1],
        .assign (.index (.ident handle) (uint 2)) (arrayAt item 1),
        incrementAt metrics 6
      ],
      .ifThen (notEquals (arrayAt handle 3) (.ident selected)) <| .ofList [
        setAttribute runtime (arrayAt handle 0) "class" selectedClass,
        .assign (.index (.ident handle) (uint 3)) (.ident selected),
        incrementAt metrics 6
      ],
      .return null
    ]
  }

private def disposeRowFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkDisposeRow"
  let handle ← Ident.checked "handle"
  let key ← Ident.checked "key"
  pure { name, params := #[handle, key], body := #[.return null] }

private def rowRootFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkRowRoot"
  let handle ← Ident.checked "handle"
  pure { name, params := #[handle], body := #[.return (arrayAt handle 0)] }

private def commitMetrics (metrics action : Ident) : List Stmt := [
  incrementAt metrics 1,
  incrementAt metrics 3,
  incrementAt metrics 4,
  .expr <| method (arrayAt metrics 7) "push" [.ident action]
]

/-- Commits the whole row list: the model rows are the keyed items and the
region forwards the mount-local context (metrics, template, state) to every
row callback, so no per-commit projection array is built. -/
private def commitFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkCommit"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[state, context, action]
    body := #[.const metrics (arrayAt context 1)] ++ (commitMetrics metrics action).toArray ++ #[
      .expr <| method (arrayAt context 0) "update" [arrayAt state 0, .ident context],
      .return null
    ]
  }

/-- Commits a change that affects the render payload of at most two retained
rows (the previously and newly selected rows): the region re-runs the update
callback for exactly those positions, which is equivalent to a full commit
because every other row's label and selection flag are unchanged. A negative
first position means no previously selected row; an equal second position is
updated once. -/
private def commitRowsFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkCommitRows"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let first ← Ident.checked "first"
  let second ← Ident.checked "second"
  let action ← Ident.checked "action"
  let metrics ← Ident.checked "metrics"
  let rows ← Ident.checked "rows"
  let updateAt (position : Ident) : Stmt :=
    .expr <| method (arrayAt context 0) "updateAt" [
      .ident position, .index (.ident rows) (.ident position), .ident context]
  pure {
    name
    params := #[state, context, first, second, action]
    body := #[.const metrics (arrayAt context 1)] ++ (commitMetrics metrics action).toArray ++ #[
      .const rows (arrayAt state 0),
      .ifThen (notEquals (.ident first) negativeOne) <| .ofList [updateAt first],
      .ifThen (notEquals (.ident second) (.ident first)) <| .ofList [updateAt second],
      .return null
    ]
  }

private def replaceFunction (buildData commit : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkReplace"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let count ← Ident.checked "count"
  let action ← Ident.checked "action"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[state, context, count, action]
    body := #[
      .const metrics (arrayAt context 1),
      .assign (.index (.ident state) (uint 0))
        (call buildData [.ident state, .ident count]),
      .assign (.index (.ident state) (uint 2)) null,
      addAt metrics 0 (uint 2),
      .expr <| call commit [.ident state, .ident context, .ident action],
      .return null
    ]
  }

private def addFunction (rowCount : Nat) (buildData commit : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkAdd"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let appended ← Ident.checked "appended"
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 1),
      .const appended (call buildData [.ident state, uint rowCount]),
      .assign (.index (.ident state) (uint 0))
        (method (arrayAt state 0) "concat" [.ident appended]),
      addAt metrics 0 (uint 2),
      .expr <| call commit [
        .ident state, .ident context, .literal (.string "add")],
      .return null
    ]
  }

private def updateFunction (runtime : RuntimeNames) (stride : Nat) (commit : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkUpdate"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let rows ← Ident.checked "rows"
  let index ← Ident.checked "index"
  let changedRow ← Ident.checked "changedRow"
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 1),
      .const rows (arrayAt state 0),
      .forOf index (method (call runtime.array [property (.ident rows) "length"])
          "keys" []) <| .ofList [
        .ifThen (equals (.binary .rem (.ident index) (uint stride)) (uint 0)) <| .ofList [
          .const changedRow (.index (.ident rows) (.ident index)),
          .assign (.index (.ident changedRow) (uint 1))
            (.binary .add (arrayAt changedRow 1) (.literal (.string " !!!")))
        ]
      ],
      incrementAt metrics 0,
      .expr <| call commit [
        .ident state, .ident context, .literal (.string "update")],
      .return null
    ]
  }

private def clearFunction (commit : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkClear"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 1),
      .assign (.index (.ident state) (uint 0)) (.array .nil),
      .assign (.index (.ident state) (uint 2)) null,
      addAt metrics 0 (uint 2),
      .expr <| call commit [
        .ident state, .ident context, .literal (.string "clear")],
      .return null
    ]
  }

private def swapFunction (firstIndex secondIndex : Nat) (commit : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkSwap"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let rows ← Ident.checked "rows"
  let metrics ← Ident.checked "metrics"
  let firstRow ← Ident.checked "firstRow"
  let secondRow ← Ident.checked "secondRow"
  pure {
    name
    params := #[state, context]
    body := #[
      .const rows (arrayAt state 0),
      .const metrics (arrayAt context 1),
      .ifThen (.binary .lt (uint secondIndex) (property (.ident rows) "length")) <| .ofList [
        .const firstRow (.index (.ident rows) (uint firstIndex)),
        .const secondRow (.index (.ident rows) (uint secondIndex)),
        .assign (.index (.ident rows) (uint firstIndex)) (.ident secondRow),
        .assign (.index (.ident rows) (uint secondIndex)) (.ident firstRow),
        addAt metrics 0 (uint 2),
        .expr <| call commit [
          .ident state, .ident context, .literal (.string "swaprows")],
        .return null
      ],
      .return null
    ]
  }

/-- Selecting a row changes only the selected id, and a row's selection flag
depends on it only through equality with the row's own id, so exactly the
previously selected row (if any) and the newly selected row change; the commit
goes through `commitRows` instead of re-running every row. -/
private def selectFunction (runtime : RuntimeNames) (findIndex commitRows : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkSelect"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let key ← Ident.checked "key"
  let metrics ← Ident.checked "metrics"
  let parsedKey ← Ident.checked "parsedKey"
  let foundIndex ← Ident.checked "foundIndex"
  let previousIndex ← Ident.checked "previousIndex"
  pure {
    name
    params := #[state, context, key]
    body := #[
      .const metrics (arrayAt context 1),
      .const parsedKey (call runtime.bigInt [.ident key]),
      .const foundIndex (call findIndex [arrayAt state 0, .ident parsedKey]),
      .ifThen (notEquals (.ident foundIndex) negativeOne) <| .ofList [
        .const previousIndex (call findIndex [arrayAt state 0, arrayAt state 2]),
        .assign (.index (.ident state) (uint 2)) (.ident parsedKey),
        incrementAt metrics 0,
        .expr <| call commitRows [
          .ident state, .ident context, .ident previousIndex, .ident foundIndex,
          .literal (.string "select")],
        .return null
      ],
      .return null
    ]
  }

private def removeFunction (runtime : RuntimeNames) (findIndex commit : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkRemove"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let key ← Ident.checked "key"
  let metrics ← Ident.checked "metrics"
  let parsedKey ← Ident.checked "parsedKey"
  let foundIndex ← Ident.checked "foundIndex"
  pure {
    name
    params := #[state, context, key]
    body := #[
      .const metrics (arrayAt context 1),
      .const parsedKey (call runtime.bigInt [.ident key]),
      .const foundIndex (call findIndex [arrayAt state 0, .ident parsedKey]),
      .ifThen (notEquals (.ident foundIndex) negativeOne) <| .ofList [
        .expr <| method (arrayAt state 0) "splice" [.ident foundIndex, uint 1],
        .ifThen (equals (arrayAt state 2) (.ident parsedKey)) <| .ofList [
          .assign (.index (.ident state) (uint 2)) null
        ],
        incrementAt metrics 0,
        .expr <| call commit [
          .ident state, .ident context, .literal (.string "remove")],
        .return null
      ],
      .return null
    ]
  }

private def dispatchFunction (spec : LeanRx.JsFrameworkBenchmark.Spec) (replace add updateRows
    clearRows swapRows selectRow removeRow : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_benchmarkDispatch"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let key ← Ident.checked "key"
  let branch (slug : String) (callee : Ident) (args : List Expr) : Stmt :=
    .ifThen (equals (.ident action) (.literal (.string slug))) <| .ofList [
      .expr <| call callee args,
      .return null
    ]
  pure {
    name
    params := #[state, context, action, key]
    body := #[
      branch "run" replace [
        .ident state, .ident context, uint spec.rowCount, .literal (.string "run")],
      branch "runlots" replace [
        .ident state, .ident context, uint spec.largeRowCount, .literal (.string "runlots")],
      branch "add" add [.ident state, .ident context],
      branch "update" updateRows [.ident state, .ident context],
      branch "clear" clearRows [.ident state, .ident context],
      branch "swaprows" swapRows [.ident state, .ident context],
      branch "select" selectRow [.ident state, .ident context, .ident key],
      branch "remove" removeRow [.ident state, .ident context, .ident key],
      .return null
    ]
  }

private def mountFunction (runtime : RuntimeNames) (rowTemplate mountRow updateRow disposeRow
    rowRoot dispatch : Ident) : Except Error Function := do
  let name ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let tbody ← Ident.checked "tbody"
  let metrics ← Ident.checked "metrics"
  let rows ← Ident.checked "rows"
  let state ← Ident.checked "state"
  let template ← Ident.checked "template"
  let region ← Ident.checked "region"
  let context ← Ident.checked "context"
  let off ← Ident.checked "off"
  let disposer ← Ident.checked "disposer"
  pure {
    name
    params := #[target]
    body := #[
      .const tbody (method (.ident runtime.document) "getElementById" [
        .literal (.string "tbody")]),
      .const metrics (.array <| .ofList [
        uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil, uint 0, uint 0]),
      .const rows (.array .nil),
      .const state (.array <| .ofList [.ident rows, bigint 1, null]),
      .const template (call rowTemplate []),
      .const region (call runtime.createKeyedRegion [
        .ident tbody, .ident mountRow, .ident updateRow, .ident disposeRow, .ident rowRoot]),
      .const context (.array <| .ofList [
        .ident region, .ident metrics, .ident template, .ident state]),
      .const off (call runtime.listenDelegated [
        .ident target, .literal (.string "click"), .ident state, .ident context, .ident dispatch]),
      .const disposer (call runtime.makeDisposer [
        .ident target,
        .array <| .ofList [.ident off, property (.ident region) "dispose"],
        .ident metrics,
        .array <| .ofList [.ident region]]),
      .return (.ident disposer)
    ]
  }

private def manifest (moduleName : String) (checked : LeanRx.JsFrameworkBenchmark.Spec.Checked) :
    ComponentManifest := {
  compilerVersion := LeanRx.version
  leanToolchain := LeanRx.leanToolchain
  moduleName
  graphHash := s!"js-framework-benchmark:{checked.spec.rowCount}:" ++
    s!"{checked.spec.largeRowCount}:{checked.spec.updateStride}:" ++
    s!"{checked.spec.swapFirst}:{checked.spec.swapSecond}"
  runtimeAbi := LeanRx.runtimeAbi
  exports := #["mount"]
  stateSlots := #[
    .list (.record "BenchmarkRow"), .nat, .record "OptionNat"
  ]
  sourceCount := 3
  derivedCount := 1
  textSinkCount := 2
  eventCount := 8
  hostImports := #["./leanrx_dom.mjs", "./leanrx_region.mjs"]
  features := #["direct-dom", "template-clone", "keyed-region", "instrumentation",
    "benchmark-contract"]
}

def emit (moduleName : String) (checked : LeanRx.JsFrameworkBenchmark.Spec.Checked) :
    Except Error Emitted := do
  let runtime ← runtimeNames
  let random ← randomFunction runtime
  let buildData ← buildDataFunction runtime random.name
  let findIndex ← findIndexFunction
  let rowTemplate ← rowTemplateFunction runtime
  let mountRow ← mountRowFunction runtime
  let updateRow ← updateRowFunction runtime
  let disposeRow ← disposeRowFunction
  let rowRoot ← rowRootFunction
  let commit ← commitFunction
  let commitRows ← commitRowsFunction
  let replace ← replaceFunction buildData.name commit.name
  let add ← addFunction checked.spec.rowCount buildData.name commit.name
  let updateRows ← updateFunction runtime checked.spec.updateStride commit.name
  let clearRows ← clearFunction commit.name
  let swapRows ← swapFunction checked.spec.swapFirst checked.spec.swapSecond commit.name
  let selectRow ← selectFunction runtime findIndex.name commitRows.name
  let removeRow ← removeFunction runtime findIndex.name commit.name
  let dispatch ← dispatchFunction checked.spec replace.name add.name updateRows.name
    clearRows.name swapRows.name selectRow.name removeRow.name
  let mount ← mountFunction runtime rowTemplate.name mountRow.name updateRow.name
    disposeRow.name rowRoot.name dispatch.name
  let declarations : Array Decl := #[
    .function random, .function buildData, .function findIndex,
    .function rowTemplate, .function mountRow, .function updateRow, .function disposeRow, .function rowRoot,
    .function commit, .function commitRows, .function replace, .function add, .function updateRows,
    .function clearRows, .function swapRows, .function selectRow, .function removeRow,
    .function dispatch, .function mount
  ]
  let module : Module := {
    globals := #[runtime.array, runtime.bigInt, runtime.document, runtime.math, runtime.string]
    imports := #[
      { source := "./leanrx_dom.mjs", names := #[
          (runtime.createElement, runtime.createElement),
          (runtime.createText, runtime.createText),
          (runtime.setAttribute, runtime.setAttribute),
          (runtime.append, runtime.append),
          (runtime.setText, runtime.setText),
          (runtime.firstChild, runtime.firstChild),
          (runtime.nextSibling, runtime.nextSibling),
          (runtime.cloneTemplate, runtime.cloneTemplate),
          (runtime.setKey, runtime.setKey),
          (runtime.listenDelegated, runtime.listenDelegated),
          (runtime.makeDisposer, runtime.makeDisposer)
        ] },
      { source := "./leanrx_region.mjs", names := #[
          (runtime.createKeyedRegion, runtime.createKeyedRegion)
        ] }
    ]
    declarations
    exports := #[{ localName := mount.name, exportName := mount.name }]
  }
  module.validate
  pure ⟨module, manifest moduleName checked⟩

end LeanRx.Backend.JsFrameworkBenchmark
