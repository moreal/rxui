import LeanRx.Backend.Manifest
import LeanRx.Component.Tabs
import LeanRx.Graph.Serialize

namespace LeanRx.Backend.Tabs

open LeanRx.Js

structure Emitted where
  private mk ::
  module : Module
  manifest : ComponentManifest
deriving Repr, BEq

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))

private def arrayAt (value : Ident) (index : Nat) : Expr :=
  .index (.ident value) (uint index)

private def call (name : Ident) (args : List Expr) : Expr :=
  .call (.ident name) (.ofList args)

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def pushTrace (metrics : Ident) (message : String) : Stmt :=
  .expr <| .call
    (.index (arrayAt metrics 7) (.literal (.string "push")))
    (.ofList [.literal (.string message)])

private def stringArray (values : Vector String count) : Expr :=
  .array <| .ofList <| values.toList.map fun value => .literal (.string value)

private structure RuntimeNames where
  createElement : Ident
  createText : Ident
  setAttribute : Ident
  append : Ident
  listen : Ident
  setText : Ident
  makeDisposer : Ident

private def runtimeNames : Except Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    append := ← Ident.checked "append"
    listen := ← Ident.checked "listen"
    setText := ← Ident.checked "setText"
    makeDisposer := ← Ident.checked "makeDisposer"
  }

private def selectFunction (runtime : RuntimeNames) (panelEvaluator : Ident)
    (event : TypedEventSpec (TabsState count) (Fin count)) : Except Error Function := do
  let select ← Ident.checked s!"$lrx_{event.name}"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let index ← Ident.checked event.parameterName
  let metrics ← Ident.checked "metrics"
  pure {
    name := select
    params := #[state, context, index]
    body := #[
      .const metrics (arrayAt context 2),
      pushTrace metrics s!"event:{event.name}",
      .assign (.index (.ident state) (uint event.target.index)) (.ident index),
      incrementAt metrics 2,
      pushTrace metrics s!"source:{event.target.name}:write",
      incrementAt metrics 5,
      pushTrace metrics "sink:panel:evaluated",
      .expr <| call runtime.setText [arrayAt context 0,
        call panelEvaluator [arrayAt context 1, arrayAt state 0]],
      incrementAt metrics 6,
      pushTrace metrics "dom:panel:write",
      incrementAt metrics 1,
      pushTrace metrics "transaction:commit",
      .return (.literal .null)
    ]
  }

private def handlerName (select : Ident) (index : Nat) : Except Error Ident :=
  Ident.checked s!"{select.raw}_{index}"

private def handlerFunction (select : Ident) (index : Nat) : Except Error Function := do
  let name ← handlerName select index
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  pure {
    name
    params := #[state, context]
    body := #[.return <| call select [.ident state, .ident context, uint index]]
  }

private def hash (value : String) : Nat :=
  value.toList.foldl
    (fun current char => (current * 16777619 + char.toNat) % 4294967296) 2166136261

