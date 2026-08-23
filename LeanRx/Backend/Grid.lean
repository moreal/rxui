import LeanRx.Backend.Manifest
import LeanRx.Grid.Component

namespace LeanRx.Backend.Grid

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
  setProperty : Ident
  append : Ident
  setText : Ident
  listenDelegated : Ident
  createKeyedRegion : Ident
  createDeltaKeyedRegion : Ident
  makeDisposer : Ident
  array : Ident
  bigInt : Ident
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

private def runtimeNames : Except Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    setProperty := ← Ident.checked "setProperty"
    append := ← Ident.checked "append"
    setText := ← Ident.checked "setText"
    listenDelegated := ← Ident.checked "listenDelegated"
    createKeyedRegion := ← Ident.checked "createKeyedRegion"
    createDeltaKeyedRegion := ← Ident.checked "createDeltaKeyedRegion"
    makeDisposer := ← Ident.checked "makeDisposer"
    array := ← Ident.checked "Array"
    bigInt := ← Ident.checked "BigInt"
    string := ← Ident.checked "String"
  }

private inductive GridAction where
  | createRows
  | updateOne
  | removeRows
  | swapRows
  | filterRows
  | sortRows
  | selectRow

private def GridAction.slug : GridAction → String
  | .createRows => "create"
  | .updateOne => "update"
  | .removeRows => "remove"
  | .swapRows => "swap"
  | .filterRows => "filter"
  | .sortRows => "sort"
  | .selectRow => "select"

private def GridAction.label (spec : LeanRx.Grid.Spec) : GridAction → String
  | .createRows => s!"Create {spec.rowCount} rows"
  | .updateOne => "Update one row"
  | .removeRows => s!"Remove rows divisible by {spec.removeDivisor}"
  | .swapRows => s!"Swap rows {spec.swapFirst} and {spec.swapSecond}"
  | .filterRows => "Toggle odd rows"
  | .sortRows => "Toggle sort order"
  | .selectRow => s!"Select row {spec.selectId}"

private def setAttribute (runtime : RuntimeNames) (node : Expr) (name : String)
    (value : Expr) : Stmt :=
  .expr <| call runtime.setAttribute [node, .literal (.string name), value]

private def setProperty (runtime : RuntimeNames) (node : Expr) (name : String)
    (value : Expr) : Stmt :=
  .expr <| call runtime.setProperty [node, .literal (.string name), value]

private def createRowsFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridCreateRows"
  let count ← Ident.checked "count"
  let rows ← Ident.checked "rows"
  let index ← Ident.checked "index"
  let id ← Ident.checked "id"
  let label ← Ident.checked "label"
  pure {
    name
    params := #[count]
    body := #[
      .const rows (.array .nil),
      .forOf index (method (call runtime.array [.ident count]) "keys" []) <| .ofList [
        .const id (call runtime.bigInt [.ident index]),
        .const label (.binary .add (.literal (.string "Row ")) (call runtime.string [.ident index])),
        .expr <| method (.ident rows) "push" [.array <| .ofList [
          .ident id, .ident label, .binary .mul (.ident id) (bigint 10), bool false
        ]]
      ],
      .return (.ident rows)
    ]
  }

private def keepRowFunction (divisor : Nat) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridKeepRow"
  let row ← Ident.checked "row"
  pure {
    name
    params := #[row]
    body := #[.return <| notEquals (.binary .rem (arrayAt row 0) (bigint divisor)) (bigint 0)]
  }

private def rowTextFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridRowText"
  let row ← Ident.checked "row"
  pure {
    name
    params := #[row]
    body := #[.return <| .binary .add
      (.binary .add (arrayAt row 1) (.literal (.string " value ")))
      (call runtime.string [arrayAt row 2])]
  }

private def projectRowFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_gridProjectRow"
  let row ← Ident.checked "row"
  let selected ← Ident.checked "selected"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[row, selected, metrics]
    body := #[.return <| .array <| .ofList [
      arrayAt row 0, arrayAt row 1, arrayAt row 2,
      .binary .and (notEquals (.ident selected) null) (equals (.ident selected) (arrayAt row 0)),
      .ident metrics
    ]]
  }

private def compareRowsFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_gridCompareRows"
  let left ← Ident.checked "left"
  let right ← Ident.checked "right"
  pure {
    name
    params := #[left, right]
    body := #[.return <| .conditional (equals (arrayAt left 0) (arrayAt right 0)) (uint 0)
      (.conditional (.binary .lt (arrayAt left 0) (arrayAt right 0)) (uint 1) negativeOne)]
  }

