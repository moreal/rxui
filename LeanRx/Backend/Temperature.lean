import LeanRx.Backend.Manifest
import LeanRx.Form.Temperature
import LeanRx.Graph.Serialize

namespace LeanRx.Backend.Temperature

open LeanRx.Js
open LeanRx.Form

structure Emitted where
  private mk ::
  module : Module
  manifest : ComponentManifest
deriving Repr, BEq

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))

private def arrayAt (value : Ident) (index : Nat) : Expr :=
  .index (.ident value) (uint index)

private def property (value : Expr) (name : String) : Expr :=
  .index value (.literal (.string name))

private def call (name : Ident) (args : List Expr) : Expr :=
  .call (.ident name) (.ofList args)

private def callExpr (callee : Expr) (args : List Expr) : Expr :=
  .call callee (.ofList args)

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def pushTrace (metrics : Ident) (message : String) : Stmt :=
  .expr <| callExpr (property (arrayAt metrics 7) "push") [.literal (.string message)]

private structure RuntimeNames where
  createElement : Ident
  createText : Ident
  setAttribute : Ident
  append : Ident
  setText : Ident
  setProperty : Ident
  listenValue : Ident
  makeDisposer : Ident
  string : Ident
  bigInt : Ident

private def runtimeNames : Except Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    append := ← Ident.checked "append"
    setText := ← Ident.checked "setText"
    setProperty := ← Ident.checked "setProperty"
    listenValue := ← Ident.checked "listenValue"
    makeDisposer := ← Ident.checked "makeDisposer"
    string := ← Ident.checked "String"
    bigInt := ← Ident.checked "BigInt"
  }

private def invalidMessage (scale : TemperatureScale) : String :=
  s!"Enter an integer {scale.name} temperature."

private def validInput (value : Ident) : Expr :=
  callExpr (property (.literal .signedIntegerPattern) "test") [.ident value]

private def converted (scale : TemperatureScale) (parsed : Ident) : Expr :=
  match scale with
  | .celsius => .binary .add
      (.binary .div (.binary .mul (.ident parsed) (.literal (.bigint 9)))
        (.literal (.bigint 5)))
      (.literal (.bigint 32))
  | .fahrenheit => .binary .div
      (.binary .mul (.binary .sub (.ident parsed) (.literal (.bigint 32)))
        (.literal (.bigint 5)))
      (.literal (.bigint 9))

private def updateError (runtime : RuntimeNames) (errorCache errorText metrics : Ident)
    (message : String) : Stmt :=
  .ifThen (.unary .not <| .binary .eq (arrayAt errorCache 0) (.literal (.string message))) <|
    .ofList [
      .assign (.index (.ident errorCache) (uint 0)) (.literal (.string message)),
      .expr <| call runtime.setText [.ident errorText, .literal (.string message)],
      incrementAt metrics 5,
      incrementAt metrics 6,
      pushTrace metrics "dom:temperatureError:write"
    ]

private def editFunction (runtime : RuntimeNames) (event : TypedEventSpec TemperatureState String)
    (scale : TemperatureScale) : Except Error Function := do
  let name ← Ident.checked s!"$lrx_{event.name}"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let value ← Ident.checked event.parameterName
  let metrics ← Ident.checked "metrics"
  let errorCache ← Ident.checked "errorCache"
  let errorText ← Ident.checked "errorText"
  let parsed ← Ident.checked "parsed"
  let next ← Ident.checked "next"
  let ownIndex := event.target.index
  let otherIndex := if ownIndex == 0 then 1 else 0
  let otherInput := arrayAt context otherIndex
  let validBody : List Stmt := [
    .const parsed (call runtime.bigInt [.ident value]),
    .const next (call runtime.string [converted scale parsed]),
    .ifThen (.unary .not <| .binary .eq (arrayAt state otherIndex) (.ident next)) <| .ofList [
      .assign (.index (.ident state) (uint otherIndex)) (.ident next),
      .expr <| call runtime.setProperty [
        otherInput, .literal (.string "value"), .ident next],
      incrementAt metrics 4,
      incrementAt metrics 5,
      incrementAt metrics 6,
      pushTrace metrics s!"dom:{if otherIndex == 0 then "celsius" else "fahrenheit"}:value"
    ],
    updateError runtime errorCache errorText metrics ""
  ]
  pure {
    name
    params := #[state, context, value]
    body := #[
      .const metrics (arrayAt context 3),
      .const errorCache (arrayAt context 4),
      .const errorText (arrayAt context 2),
      pushTrace metrics s!"event:{event.name}",
      incrementAt metrics 2,
      pushTrace metrics s!"source:{event.target.name}:write",
      .ifThen (.unary .not <| .binary .eq (arrayAt state ownIndex) (.ident value)) <|
        .ofList [
          .assign (.index (.ident state) (uint ownIndex)) (.ident value),
          incrementAt metrics 3,
          .ifThen (.unary .not <| validInput value) <| .ofList [
            updateError runtime errorCache errorText metrics (invalidMessage scale)
          ],
          .ifThen (validInput value) (.ofList validBody)
        ],
      incrementAt metrics 1,
      pushTrace metrics "transaction:commit",
      .return (.literal .null)
    ]
  }

private def hash (value : String) : Nat :=
  value.toList.foldl
    (fun current char => (current * 16777619 + char.toNat) % 4294967296) 2166136261

private def manifest (moduleName : String) (checked : TemperatureSpec.Checked) : ComponentManifest :=
  { compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := toString (hash checked.graph.toJson)
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := #[.string, .string]
    sourceCount := 2
    derivedCount := 0
    textSinkCount := 3
    eventCount := 2
    hostImports := #["./leanrx_dom.mjs", "./leanrx_host.mjs"]
    features := #["forms", "controlled-input", "typed-events", "validation",
      "actual-change", "instrumentation", "trace"] }

