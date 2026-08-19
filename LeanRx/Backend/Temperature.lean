import LeanRx.Backend.Manifest
import LeanRx.Backend.FormDom
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
  uniqueId : Ident
  listenValue : Ident
  listenChecked : Ident
  listenKey : Ident
  listenFocus : Ident
  listenSubmit : Ident
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
    uniqueId := ← Ident.checked "uniqueId"
    listenValue := ← Ident.checked "listenValue"
    listenChecked := ← Ident.checked "listenChecked"
    listenKey := ← Ident.checked "listenKey"
    listenFocus := ← Ident.checked "listenFocus"
    listenSubmit := ← Ident.checked "listenSubmit"
    makeDisposer := ← Ident.checked "makeDisposer"
    string := ← Ident.checked "String"
    bigInt := ← Ident.checked "BigInt"
  }

private def listenerRuntime (runtime : RuntimeNames) : FormDom.ListenerRuntime := {
  value := runtime.listenValue
  checked := runtime.listenChecked
  key := runtime.listenKey
  focus := runtime.listenFocus
  submit := runtime.listenSubmit
}

private def setProperty (runtime : RuntimeNames) (target : Expr)
    (property : DomProperty α) (value : Expr) : Expr :=
  FormDom.setProperty runtime.setProperty target property value

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
      incrementAt metrics 6,
      pushTrace metrics "dom:temperatureError:write"
    ]

private def updateInvalid (runtime : RuntimeNames) (context invalidCache metrics : Ident)
    (index : Nat) (invalid : Bool) : Stmt :=
  let value := .literal (.boolean invalid)
  .ifThen (.unary .not <| .binary .eq (arrayAt invalidCache index) value) <| .ofList [
    .assign (.index (.ident invalidCache) (uint index)) value,
    .expr <| call runtime.setAttribute [arrayAt context index,
      .literal (.string "aria-invalid"), .literal (.string (if invalid then "true" else "false"))],
    incrementAt metrics 6,
    pushTrace metrics s!"dom:{if index == 0 then "celsius" else "fahrenheit"}:aria-invalid"
  ]

private def presentation (runtime : RuntimeNames) (context errorCache errorText invalidCache
    metrics : Ident) (ownIndex : Nat) (message : String) (invalid : Bool) : List Stmt := [
  incrementAt metrics 5,
  pushTrace metrics "sink:temperatureError:evaluated",
  updateError runtime errorCache errorText metrics message,
  incrementAt metrics 5,
  pushTrace metrics "sink:celsiusInvalid:evaluated",
  updateInvalid runtime context invalidCache metrics 0 (invalid && ownIndex == 0),
  incrementAt metrics 5,
  pushTrace metrics "sink:fahrenheitInvalid:evaluated",
  updateInvalid runtime context invalidCache metrics 1 (invalid && ownIndex == 1)
]

private def editFunction (runtime : RuntimeNames) (plan : TemperatureSpec.UpdatePlan) :
    Except Error Function := do
  let event := plan.binding.update
  let scale := plan.scale
  let name ← Ident.checked s!"$lrx_{event.name}"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let value ← Ident.checked event.parameterName
  let metrics ← Ident.checked "metrics"
  let errorCache ← Ident.checked "errorCache"
  let propertyCache ← Ident.checked "propertyCache"
  let invalidCache ← Ident.checked "invalidCache"
  let errorText ← Ident.checked "errorText"
  let lexical ← Ident.checked "lexical"
  let parsed ← Ident.checked "parsed"
  let next ← Ident.checked "next"
  let ownIndex := plan.binding.target.index
  let otherIndex := plan.convertedTarget.index
  let otherInput := arrayAt context otherIndex
  let validBody : List Stmt := [
    .const parsed (call runtime.bigInt [.ident value]),
    .const next (call runtime.string [converted scale parsed]),
    incrementAt metrics 2,
    pushTrace metrics s!"source:{plan.convertedTarget.name}:write",
    .ifThen (.unary .not <| .binary .eq (arrayAt state otherIndex) (.ident next)) <| .ofList [
      .assign (.index (.ident state) (uint otherIndex)) (.ident next),
      incrementAt metrics 5,
      pushTrace metrics s!"sink:{if otherIndex == 0 then "celsiusValue" else "fahrenheitValue"}:evaluated",
      .ifThen (.unary .not <| .binary .eq (arrayAt propertyCache otherIndex) (.ident next)) <|
        .ofList [
          .assign (.index (.ident propertyCache) (uint otherIndex)) (.ident next),
          .expr <| setProperty runtime otherInput plan.convertedProperty (.ident next),
          incrementAt metrics 6,
          pushTrace metrics s!"dom:{if otherIndex == 0 then "celsius" else "fahrenheit"}:value"
        ]
    ]
  ] ++ presentation runtime context errorCache errorText invalidCache metrics ownIndex "" false
  let invalidBody := presentation runtime context errorCache errorText invalidCache metrics
    ownIndex (invalidMessage scale) true
  pure {
    name
    params := #[state, context, value]
    body := #[
      .const metrics (arrayAt context 3),
      .const errorCache (arrayAt context 4),
      .const propertyCache (arrayAt context 5),
      .const invalidCache (arrayAt context 6),
      .const errorText (arrayAt context 2),
      pushTrace metrics s!"event:{event.name}",
      incrementAt metrics 2,
      pushTrace metrics s!"source:{plan.binding.target.name}:write",
      .ifThen (.unary .not <| .binary .eq (arrayAt state ownIndex) (.ident value)) <|
        .ofList [
          .assign (.index (.ident state) (uint ownIndex)) (.ident value),
          .assign (.index (.ident propertyCache) (uint ownIndex)) (.ident value),
          incrementAt metrics 5,
          pushTrace metrics s!"sink:{if ownIndex == 0 then "celsiusValue" else "fahrenheitValue"}:evaluated",
          .const lexical (validInput value),
          pushTrace metrics "validation:signedInteger:evaluated",
          .ifThen (.unary .not <| .ident lexical) (.ofList invalidBody),
          .ifThen (.ident lexical) (.ofList validBody)
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
    textSinkCount := 1
    eventCount := 2
    hostImports := #["./leanrx_dom.mjs", "./leanrx_host.mjs"]
    features := #["forms", "controlled-input", "typed-events", "validation",
      "actual-change", "instrumentation", "trace"] }