private def visibleFunction (projectRow compareRows : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridVisible"
  let rows ← Ident.checked "rows"
  let oddOnly ← Ident.checked "oddOnly"
  let descending ← Ident.checked "descending"
  let selected ← Ident.checked "selected"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let visible ← Ident.checked "visible"
  let row ← Ident.checked "row"
  let includeRow := .binary .or (.unary .not <| .ident oddOnly)
    (equals (.binary .rem (arrayAt row 0) (bigint 2)) (bigint 1))
  pure {
    name
    params := #[rows, oddOnly, descending, selected, metrics, work]
    body := #[
      .const visible (.array .nil),
      .forOf row (.ident rows) <| .ofList [
        incrementAt work 0,
        .ifThen includeRow <| .ofList [
          .expr <| method (.ident visible) "push" [
            call projectRow [.ident row, .ident selected, .ident metrics]]
        ]
      ],
      .ifThen (.ident descending) <| .ofList [
        .expr <| method (.ident visible) "sort" [.ident compareRows]
      ],
      .return (.ident visible)
    ]
  }

private def findIndexFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_gridFindIndex"
  let rows ← Ident.checked "rows"
  let key ← Ident.checked "key"
  let work ← Ident.checked "work"
  let found ← Ident.checked "found"
  let index ← Ident.checked "index"
  pure {
    name
    params := #[rows, key, work]
    body := #[
      .const found (.array <| .ofList [negativeOne]),
      .forOf index (method (.ident rows) "keys" []) <| .ofList [
        incrementAt work 1,
        .ifThen (equals (.index (.index (.ident rows) (.ident index)) (uint 0)) (.ident key)) <|
          .ofList [.assign (.index (.ident found) (uint 0)) (.ident index)]
      ],
      .return (arrayAt found 0)
    ]
  }

private def mountRowFunction (runtime : RuntimeNames) (rowText : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridMountRow"
  let item ← Ident.checked "item"
  let root ← Ident.checked "rowRoot"
  let cell ← Ident.checked "rowCell"
  let text ← Ident.checked "rowTextNode"
  let metrics ← Ident.checked "metrics"
  let selectedValue := .conditional (arrayAt item 3) (.literal (.string "true"))
    (.literal (.string "false"))
  pure {
    name
    params := #[item]
    body := #[
      .const metrics (arrayAt item 4),
      .const root (call runtime.createElement [.literal (.string "div")]),
      setAttribute runtime (.ident root) "role" (.literal (.string "row")),
      setAttribute runtime (.ident root) "data-row-id" (call runtime.string [arrayAt item 0]),
      setAttribute runtime (.ident root) "aria-current" selectedValue,
      .const cell (call runtime.createElement [.literal (.string "div")]),
      setAttribute runtime (.ident cell) "role" (.literal (.string "cell")),
      .const text (call runtime.createText [call rowText [.ident item]]),
      .expr <| call runtime.append [.ident cell, .ident text],
      .expr <| call runtime.append [.ident root, .ident cell],
      addAt metrics 6 (uint 4),
      .return <| .array <| .ofList [.ident root, .ident text, arrayAt item 2, arrayAt item 3]
    ]
  }

private def updateRowFunction (runtime : RuntimeNames) (rowText : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridUpdateRow"
  let handle ← Ident.checked "handle"
  let item ← Ident.checked "item"
  let _index ← Ident.checked "index"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[handle, item, _index]
    body := #[
      .const metrics (arrayAt item 4),
      incrementAt metrics 5,
      .ifThen (notEquals (arrayAt handle 2) (arrayAt item 2)) <| .ofList [
        .expr <| call runtime.setText [arrayAt handle 1, call rowText [.ident item]],
        .assign (.index (.ident handle) (uint 2)) (arrayAt item 2),
        incrementAt metrics 6
      ],
      .ifThen (notEquals (arrayAt handle 3) (arrayAt item 3)) <| .ofList [
        setAttribute runtime (arrayAt handle 0) "aria-current"
          (.conditional (arrayAt item 3) (.literal (.string "true")) (.literal (.string "false"))),
        .assign (.index (.ident handle) (uint 3)) (arrayAt item 3),
        incrementAt metrics 6
      ],
      .return null
    ]
  }