def emit (moduleName : String) (checked : TemperatureSpec.Checked) : Except Error Emitted := do
  let runtime ← runtimeNames
  let editCelsius ← editFunction runtime checked.celsiusEvent .celsius
  let editFahrenheit ← editFunction runtime checked.fahrenheitEvent .fahrenheit
  let mount ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let state ← Ident.checked "state"
  let root ← Ident.checked "root"
  let title ← Ident.checked "title"
  let titleText ← Ident.checked "titleText"
  let celsiusLabel ← Ident.checked "celsiusLabel"
  let celsiusLabelText ← Ident.checked "celsiusLabelText"
  let celsiusInput ← Ident.checked "celsiusInput"
  let fahrenheitLabel ← Ident.checked "fahrenheitLabel"
  let fahrenheitLabelText ← Ident.checked "fahrenheitLabelText"
  let fahrenheitInput ← Ident.checked "fahrenheitInput"
  let errorNode ← Ident.checked "errorNode"
  let errorText ← Ident.checked "errorText"
  let metrics ← Ident.checked "metrics"
  let errorCache ← Ident.checked "errorCache"
  let context ← Ident.checked "context"
  let offCelsius ← Ident.checked "offCelsius"
  let offFahrenheit ← Ident.checked "offFahrenheit"
  let disposer ← Ident.checked "disposer"
  let body : Array Stmt := #[
    .const state (.array <| .ofList [
      .literal (.string checked.spec.initialCelsius),
      .literal (.string checked.spec.initialFahrenheit)]),
    .const root (call runtime.createElement [.literal (.string "main")]),
    .expr <| call runtime.setAttribute [
      .ident root, .literal (.string "class"), .literal (.string "temperature-converter")],
    .const title (call runtime.createElement [.literal (.string "h1")]),
    .const titleText (call runtime.createText [.literal (.string checked.spec.name)]),
    .expr <| call runtime.append [.ident title, .ident titleText],
    .expr <| call runtime.append [.ident root, .ident title],
    .const celsiusLabel (call runtime.createElement [.literal (.string "label")]),
    .const celsiusLabelText (call runtime.createText [.literal (.string "Celsius ")]),
    .expr <| call runtime.append [.ident celsiusLabel, .ident celsiusLabelText],
    .const celsiusInput (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [
      .ident celsiusInput, .literal (.string "type"), .literal (.string "text")],
    .expr <| call runtime.setAttribute [
      .ident celsiusInput, .literal (.string "inputmode"), .literal (.string "numeric")],
    .expr <| call runtime.setProperty [
      .ident celsiusInput, .literal (.string "value"),
      .literal (.string checked.spec.initialCelsius)],
    .expr <| call runtime.append [.ident celsiusLabel, .ident celsiusInput],
    .expr <| call runtime.append [.ident root, .ident celsiusLabel],
    .const fahrenheitLabel (call runtime.createElement [.literal (.string "label")]),
    .const fahrenheitLabelText (call runtime.createText [.literal (.string "Fahrenheit ")]),
    .expr <| call runtime.append [.ident fahrenheitLabel, .ident fahrenheitLabelText],
    .const fahrenheitInput (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [
      .ident fahrenheitInput, .literal (.string "type"), .literal (.string "text")],
    .expr <| call runtime.setAttribute [
      .ident fahrenheitInput, .literal (.string "inputmode"), .literal (.string "numeric")],
    .expr <| call runtime.setProperty [
      .ident fahrenheitInput, .literal (.string "value"),
      .literal (.string checked.spec.initialFahrenheit)],
    .expr <| call runtime.append [.ident fahrenheitLabel, .ident fahrenheitInput],
    .expr <| call runtime.append [.ident root, .ident fahrenheitLabel],
    .const errorNode (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident errorNode, .literal (.string "aria-live"), .literal (.string "polite")],
    .const errorText (call runtime.createText [.literal (.string "")]),
    .expr <| call runtime.append [.ident errorNode, .ident errorText],
    .expr <| call runtime.append [.ident root, .ident errorNode],
    .const metrics (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil]),
    .const errorCache (.array <| .ofList [.literal (.string "")]),
    .const context (.array <| .ofList [
      .ident celsiusInput, .ident fahrenheitInput, .ident errorText,
      .ident metrics, .ident errorCache]),
    .expr <| call runtime.append [.ident target, .ident root],
    .const offCelsius <| call runtime.listenValue [
      .ident celsiusInput, .literal (.string "input"), .ident state, .ident context,
      .ident editCelsius.name],
    .const offFahrenheit <| call runtime.listenValue [
      .ident fahrenheitInput, .literal (.string "input"), .ident state, .ident context,
      .ident editFahrenheit.name],
    .const disposer <| call runtime.makeDisposer [
      .ident root, .array (.ofList [.ident offCelsius, .ident offFahrenheit]), .ident metrics],
    .return (.ident disposer)
  ]
  let module : Module :=
    { globals := #[runtime.string, runtime.bigInt]
      imports := #[
        { source := "./leanrx_dom.mjs", names := #[
            (runtime.createElement, runtime.createElement),
            (runtime.createText, runtime.createText),
            (runtime.setAttribute, runtime.setAttribute),
            (runtime.append, runtime.append),
            (runtime.setText, runtime.setText),
            (runtime.setProperty, runtime.setProperty),
            (runtime.listenValue, runtime.listenValue)
          ] },
        { source := "./leanrx_host.mjs", names := #[
            (runtime.makeDisposer, runtime.makeDisposer)
          ] }
      ]
      declarations := #[.function editCelsius, .function editFahrenheit,
        .function { name := mount, params := #[target], body }]
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Temperature