private def manifest (moduleName : String) (checked : TabsSpec.Checked n) : ComponentManifest :=
  let count := checked.spec.props.count
  { compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := toString (hash checked.graph.toJson)
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := #[.fin count]
    sourceCount := 1
    derivedCount := 0
    textSinkCount := 1
    eventCount := 1
    hostImports := #["./leanrx_dom.mjs", "./leanrx_host.mjs"]
    features := #["dependent", "immutable-props", "typed-events", "proof-erasure", "direct-dom"] }

/-- Emit one checked dependent Tabs component through the same typed scalar
evaluator, JavaScript AST, printer, and tiny DOM host boundaries as scalar
components. -/
def emit (moduleName : String) (checked : TabsSpec.Checked n) : Except Error Emitted := do
  let count := checked.spec.props.count
  if count >= UInt32.size then
    throw {
      code := "LRX-BE-029"
      message := "dependent vector length exceeds the JavaScript array-index ABI"
    }
  unless checked.event.payloadType == .fin count do
    throw {
      code := "LRX-BE-030"
      message := "typed event payload disagrees with the erased finite-index ABI"
    }
  let runtime ← runtimeNames
  let panelEvaluator ← Scalar.moduleFor "$lrx_panel" #[
    { name := checked.spec.props.panels.name, valueType := .vector .string count },
    { name := checked.event.target.name, valueType := .fin count }
  ] <| Lower.rxExpr (TabsSpec.selectedPanelExpr n)
  let select ← selectFunction runtime panelEvaluator.exportName checked.event
  let selectName := select.name
  let handlers ← List.range count |>.mapM (handlerFunction selectName)
  let mount ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let state ← Ident.checked "state"
  let panels ← Ident.checked "panels"
  let root ← Ident.checked "root"
  let title ← Ident.checked "title"
  let titleText ← Ident.checked "titleText"
  let panel ← Ident.checked "panel"
  let panelText ← Ident.checked "panelText"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let disposer ← Ident.checked "disposer"
  let mut body : List Stmt := [
    .const state (.array <| .ofList [uint checked.spec.initialSelected.val]),
    .const panels (stringArray checked.spec.props.panels.value),
    .const root (call runtime.createElement [.literal (.string "main")]),
    .expr <| call runtime.setAttribute [
      .ident root, .literal (.string "class"), .literal (.string "leanrx-tabs")],
    .const title (call runtime.createElement [.literal (.string "h1")]),
    .const titleText (call runtime.createText [.literal (.string checked.spec.name)]),
    .expr <| call runtime.append [.ident title, .ident titleText],
    .expr <| call runtime.append [.ident root, .ident title]
  ]
  let mut buttonNames : List Ident := []
  for (label, index) in checked.spec.props.labels.value.toList.zipIdx do
    let button ← Ident.checked s!"button_{index}"
    let text ← Ident.checked s!"button_text_{index}"
    buttonNames := buttonNames ++ [button]
    body := body ++ [
      .const button (call runtime.createElement [.literal (.string "button")]),
      .expr <| call runtime.setAttribute [
        .ident button, .literal (.string "type"), .literal (.string "button")],
      .expr <| call runtime.setAttribute [
        .ident button, .literal (.string "aria-label"), .literal (.string label)],
      .const text (call runtime.createText [.literal (.string label)]),
      .expr <| call runtime.append [.ident button, .ident text],
      .expr <| call runtime.append [.ident root, .ident button]
    ]
  body := body ++ [
    .const panel (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident panel, .literal (.string "aria-live"), .literal (.string "polite")],
    .const panelText (call runtime.createText [
      call panelEvaluator.exportName [.ident panels, arrayAt state 0]]),
    .expr <| call runtime.append [.ident panel, .ident panelText],
    .expr <| call runtime.append [.ident root, .ident panel],
    .const metrics (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil]),
    .const context (.array <| .ofList [.ident panelText, .ident panels, .ident metrics]),
    .expr <| call runtime.append [.ident target, .ident root]
  ]
  let mut offNames : List Ident := []
  for (button, index) in buttonNames.zipIdx do
    let off ← Ident.checked s!"off_{index}"
    let handler ← handlerName selectName index
    offNames := offNames ++ [off]
    body := body ++ [.const off <| call runtime.listen [
      .ident button, .literal (.string "click"), .ident state, .ident context, .ident handler
    ]]
  body := body ++ [
    .const disposer <| call runtime.makeDisposer [
      .ident root, .array (.ofList <| offNames.map Expr.ident), .ident metrics],
    .return (.ident disposer)
  ]
  let module : Module :=
    { globals := panelEvaluator.module.globals
      imports := #[
        { source := "./leanrx_dom.mjs", names := #[
            (runtime.createElement, runtime.createElement),
            (runtime.createText, runtime.createText),
            (runtime.setAttribute, runtime.setAttribute),
            (runtime.append, runtime.append),
            (runtime.listen, runtime.listen),
            (runtime.setText, runtime.setText)
          ] },
        { source := "./leanrx_host.mjs", names := #[
            (runtime.makeDisposer, runtime.makeDisposer)
          ] }
      ]
      declarations := (panelEvaluator.module.declarations.toList ++
        [Decl.function select] ++ handlers.map Decl.function ++ [
          Decl.function { name := mount, params := #[target], body := body.toArray }
        ]).toArray
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Tabs