private def disposeRowFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_gridDisposeRow"
  let handle ← Ident.checked "handle"
  let key ← Ident.checked "key"
  pure { name, params := #[handle, key], body := #[.return null] }

private def rowRootFunction : Except Error Function := do
  let name ← Ident.checked "$lrx_gridRowRoot"
  let handle ← Ident.checked "handle"
  pure { name, params := #[handle], body := #[.return (arrayAt handle 0)] }

private def finishFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridFinish"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let metrics ← Ident.checked "metrics"
  let statusText ← Ident.checked "statusText"
  let nextStatus ← Ident.checked "nextStatus"
  let visibleText := call runtime.string [property (arrayAt state 4) "length"]
  let sourceText := call runtime.string [property (arrayAt state 0) "length"]
  let statusExpr := .binary .add
    (.binary .add (.binary .add visibleText (.literal (.string " visible / "))) sourceText)
    (.literal (.string " source"))
  pure {
    name
    params := #[state, context, action]
    body := #[
      .const metrics (arrayAt context 2),
      .const statusText (arrayAt context 1),
      incrementAt metrics 1,
      incrementAt metrics 3,
      incrementAt metrics 4,
      .expr <| method (arrayAt metrics 7) "push" [.ident action],
      .const nextStatus statusExpr,
      incrementAt metrics 5,
      .ifThen (notEquals (arrayAt state 6) (.ident nextStatus)) <| .ofList [
        .expr <| call runtime.setText [.ident statusText, .ident nextStatus],
        .assign (.index (.ident state) (uint 6)) (.ident nextStatus),
        incrementAt metrics 6
      ],
      .return null
    ]
  }

private def fullCommitFunction (visible finish : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridFullCommit"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let target ← Ident.checked "target"
  let work ← Ident.checked "work"
  pure {
    name
    params := #[state, context, action]
    body := #[
      .const work (arrayAt context 3),
      .const target (call visible [arrayAt state 0, arrayAt state 1, arrayAt state 2,
        arrayAt state 3, arrayAt context 2, .ident work]),
      .assign (.index (.ident state) (uint 4)) (.ident target),
      .expr <| method (arrayAt context 0) "update" [.ident target],
      .expr <| call finish [.ident state, .ident context, .ident action],
      .return null
    ]
  }

private def plannedCommitFunction (costModel : LeanRx.Grid.CostModel) (fullCommit finish : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_gridPlannedCommit"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let deltas ← Ident.checked "deltas"
  let forceFull ← Ident.checked "forceFull"
  let deltaCost ← Ident.checked "deltaCost"
  let fullCost ← Ident.checked "fullCost"
  let strategy := arrayAt state 5
  let applyAndFinish : List Stmt := [
    .expr <| method (arrayAt context 0) "apply" [.ident deltas],
    .expr <| call finish [.ident state, .ident context, .ident action],
    .return null
  ]
  pure {
    name
    params := #[state, context, action, deltas, forceFull]
    body := #[
      .ifThen (equals strategy (bigint 0)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, .ident action],
        .return null
      ],
      .ifThen (equals strategy (bigint 1)) (.ofList applyAndFinish),
      .const deltaCost (.binary .add (uint costModel.deltaFixedCost)
        (.binary .mul (property (.ident deltas) "length") (uint costModel.deltaEditCost))),
      .const fullCost (.binary .mul (property (arrayAt state 4) "length")
        (uint costModel.fullRowCost)),
      .ifThen (.binary .or (.ident forceFull) <| .binary .or
          (.binary .lt (uint costModel.maxDeltaEdits) (property (.ident deltas) "length"))
          (.unary .not <| .binary .lt (.ident deltaCost) (.ident fullCost))) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, .ident action],
        .return null
      ],
      .expr <| method (arrayAt context 0) "apply" [.ident deltas],
      .expr <| call finish [.ident state, .ident context, .ident action],
      .return null
    ]
  }

private def createOperationFunction (runtime : RuntimeNames) (spec : LeanRx.Grid.Spec)
    (createRows visible fullCommit finish : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridCreate"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let updateButton ← Ident.checked "updateButton"
  let swapButton ← Ident.checked "swapButton"
  let selectButton ← Ident.checked "selectButton"
  let target ← Ident.checked "target"
  let deltas ← Ident.checked "deltas"
  let action := .literal (.string GridAction.createRows.slug)
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 2),
      .const work (arrayAt context 3),
      .const updateButton (arrayAt context 4),
      .const swapButton (arrayAt context 5),
      .const selectButton (arrayAt context 6),
      .assign (.index (.ident state) (uint 0)) (call createRows [uint spec.rowCount]),
      .assign (.index (.ident state) (uint 1)) (bool false),
      .assign (.index (.ident state) (uint 2)) (bool false),
      .assign (.index (.ident state) (uint 3)) null,
      .ifThen (notEquals (property (.ident updateButton) "disabled") (bool false)) <| .ofList [
        setProperty runtime (.ident updateButton) "disabled" (bool false),
        incrementAt metrics 6
      ],
      .ifThen (notEquals (property (.ident swapButton) "disabled") (bool false)) <| .ofList [
        setProperty runtime (.ident swapButton) "disabled" (bool false),
        incrementAt metrics 6
      ],
      .ifThen (notEquals (property (.ident selectButton) "disabled") (bool false)) <| .ofList [
        setProperty runtime (.ident selectButton) "disabled" (bool false),
        incrementAt metrics 6
      ],
      addAt metrics 2 (uint 4),
      .ifThen (notEquals (arrayAt state 5) (bigint 1)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, action],
        .return null
      ],
      .const target (call visible [arrayAt state 0, arrayAt state 1, arrayAt state 2,
        arrayAt state 3, .ident metrics, .ident work]),
      .assign (.index (.ident state) (uint 4)) (.ident target),
      .const deltas (.array <| .ofList [.array <| .ofList [
        .literal (.string "reset"), .ident target]]),
      .expr <| method (arrayAt context 0) "apply" [.ident deltas],
      .expr <| call finish [.ident state, .ident context, action],
      .return null
    ]
  }