def emit (moduleName : String) (checked : TemperatureSpec.Checked) : Except Error Emitted := do
  let runtime ← runtimeNames
  let editCelsius ← editFunction runtime checked.celsiusUpdate
  let editFahrenheit ← editFunction runtime checked.fahrenheitUpdate
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
  let errorId ← Ident.checked "errorId"
  let errorText ← Ident.checked "errorText"
  let metrics ← Ident.checked "metrics"
  let errorCache ← Ident.checked "errorCache"
  let propertyCache ← Ident.checked "propertyCache"
  let invalidCache ← Ident.checked "invalidCache"
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
    .const errorId (call runtime.uniqueId [.literal (.string "lrx-temperature-error")]),
    .const celsiusLabel (call runtime.createElement [.literal (.string "label")]),
    .const celsiusLabelText (call runtime.createText [.literal (.string "Celsius ")]),
    .expr <| call runtime.append [.ident celsiusLabel, .ident celsiusLabelText],
    .const celsiusInput (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [
      .ident celsiusInput, .literal (.string "type"), .literal (.string "text")],
    .expr <| call runtime.setAttribute [
      .ident celsiusInput, .literal (.string "inputmode"), .literal (.string "numeric")],
    .expr <| call runtime.setAttribute [
      .ident celsiusInput, .literal (.string "aria-describedby"), .ident errorId],
    .expr <| call runtime.setAttribute [
      .ident celsiusInput, .literal (.string "aria-invalid"), .literal (.string "false")],
    .expr <| setProperty runtime (.ident celsiusInput)
      checked.celsiusUpdate.binding.property (.literal (.string checked.spec.initialCelsius)),
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
    .expr <| call runtime.setAttribute [
      .ident fahrenheitInput, .literal (.string "aria-describedby"), .ident errorId],
    .expr <| call runtime.setAttribute [
      .ident fahrenheitInput, .literal (.string "aria-invalid"), .literal (.string "false")],
    .expr <| setProperty runtime (.ident fahrenheitInput)
      checked.fahrenheitUpdate.binding.property (.literal (.string checked.spec.initialFahrenheit)),
    .expr <| call runtime.append [.ident fahrenheitLabel, .ident fahrenheitInput],
    .expr <| call runtime.append [.ident root, .ident fahrenheitLabel],
    .const errorNode (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident errorNode, .literal (.string "id"), .ident errorId],
    .expr <| call runtime.setAttribute [
      .ident errorNode, .literal (.string "aria-live"), .literal (.string "polite")],
    .const errorText (call runtime.createText [.literal (.string "")]),
    .expr <| call runtime.append [.ident errorNode, .ident errorText],
    .expr <| call runtime.append [.ident root, .ident errorNode],
    .const metrics (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil]),
    .const errorCache (.array <| .ofList [.literal (.string "")]),
    .const propertyCache (.array <| .ofList [
      .literal (.string checked.spec.initialCelsius),
      .literal (.string checked.spec.initialFahrenheit)]),
    .const invalidCache (.array <| .ofList [
      .literal (.boolean false), .literal (.boolean false)]),
    .const context (.array <| .ofList [
      .ident celsiusInput, .ident fahrenheitInput, .ident errorText,
      .ident metrics, .ident errorCache, .ident propertyCache, .ident invalidCache]),
    .expr <| call runtime.append [.ident target, .ident root],
    .const offCelsius <| FormDom.listen (listenerRuntime runtime)
      checked.celsiusUpdate.binding.event (.ident celsiusInput) (.ident state) (.ident context)
      editCelsius.name,
    .const offFahrenheit <| FormDom.listen (listenerRuntime runtime)
      checked.fahrenheitUpdate.binding.event (.ident fahrenheitInput) (.ident state) (.ident context)
      editFahrenheit.name,
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
            (runtime.uniqueId, runtime.uniqueId),
            (runtime.listenValue, runtime.listenValue),
            (runtime.listenChecked, runtime.listenChecked),
            (runtime.listenKey, runtime.listenKey),
            (runtime.listenFocus, runtime.listenFocus),
            (runtime.listenSubmit, runtime.listenSubmit)
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