private def updateOperationFunction (spec : LeanRx.Grid.Spec) (findIndex projectRow fullCommit
    plannedCommit : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridUpdateOne"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let rawIndex ← Ident.checked "rawIndex"
  let row ← Ident.checked "row"
  let next ← Ident.checked "nextRow"
  let visibleIndex ← Ident.checked "visibleIndex"
  let projected ← Ident.checked "projected"
  let deltas ← Ident.checked "deltas"
  let action := .literal (.string GridAction.updateOne.slug)
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 2),
      .const work (arrayAt context 3),
      .const rawIndex (call findIndex [arrayAt state 0, bigint spec.updateId, .ident work]),
      .ifThen (.binary .lt (.ident rawIndex) (uint 0)) <| .ofList [.return null],
      .const row (.index (arrayAt state 0) (.ident rawIndex)),
      .const next (.array <| .ofList [arrayAt row 0, arrayAt row 1,
        .binary .add (arrayAt row 2) (bigint 1), bool false]),
      .assign (.index (arrayAt state 0) (.ident rawIndex)) (.ident next),
      incrementAt metrics 2,
      .ifThen (equals (arrayAt state 5) (bigint 0)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, action],
        .return null
      ],
      .const deltas (.array .nil),
      .const visibleIndex (call findIndex [arrayAt state 4, bigint spec.updateId, .ident work]),
      .ifThen (.binary .le (uint 0) (.ident visibleIndex)) <| .ofList [
        .const projected (call projectRow [.ident next, arrayAt state 3, .ident metrics]),
        .assign (.index (arrayAt state 4) (.ident visibleIndex)) (.ident projected),
        .expr <| method (.ident deltas) "push" [.array <| .ofList [
          .literal (.string "update"), .ident visibleIndex, .ident projected]]
      ],
      .expr <| call plannedCommit [.ident state, .ident context, action, .ident deltas, bool false],
      .return null
    ]
  }

private def removeOperationFunction (runtime : RuntimeNames) (spec : LeanRx.Grid.Spec)
    (keepRow fullCommit plannedCommit : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_gridRemove"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let updateButton ← Ident.checked "updateButton"
  let deltas ← Ident.checked "deltas"
  let nextVisible ← Ident.checked "nextVisible"
  let item ← Ident.checked "item"
  let currentIndex ← Ident.checked "currentIndex"
  let nextRows ← Ident.checked "nextRows"
  let action := .literal (.string GridAction.removeRows.slug)
  let removed := equals (.binary .rem (arrayAt item 0) (bigint spec.removeDivisor)) (bigint 0)
  let selectedRemoved := .binary .and (notEquals (arrayAt state 3) null)
    (equals (.binary .rem (arrayAt state 3) (bigint spec.removeDivisor)) (bigint 0))
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 2),
      .const work (arrayAt context 3),
      .const updateButton (arrayAt context 4),
      .const nextRows (method (arrayAt state 0) "filter" [.ident keepRow]),
      .assign (.index (.ident state) (uint 0)) (.ident nextRows),
      .ifThen (notEquals (property (.ident updateButton) "disabled")
          (bool (spec.updateId % spec.removeDivisor == 0))) <| .ofList [
        setProperty runtime (.ident updateButton) "disabled"
          (bool (spec.updateId % spec.removeDivisor == 0)),
        incrementAt metrics 6
      ],
      incrementAt metrics 2,
      .ifThen selectedRemoved <| .ofList [
        .assign (.index (.ident state) (uint 3)) null,
        incrementAt metrics 2
      ],
      .ifThen (equals (arrayAt state 5) (bigint 0)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, action],
        .return null
      ],
      .const deltas (.array .nil),
      .const nextVisible (.array .nil),
      .forOf item (arrayAt state 4) <| .ofList [
        incrementAt work 2,
        .const currentIndex (property (.ident nextVisible) "length"),
        .ifThen removed <| .ofList [
          .expr <| method (.ident deltas) "push" [.array <| .ofList [
            .literal (.string "remove"), .ident currentIndex]]
        ],
        .ifThen (.unary .not removed) <| .ofList [
          .expr <| method (.ident nextVisible) "push" [.ident item]
        ]
      ],
      .assign (.index (.ident state) (uint 4)) (.ident nextVisible),
      .expr <| call plannedCommit [.ident state, .ident context, action, .ident deltas, bool false],
      .return null
    ]
  }

private def swapOperationFunction (spec : LeanRx.Grid.Spec) (findIndex visible fullCommit plannedCommit : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_gridSwap"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let firstIndex ← Ident.checked "firstIndex"
  let secondIndex ← Ident.checked "secondIndex"
  let firstRow ← Ident.checked "firstRow"
  let secondRow ← Ident.checked "secondRow"
  let visibleFirst ← Ident.checked "visibleFirst"
  let visibleSecond ← Ident.checked "visibleSecond"
  let resetTarget ← Ident.checked "resetTarget"
  let resetDeltas ← Ident.checked "resetDeltas"
  let deltas ← Ident.checked "deltas"
  let low ← Ident.checked "low"
  let high ← Ident.checked "high"
  let moved ← Ident.checked "moved"
  let movedBack ← Ident.checked "movedBack"
  let action := .literal (.string GridAction.swapRows.slug)
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 2),
      .const work (arrayAt context 3),
      .const firstIndex (call findIndex [arrayAt state 0, bigint spec.swapFirst, .ident work]),
      .const secondIndex (call findIndex [arrayAt state 0, bigint spec.swapSecond, .ident work]),
      .ifThen (.binary .or (.binary .lt (.ident firstIndex) (uint 0))
          (.binary .lt (.ident secondIndex) (uint 0))) <| .ofList [.return null],
      .const firstRow (.index (arrayAt state 0) (.ident firstIndex)),
      .const secondRow (.index (arrayAt state 0) (.ident secondIndex)),
      .assign (.index (arrayAt state 0) (.ident firstIndex)) (.ident secondRow),
      .assign (.index (arrayAt state 0) (.ident secondIndex)) (.ident firstRow),
      addAt metrics 2 (uint 2),
      .ifThen (equals (arrayAt state 5) (bigint 0)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, action],
        .return null
      ],
      .const visibleFirst (call findIndex [arrayAt state 4, bigint spec.swapFirst, .ident work]),
      .const visibleSecond (call findIndex [arrayAt state 4, bigint spec.swapSecond, .ident work]),
      .ifThen (.unary .not <| .binary .and
          (.binary .le (uint 0) (.ident visibleFirst))
          (.binary .le (uint 0) (.ident visibleSecond))) <| .ofList [
        .const resetTarget (call visible [arrayAt state 0, arrayAt state 1, arrayAt state 2,
          arrayAt state 3, .ident metrics, .ident work]),
        .assign (.index (.ident state) (uint 4)) (.ident resetTarget),
        .const resetDeltas (.array <| .ofList [.array <| .ofList [
          .literal (.string "reset"), .ident resetTarget]]),
        .expr <| call plannedCommit [.ident state, .ident context, action,
          .ident resetDeltas, bool true],
        .return null
      ],
      .const low (.conditional (.binary .lt (.ident visibleFirst) (.ident visibleSecond))
        (.ident visibleFirst) (.ident visibleSecond)),
      .const high (.conditional (.binary .lt (.ident visibleFirst) (.ident visibleSecond))
        (.ident visibleSecond) (.ident visibleFirst)),
      .const moved (indexAt (method (arrayAt state 4) "splice" [.ident high, uint 1]) 0),
      .expr <| method (arrayAt state 4) "splice" [.ident low, uint 0, .ident moved],
      .const movedBack (indexAt (method (arrayAt state 4) "splice" [
        .binary .add (.ident low) (uint 1), uint 1]) 0),
      .expr <| method (arrayAt state 4) "splice" [.ident high, uint 0, .ident movedBack],
      .const deltas (.array <| .ofList [
        .array <| .ofList [.literal (.string "move"), .ident high, .ident low],
        .array <| .ofList [.literal (.string "move"),
          .binary .add (.ident low) (uint 1), .ident high]
      ]),
      .expr <| call plannedCommit [.ident state, .ident context, action,
        .ident deltas, bool false],
      .return null
    ]
  }

private def resetProjectionOperationFunction (functionName : String)
    (actionValue : GridAction) (stateIndex : Nat) (visible fullCommit finish : Ident) :
    Except Error Function := do
  let name ← Ident.checked functionName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let target ← Ident.checked "target"
  let deltas ← Ident.checked "deltas"
  let action := .literal (.string actionValue.slug)
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 2),
      .const work (arrayAt context 3),
      .assign (.index (.ident state) (uint stateIndex)) (.unary .not <| arrayAt state stateIndex),
      incrementAt metrics 2,
      .ifThen (notEquals (arrayAt state 5) (bigint 1)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, action],
        .return null
      ],
      .const target (call visible [arrayAt state 0, arrayAt state 1, arrayAt state 2,
        arrayAt state 3, .ident metrics, .ident work]),
      .assign (.index (.ident state) (uint 4)) (.ident target),
      .const deltas (.array <| .ofList [.array <| .ofList [
        .literal (.string "reset"), .ident target]]),
      .expr <| method (arrayAt context 0) "apply" [.ident deltas],
      .expr <| call finish [.ident state, .ident context, action],
      .return null
    ]
  }

private def selectOperationFunction (spec : LeanRx.Grid.Spec) (findIndex projectRow fullCommit
    plannedCommit : Ident) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridSelect"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let previous ← Ident.checked "previous"
  let rawIndex ← Ident.checked "rawIndex"
  let deltas ← Ident.checked "deltas"
  let previousIndex ← Ident.checked "previousIndex"
  let previousRow ← Ident.checked "previousRow"
  let nextIndex ← Ident.checked "nextIndex"
  let nextRow ← Ident.checked "nextRow"
  let action := .literal (.string GridAction.selectRow.slug)
  let selected := bigint spec.selectId
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 2),
      .const work (arrayAt context 3),
      .const rawIndex (call findIndex [arrayAt state 0, selected, .ident work]),
      .ifThen (.binary .lt (.ident rawIndex) (uint 0)) <| .ofList [.return null],
      incrementAt metrics 2,
      .ifThen (equals (arrayAt state 3) selected) <| .ofList [
        incrementAt metrics 1,
        .expr <| method (arrayAt metrics 7) "push" [action],
        .return null
      ],
      .const previous (arrayAt state 3),
      .assign (.index (.ident state) (uint 3)) selected,
      .ifThen (equals (arrayAt state 5) (bigint 0)) <| .ofList [
        .expr <| call fullCommit [.ident state, .ident context, action],
        .return null
      ],
      .const deltas (.array .nil),
      .ifThen (notEquals (.ident previous) null) <| .ofList [
        .const previousIndex (call findIndex [arrayAt state 4, .ident previous, .ident work]),
        .ifThen (.binary .le (uint 0) (.ident previousIndex)) <| .ofList [
          .const previousRow (call projectRow [
            .index (arrayAt state 4) (.ident previousIndex), null, .ident metrics]),
          .assign (.index (arrayAt state 4) (.ident previousIndex)) (.ident previousRow),
          .expr <| method (.ident deltas) "push" [.array <| .ofList [
            .literal (.string "update"), .ident previousIndex, .ident previousRow]]
        ]
      ],
      .const nextIndex (call findIndex [arrayAt state 4, selected, .ident work]),
      .ifThen (.binary .le (uint 0) (.ident nextIndex)) <| .ofList [
        .const nextRow (call projectRow [
          .index (arrayAt state 4) (.ident nextIndex), selected, .ident metrics]),
        .assign (.index (arrayAt state 4) (.ident nextIndex)) (.ident nextRow),
        .expr <| method (.ident deltas) "push" [.array <| .ofList [
          .literal (.string "update"), .ident nextIndex, .ident nextRow]]
      ],
      .expr <| call plannedCommit [.ident state, .ident context, action,
        .ident deltas, bool false],
      .return null
    ]
  }

private def dispatchFunction (operations : List (GridAction × Ident)) : Except Error Function := do
  let name ← Ident.checked "$lrx_gridDispatch"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let key ← Ident.checked "key"
  let value ← Ident.checked "value"
  let checked ← Ident.checked "checked"
  let eventKey ← Ident.checked "eventKey"
  pure {
    name
    params := #[state, context, action, key, value, checked, eventKey]
    body := (operations.map fun (kind, functionName) =>
      .ifThen (equals (.ident action) (.literal (.string kind.slug))) <| .ofList [
        .expr <| call functionName [.ident state, .ident context]
      ]).toArray ++ #[.return null]
  }

private def buttonBody (runtime : RuntimeNames) (spec : LeanRx.Grid.Spec) (controls metrics : Ident)
    (action : GridAction) (index : Nat) : Except Error (Ident × List Stmt) := do
  let button ← Ident.checked s!"gridButton{index}"
  let text ← Ident.checked s!"gridButtonText{index}"
  pure (button, [
    .const button (call runtime.createElement [.literal (.string "button")]),
    setAttribute runtime (.ident button) "type" (.literal (.string "button")),
    setAttribute runtime (.ident button) "data-lrx-action" (.literal (.string action.slug)),
    setAttribute runtime (.ident button) "data-lrx-key" (.literal (.string "")),
    .const text (call runtime.createText [.literal (.string (action.label spec))]),
    .expr <| call runtime.append [.ident button, .ident text],
    .expr <| call runtime.append [.ident controls, .ident button],
    addAt metrics 6 (uint 3)
  ])

private def mountStrategyFunction (runtime : RuntimeNames) (checked : LeanRx.Grid.Spec.Checked)
    (mountRow updateRow disposeRow rowRoot dispatch : Ident) :
    Except Error Function := do
  let name ← Ident.checked "$lrx_mountGridStrategy"
  let target ← Ident.checked "target"
  let strategy ← Ident.checked "strategy"
  let root ← Ident.checked "root"
  let title ← Ident.checked "title"
  let titleText ← Ident.checked "titleText"
  let controls ← Ident.checked "controls"
  let grid ← Ident.checked "grid"
  let status ← Ident.checked "status"
  let statusText ← Ident.checked "statusText"
  let metrics ← Ident.checked "metrics"
  let work ← Ident.checked "work"
  let rows ← Ident.checked "rows"
  let state ← Ident.checked "state"
  let region ← Ident.checked "region"
  let context ← Ident.checked "context"
  let offControls ← Ident.checked "offControls"
  let disposer ← Ident.checked "disposer"
  let actions : List GridAction := [.createRows, .updateOne, .removeRows, .swapRows,
    .filterRows, .sortRows, .selectRow]
  let buttons ← actions.zipIdx.mapM fun (action, index) =>
    buttonBody runtime checked.spec controls metrics action index
  let buttonStatements := buttons.flatMap (·.2)
  let updateButton ← Ident.checked "gridButton1"
  let swapButton ← Ident.checked "gridButton3"
  let selectButton ← Ident.checked "gridButton6"
  let resetMetrics := (List.range 10).map fun index =>
    .assign (.index (.ident metrics) (uint index)) (if index == 7 then .array .nil else uint 0)
  let selectedRegion := .conditional (equals (.ident strategy) (bigint 0))
    (.ident runtime.createKeyedRegion) (.ident runtime.createDeltaKeyedRegion)
  let initialStatus := "0 visible / 0 source"
  let body : List Stmt := [
    .const root (call runtime.createElement [.literal (.string "main")]),
    setAttribute runtime (.ident root) "class" (.literal (.string "leanrx-grid")),
    .const title (call runtime.createElement [.literal (.string "h1")]),
    .const titleText (call runtime.createText [.literal (.string checked.spec.name)]),
    .expr <| call runtime.append [.ident title, .ident titleText],
    .expr <| call runtime.append [.ident root, .ident title],
    .const controls (call runtime.createElement [.literal (.string "div")]),
    setAttribute runtime (.ident controls) "role" (.literal (.string "group")),
    setAttribute runtime (.ident controls) "aria-label" (.literal (.string "Grid operations")),
    .expr <| call runtime.append [.ident root, .ident controls],
    .const grid (call runtime.createElement [.literal (.string "div")]),
    setAttribute runtime (.ident grid) "role" (.literal (.string "table")),
    setAttribute runtime (.ident grid) "aria-label" (.literal (.string "10,000 row experiment")),
    .expr <| call runtime.append [.ident root, .ident grid],
    .const status (call runtime.createElement [.literal (.string "p")]),
    setAttribute runtime (.ident status) "role" (.literal (.string "status")),
    .const statusText (call runtime.createText [.literal (.string initialStatus)]),
    .expr <| call runtime.append [.ident status, .ident statusText],
    .expr <| call runtime.append [.ident root, .ident status],
    .const metrics (.array <| .ofList [uint 0, uint 0, uint 0, uint 0, uint 0,
      uint 0, uint 0, .array .nil, uint 0, uint 0]),
    .const work (.array <| .ofList [uint 0, uint 0, uint 0])
  ] ++ buttonStatements ++ [
    setProperty runtime (.ident updateButton) "disabled" (bool true),
    setProperty runtime (.ident swapButton) "disabled" (bool true),
    setProperty runtime (.ident selectButton) "disabled" (bool true),
    .const rows (.array .nil),
    .const state (.array <| .ofList [
      .ident rows, bool false, bool false, null, .array .nil, .ident strategy,
      .literal (.string initialStatus)]),
    .const region (callExpr selectedRegion [
      .ident grid, .ident mountRow, .ident updateRow, .ident disposeRow, .ident rowRoot]),
    .const context (.array <| .ofList [.ident region, .ident statusText, .ident metrics,
      .ident work, .ident updateButton, .ident swapButton, .ident selectButton]),
    .expr <| call runtime.append [.ident target, .ident root]
  ] ++ resetMetrics ++ [
    .assign (.index (.ident work) (uint 0)) (uint 0),
    .assign (.index (.ident work) (uint 1)) (uint 0),
    .assign (.index (.ident work) (uint 2)) (uint 0),
    .const offControls (call runtime.listenDelegated [
      .ident controls, .literal (.string "click"), .ident state, .ident context, .ident dispatch]),
    .const disposer (call runtime.makeDisposer [
      .ident root,
      .array <| .ofList [.ident offControls, property (.ident region) "dispose"],
      .ident metrics,
      .array <| .ofList [.ident region],
      .ident work]),
    .return (.ident disposer)
  ]
  pure { name, params := #[target, strategy], body := body.toArray }

private def mountWrapper (nameValue : String) (strategyValue : Nat) (mountStrategy : Ident) :
    Except Error Function := do
  let name ← Ident.checked nameValue
  let target ← Ident.checked "target"
  pure {
    name
    params := #[target]
    body := #[.return <| call mountStrategy [.ident target, bigint strategyValue]]
  }

private def manifest (moduleName : String) (checked : LeanRx.Grid.Spec.Checked) : ComponentManifest := {
  compilerVersion := LeanRx.version
  leanToolchain := LeanRx.leanToolchain
  moduleName
  graphHash := s!"grid:{checked.spec.rowCount}:{checked.spec.updateId}:{checked.spec.removeDivisor}:" ++
    s!"{checked.spec.swapFirst}:{checked.spec.swapSecond}:{checked.spec.selectId}:" ++
    s!"{checked.spec.costModel.maxDeltaEdits}:{checked.spec.costModel.deltaFixedCost}:" ++
    s!"{checked.spec.costModel.deltaEditCost}:{checked.spec.costModel.fullRowCost}"
  runtimeAbi := LeanRx.runtimeAbi
  exports := #["mountFull", "mountDelta", "mountHybrid"]
  stateSlots := #[
    .list (.record "GridRow"), .bool, .bool, .record "OptionNat",
    .list (.record "ProjectedGridRow"), .nat, .string
  ]
  sourceCount := 4
  derivedCount := 1
  textSinkCount := 2
  eventCount := 7
  hostImports := #["./leanrx_dom.mjs", "./leanrx_region.mjs", "./leanrx_delta_region.mjs"]
  features := #["direct-dom", "keyed-region", "structural-delta", "hybrid-cost-model",
    "instrumentation", "reference-propagation"]
}

def emit (moduleName : String) (checked : LeanRx.Grid.Spec.Checked) : Except Error Emitted := do
  let runtime ← runtimeNames
  let createRows ← createRowsFunction runtime
  let keepRow ← keepRowFunction checked.spec.removeDivisor
  let rowText ← rowTextFunction runtime
  let projectRow ← projectRowFunction
  let compareRows ← compareRowsFunction
  let visible ← visibleFunction projectRow.name compareRows.name
  let findIndex ← findIndexFunction
  let mountRow ← mountRowFunction runtime rowText.name
  let updateRow ← updateRowFunction runtime rowText.name
  let disposeRow ← disposeRowFunction
  let rowRoot ← rowRootFunction
  let finish ← finishFunction runtime
  let fullCommit ← fullCommitFunction visible.name finish.name
  let plannedCommit ← plannedCommitFunction checked.spec.costModel
    fullCommit.name finish.name
  let create ← createOperationFunction runtime checked.spec createRows.name visible.name
    fullCommit.name finish.name
  let updateOne ← updateOperationFunction checked.spec findIndex.name projectRow.name
    fullCommit.name plannedCommit.name
  let remove ← removeOperationFunction runtime checked.spec keepRow.name fullCommit.name
    plannedCommit.name
  let swap ← swapOperationFunction checked.spec findIndex.name visible.name fullCommit.name
    plannedCommit.name
  let filter ← resetProjectionOperationFunction "$lrx_gridFilter" .filterRows 1
    visible.name fullCommit.name finish.name
  let sort ← resetProjectionOperationFunction "$lrx_gridSort" .sortRows 2
    visible.name fullCommit.name finish.name
  let select ← selectOperationFunction checked.spec findIndex.name projectRow.name
    fullCommit.name plannedCommit.name
  let dispatch ← dispatchFunction [
    (.createRows, create.name), (.updateOne, updateOne.name), (.removeRows, remove.name),
    (.swapRows, swap.name), (.filterRows, filter.name), (.sortRows, sort.name),
    (.selectRow, select.name)]
  let mountStrategy ← mountStrategyFunction runtime checked
    mountRow.name updateRow.name disposeRow.name rowRoot.name dispatch.name
  let mountFull ← mountWrapper "mountFull" 0 mountStrategy.name
  let mountDelta ← mountWrapper "mountDelta" 1 mountStrategy.name
  let mountHybrid ← mountWrapper "mountHybrid" 2 mountStrategy.name
  let declarations : Array Decl := #[
    .function createRows, .function keepRow, .function rowText, .function projectRow,
    .function compareRows, .function visible, .function findIndex, .function mountRow,
    .function updateRow,
    .function disposeRow, .function rowRoot, .function finish, .function fullCommit,
    .function plannedCommit, .function create, .function updateOne, .function remove,
    .function swap, .function filter, .function sort, .function select, .function dispatch,
    .function mountStrategy, .function mountFull, .function mountDelta, .function mountHybrid
  ]
  let module : Module := {
    globals := #[runtime.array, runtime.bigInt, runtime.string]
    imports := #[
      { source := "./leanrx_dom.mjs", names := #[
          (runtime.createElement, runtime.createElement),
          (runtime.createText, runtime.createText),
          (runtime.setAttribute, runtime.setAttribute),
          (runtime.setProperty, runtime.setProperty),
          (runtime.append, runtime.append),
          (runtime.setText, runtime.setText),
          (runtime.listenDelegated, runtime.listenDelegated),
          (runtime.makeDisposer, runtime.makeDisposer)
        ] },
      { source := "./leanrx_region.mjs", names := #[
          (runtime.createKeyedRegion, runtime.createKeyedRegion)
        ] },
      { source := "./leanrx_delta_region.mjs", names := #[
          (runtime.createDeltaKeyedRegion, runtime.createDeltaKeyedRegion)
        ] }
    ]
    declarations
    exports := #[
      { localName := mountFull.name, exportName := mountFull.name },
      { localName := mountDelta.name, exportName := mountDelta.name },
      { localName := mountHybrid.name, exportName := mountHybrid.name }
    ]
  }
  module.validate
  pure ⟨module, manifest moduleName checked⟩

end LeanRx.Backend.Grid
