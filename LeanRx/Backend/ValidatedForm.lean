import LeanRx.Backend.Manifest
import LeanRx.Backend.FormDom
import LeanRx.Form.Validated
import LeanRx.Graph.Serialize

namespace LeanRx.Backend.ValidatedForm

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

private def pushTrace (metrics : Ident) (message : Expr) : Stmt :=
  .expr <| callExpr (property (arrayAt metrics 7) "push") [message]

private def trace (metrics : Ident) (message : String) : Stmt :=
  pushTrace metrics (.literal (.string message))

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

private def validateName : Except Error Ident := Ident.checked "$lrx_validateForm"
private def renderName : Except Error Ident := Ident.checked "$lrx_renderValidation"

private def validatorFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← validateName
  let state ← Ident.checked "state"
  let trimmedName ← Ident.checked "trimmedName"
  let nameValid ← Ident.checked "nameValid"
  let ageLexical ← Ident.checked "ageLexical"
  let ageValue ← Ident.checked "ageValue"
  let ageValid ← Ident.checked "ageValid"
  let valid ← Ident.checked "valid"
  let rawName := arrayAt state 0
  let rawAge := arrayAt state 1
  let trimCall := callExpr (property rawName "replace") [
    .literal .asciiTrimPattern, .literal (.string "")]
  let naturalTest := callExpr (property (.literal .naturalPattern) "test") [rawAge]
  let lowerValid := .binary .le (.literal (.bigint 18)) (.ident ageValue)
  let upperValid := .binary .le (.ident ageValue) (.literal (.bigint 120))
  let withinBounds := .binary .and lowerValid upperValid
  pure {
    name
    params := #[state]
    body := #[
      .const trimmedName trimCall,
      .const nameValid (.unary .not <| .binary .eq (.ident trimmedName) (.literal (.string ""))),
      .const ageLexical naturalTest,
      .const ageValue (.conditional (.ident ageLexical)
        (call runtime.bigInt [rawAge]) (.literal (.bigint 0))),
      .const ageValid (.binary .and (.ident ageLexical) withinBounds),
      .const valid (.binary .and (.ident nameValid)
        (.binary .and (.ident ageValid) (arrayAt state 2))),
      .return <| .array <| .ofList [
        .ident trimmedName,
        .ident ageValue,
        .ident valid,
        .conditional (.ident nameValid) (.literal (.string ""))
          (.literal (.string "name must not be empty")),
        .conditional (.ident ageLexical)
          (.conditional lowerValid
            (.conditional upperValid (.literal (.string ""))
              (.literal (.string "value must be at most 120")))
            (.literal (.string "value must be at least 18")))
          (.literal (.string "enter a non-negative integer using ASCII digits")),
        .conditional (arrayAt state 2) (.literal (.string ""))
          (.literal (.string "terms must be accepted"))
      ]
    ]
  }

private def renderFunction (runtime : RuntimeNames) : Except Error Function := do
  let name ← renderName
  let validator ← validateName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let changedSource ← Ident.checked "changedSource"
  let result ← Ident.checked "result"
  let metrics ← Ident.checked "metrics"
  let cache ← Ident.checked "cache"
  let mut body : List Stmt := [
    .const result (call validator [.ident state]),
    .const metrics (arrayAt context 8),
    .const cache (arrayAt context 9)
  ]
  for (resultIndex, cacheIndex, contextIndex, traceName) in [
      (3, 0, 3, "nameError"), (4, 1, 4, "ageError"), (5, 2, 5, "termsError")
    ] do
    let next := arrayAt result resultIndex
    let oldInvalid ← Ident.checked s!"oldInvalid_{traceName}"
    let nextInvalid ← Ident.checked s!"nextInvalid_{traceName}"
    let affected := .binary .or
      (.binary .eq (.ident changedSource) (uint cacheIndex))
      (.binary .eq (.ident changedSource) (uint 3))
    let sinkBody : List Stmt := [
      incrementAt metrics 5,
      trace metrics s!"sink:{traceName}:evaluated",
      .ifThen (.unary .not <| .binary .eq (arrayAt cache cacheIndex) next) <|
      .ofList [
        .const oldInvalid (.unary .not <|
          .binary .eq (arrayAt cache cacheIndex) (.literal (.string ""))),
        .const nextInvalid (.unary .not <|
          .binary .eq next (.literal (.string ""))),
        .assign (.index (.ident cache) (uint cacheIndex)) next,
        .expr <| call runtime.setText [arrayAt context contextIndex, next],
        incrementAt metrics 6,
        .ifThen (.unary .not <| .binary .eq (.ident oldInvalid) (.ident nextInvalid)) <|
          .ofList [
            .expr <| call runtime.setAttribute [arrayAt context (resultIndex - 3),
              .literal (.string "aria-invalid"),
              .conditional (.ident nextInvalid)
                (.literal (.string "true")) (.literal (.string "false"))],
            incrementAt metrics 6,
            trace metrics s!"dom:{traceName}:aria-invalid"
          ],
        trace metrics s!"dom:{traceName}:write"
      ]]
    body := body ++ [.ifThen affected (.ofList sinkBody)]
  let disabled := .unary .not (arrayAt result 2)
  body := body ++ [incrementAt metrics 5, trace metrics "sink:submitDisabled:evaluated",
    .ifThen (.unary .not <| .binary .eq (arrayAt cache 3) disabled) <|
    .ofList [
      .assign (.index (.ident cache) (uint 3)) disabled,
      .expr <| setProperty runtime (arrayAt context 6) DomProperty.disabled disabled,
      incrementAt metrics 6,
      trace metrics "dom:submit:disabled"
    ], .return (.ident result)]
  pure { name, params := #[state, context, changedSource], body := body.toArray }

private def editStringFunction
    (binding : StateControlBinding ValidatedFormState String) : Except Error Function := do
  let event := binding.update
  let name ← Ident.checked s!"$lrx_{event.name}"
  let render ← renderName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let value ← Ident.checked event.parameterName
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[state, context, value]
    body := #[
      .const metrics (arrayAt context 8),
      trace metrics s!"event:{event.name}",
      incrementAt metrics 2,
      .ifThen (.unary .not <| .binary .eq (arrayAt state event.target.index) (.ident value)) <|
        .ofList [
          .assign (.index (.ident state) (uint event.target.index)) (.ident value),
          .expr <| call render [.ident state, .ident context, uint event.target.index]
        ],
      incrementAt metrics 1,
      trace metrics "transaction:commit",
      .return (.literal .null)
    ]
  }

private def editCheckedFunction (binding : StateControlBinding ValidatedFormState Bool) :
    Except Error Function := do
  let event := binding.update
  let name ← Ident.checked s!"$lrx_{event.name}"
  let render ← renderName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let checked ← Ident.checked event.parameterName
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[state, context, checked]
    body := #[
      .const metrics (arrayAt context 8),
      trace metrics s!"event:{event.name}",
      incrementAt metrics 2,
      .ifThen (.unary .not <| .binary .eq (arrayAt state event.target.index) (.ident checked)) <|
        .ofList [
          .assign (.index (.ident state) (uint event.target.index)) (.ident checked),
          .expr <| call render [.ident state, .ident context, uint event.target.index]
        ],
      incrementAt metrics 1,
      trace metrics "transaction:commit",
      .return (.literal .null)
    ]
  }

private def stringPayloadFunction (binding : ControlBinding String) : Except Error Function := do
  let name ← Ident.checked s!"$lrx_{binding.handlerName}"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let payload ← Ident.checked "payload"
  let metrics ← Ident.checked "metrics"
  pure {
    name
    params := #[state, context, payload]
    body := #[
      .const metrics (arrayAt context 8),
      trace metrics s!"event:{binding.event.name}",
      trace metrics s!"payload:{binding.event.payloadKind.name}",
      .return (.literal .null)
    ]
  }

private def focusFunction (handlerName eventName : String) (render : Bool) : Except Error Function := do
  let name ← Ident.checked s!"$lrx_{handlerName}"
  let renderValidation ← renderName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let body : List Stmt := [
    .const metrics (arrayAt context 8),
    trace metrics s!"event:{eventName}"
  ] ++ (if render then [.expr <| call renderValidation [.ident state, .ident context, uint 3]] else []) ++
    [.return (.literal .null)]
  pure { name, params := #[state, context], body := body.toArray }

private def submitFunction (runtime : RuntimeNames) (handlerName : String) : Except Error Function := do
  let name ← Ident.checked s!"$lrx_{handlerName}"
  let validator ← validateName
  let render ← renderName
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let cache ← Ident.checked "cache"
  let result ← Ident.checked "result"
  let message ← Ident.checked "message"
  let messageExpr := .binary .add
    (.binary .add (.binary .add (.literal (.string "Submitted ")) (arrayAt result 0))
      (.literal (.string " (")))
    (.binary .add (call runtime.string [arrayAt result 1]) (.literal (.string ")")))
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (arrayAt context 8),
      .const cache (arrayAt context 9),
      trace metrics "event:submit",
      .const result (call validator [.ident state]),
      .expr <| call render [.ident state, .ident context, uint 3],
      .ifThen (arrayAt result 2) <| .ofList [
        incrementAt metrics 5,
        trace metrics "sink:submissionStatus:evaluated",
        .const message messageExpr,
        .ifThen (.unary .not <| .binary .eq (arrayAt cache 4) (.ident message)) <| .ofList [
          .assign (.index (.ident cache) (uint 4)) (.ident message),
          .expr <| call runtime.setText [arrayAt context 7, .ident message],
          incrementAt metrics 6
        ],
        trace metrics "command:fakeSubmit"
      ],
      incrementAt metrics 1,
      trace metrics "transaction:commit",
      .return (.literal .null)
    ]
  }

private structure Initial where
  nameError : String
  ageError : String
  termsError : String
  disabled : Bool

private def initial (raw : RawForm) : Initial :=
  match validateForm raw with
  | .valid _ => { nameError := "", ageError := "", termsError := "", disabled := false }
  | .invalid errors => {
      nameError := errors.name.map (·.message) |>.getD ""
      ageError := errors.age.map (·.message) |>.getD ""
      termsError := errors.accepted.map (·.message) |>.getD ""
      disabled := true
    }

private def hash (value : String) : Nat :=
  value.toList.foldl
    (fun current char => (current * 16777619 + char.toNat) % 4294967296) 2166136261

private def manifest (moduleName : String) (checked : ValidatedFormSpec.Checked) : ComponentManifest :=
  { compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := toString (hash checked.graph.toJson)
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := #[.string, .string, .bool]
    sourceCount := 3
    derivedCount := 0
    textSinkCount := 4
    eventCount := 8
    hostImports := #["./leanrx_dom.mjs", "./leanrx_host.mjs"]
    features := #["forms", "controlled-input", "checked", "disabled", "submit",
      "keyboard", "focus", "validation", "typed-command", "instrumentation", "trace"] }

def emit (moduleName : String) (checked : ValidatedFormSpec.Checked) : Except Error Emitted := do
  let runtime ← runtimeNames
  let validator ← validatorFunction runtime
  let render ← renderFunction runtime
  let editName ← editStringFunction checked.nameControl
  let editAge ← editStringFunction checked.ageControl
  let editAccepted ← editCheckedFunction checked.acceptedControl
  let recordAgeChange ← stringPayloadFunction checked.ageChangeBinding
  let recordKey ← stringPayloadFunction checked.keyBinding
  let focusField ← focusFunction checked.focusBinding.handlerName "focus" false
  let blurField ← focusFunction checked.blurBinding.handlerName "blur" false
  let submitValidated ← submitFunction runtime checked.submitBinding.handlerName
  let initial := initial checked.spec.initial
  let mount ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let state ← Ident.checked "state"
  let root ← Ident.checked "root"
  let title ← Ident.checked "title"
  let titleText ← Ident.checked "titleText"
  let form ← Ident.checked "form"
  let nameLabel ← Ident.checked "nameLabel"
  let nameLabelText ← Ident.checked "nameLabelText"
  let nameInput ← Ident.checked "nameInput"
  let nameId ← Ident.checked "nameId"
  let nameError ← Ident.checked "nameError"
  let nameErrorText ← Ident.checked "nameErrorText"
  let nameErrorId ← Ident.checked "nameErrorId"
  let ageLabel ← Ident.checked "ageLabel"
  let ageLabelText ← Ident.checked "ageLabelText"
  let ageInput ← Ident.checked "ageInput"
  let ageId ← Ident.checked "ageId"
  let ageError ← Ident.checked "ageError"
  let ageErrorText ← Ident.checked "ageErrorText"
  let ageErrorId ← Ident.checked "ageErrorId"
  let termsLabel ← Ident.checked "termsLabel"
  let termsLabelText ← Ident.checked "termsLabelText"
  let termsInput ← Ident.checked "termsInput"
  let termsError ← Ident.checked "termsError"
  let termsErrorText ← Ident.checked "termsErrorText"
  let termsErrorId ← Ident.checked "termsErrorId"
  let submitButton ← Ident.checked "submitButton"
  let submitText ← Ident.checked "submitText"
  let statusNode ← Ident.checked "statusNode"
  let statusText ← Ident.checked "statusText"
  let metrics ← Ident.checked "metrics"
  let cache ← Ident.checked "cache"
  let context ← Ident.checked "context"
  let disposer ← Ident.checked "disposer"
  let offName ← Ident.checked "offName"
  let offAge ← Ident.checked "offAge"
  let offAgeChange ← Ident.checked "offAgeChange"
  let offAccepted ← Ident.checked "offAccepted"
  let offKey ← Ident.checked "offKey"
  let offFocus ← Ident.checked "offFocus"
  let offBlur ← Ident.checked "offBlur"
  let offSubmit ← Ident.checked "offSubmit"
  let body : Array Stmt := #[
    .const state (.array <| .ofList [
      .literal (.string checked.spec.initial.name),
      .literal (.string checked.spec.initial.age),
      .literal (.boolean checked.spec.initial.accepted)]),
    .const root (call runtime.createElement [.literal (.string "main")]),
    .expr <| call runtime.setAttribute [
      .ident root, .literal (.string "class"), .literal (.string "validated-form")],
    .const title (call runtime.createElement [.literal (.string "h1")]),
    .const titleText (call runtime.createText [.literal (.string checked.spec.name)]),
    .expr <| call runtime.append [.ident title, .ident titleText],
    .expr <| call runtime.append [.ident root, .ident title],
    .const form (call runtime.createElement [.literal (.string "form")]),
    .expr <| call runtime.append [.ident root, .ident form],
    .const nameId (call runtime.uniqueId [.literal (.string "lrx-name")]),
    .const nameErrorId (call runtime.uniqueId [.literal (.string "lrx-name-error")]),
    .const nameLabel (call runtime.createElement [.literal (.string "label")]),
    .expr <| call runtime.setAttribute [.ident nameLabel, .literal (.string "for"), .ident nameId],
    .const nameLabelText (call runtime.createText [.literal (.string "Name")]),
    .expr <| call runtime.append [.ident nameLabel, .ident nameLabelText],
    .expr <| call runtime.append [.ident form, .ident nameLabel],
    .const nameInput (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [.ident nameInput, .literal (.string "id"), .ident nameId],
    .expr <| call runtime.setAttribute [
      .ident nameInput, .literal (.string "aria-describedby"), .ident nameErrorId],
    .expr <| call runtime.setAttribute [
      .ident nameInput, .literal (.string "aria-invalid"),
      .literal (.string (if initial.nameError.isEmpty then "false" else "true"))],
    .expr <| setProperty runtime (.ident nameInput) checked.nameControl.property
      (.literal (.string checked.spec.initial.name)),
    .expr <| call runtime.append [.ident form, .ident nameInput],
    .const nameError (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident nameError, .literal (.string "id"), .ident nameErrorId],
    .expr <| call runtime.setAttribute [
      .ident nameError, .literal (.string "aria-live"), .literal (.string "polite")],
    .const nameErrorText (call runtime.createText [.literal (.string initial.nameError)]),
    .expr <| call runtime.append [.ident nameError, .ident nameErrorText],
    .expr <| call runtime.append [.ident form, .ident nameError],
    .const ageId (call runtime.uniqueId [.literal (.string "lrx-age")]),
    .const ageErrorId (call runtime.uniqueId [.literal (.string "lrx-age-error")]),
    .const ageLabel (call runtime.createElement [.literal (.string "label")]),
    .expr <| call runtime.setAttribute [.ident ageLabel, .literal (.string "for"), .ident ageId],
    .const ageLabelText (call runtime.createText [.literal (.string "Age")]),
    .expr <| call runtime.append [.ident ageLabel, .ident ageLabelText],
    .expr <| call runtime.append [.ident form, .ident ageLabel],
    .const ageInput (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [.ident ageInput, .literal (.string "id"), .ident ageId],
    .expr <| call runtime.setAttribute [
      .ident ageInput, .literal (.string "inputmode"), .literal (.string "numeric")],
    .expr <| call runtime.setAttribute [
      .ident ageInput, .literal (.string "aria-describedby"), .ident ageErrorId],
    .expr <| call runtime.setAttribute [
      .ident ageInput, .literal (.string "aria-invalid"),
      .literal (.string (if initial.ageError.isEmpty then "false" else "true"))],
    .expr <| setProperty runtime (.ident ageInput) checked.ageControl.property
      (.literal (.string checked.spec.initial.age)),
    .expr <| call runtime.append [.ident form, .ident ageInput],
    .const ageError (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [.ident ageError, .literal (.string "id"), .ident ageErrorId],
    .expr <| call runtime.setAttribute [
      .ident ageError, .literal (.string "aria-live"), .literal (.string "polite")],
    .const ageErrorText (call runtime.createText [.literal (.string initial.ageError)]),
    .expr <| call runtime.append [.ident ageError, .ident ageErrorText],
    .expr <| call runtime.append [.ident form, .ident ageError],
    .const termsErrorId (call runtime.uniqueId [.literal (.string "lrx-terms-error")]),
    .const termsLabel (call runtime.createElement [.literal (.string "label")]),
    .const termsInput (call runtime.createElement [.literal (.string "input")]),
    .expr <| call runtime.setAttribute [
      .ident termsInput, .literal (.string "type"), .literal (.string "checkbox")],
    .expr <| call runtime.setAttribute [
      .ident termsInput, .literal (.string "aria-describedby"), .ident termsErrorId],
    .expr <| call runtime.setAttribute [
      .ident termsInput, .literal (.string "aria-invalid"),
      .literal (.string (if initial.termsError.isEmpty then "false" else "true"))],
    .expr <| setProperty runtime (.ident termsInput) checked.acceptedControl.property
      (.literal (.boolean checked.spec.initial.accepted)),
    .expr <| call runtime.append [.ident termsLabel, .ident termsInput],
    .const termsLabelText (call runtime.createText [.literal (.string " Accept terms")]),
    .expr <| call runtime.append [.ident termsLabel, .ident termsLabelText],
    .expr <| call runtime.append [.ident form, .ident termsLabel],
    .const termsError (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident termsError, .literal (.string "id"), .ident termsErrorId],
    .expr <| call runtime.setAttribute [
      .ident termsError, .literal (.string "aria-live"), .literal (.string "polite")],
    .const termsErrorText (call runtime.createText [.literal (.string initial.termsError)]),
    .expr <| call runtime.append [.ident termsError, .ident termsErrorText],
    .expr <| call runtime.append [.ident form, .ident termsError],
    .const submitButton (call runtime.createElement [.literal (.string "button")]),
    .expr <| call runtime.setAttribute [
      .ident submitButton, .literal (.string "type"), .literal (.string "submit")],
    .expr <| setProperty runtime (.ident submitButton) DomProperty.disabled
      (.literal (.boolean initial.disabled)),
    .const submitText (call runtime.createText [.literal (.string "Submit")]),
    .expr <| call runtime.append [.ident submitButton, .ident submitText],
    .expr <| call runtime.append [.ident form, .ident submitButton],
    .const statusNode (call runtime.createElement [.literal (.string "p")]),
    .expr <| call runtime.setAttribute [
      .ident statusNode, .literal (.string "role"), .literal (.string "status")],
    .const statusText (call runtime.createText [.literal (.string "")]),
    .expr <| call runtime.append [.ident statusNode, .ident statusText],
    .expr <| call runtime.append [.ident root, .ident statusNode],
    .const metrics (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil]),
    .const cache (.array <| .ofList [
      .literal (.string initial.nameError), .literal (.string initial.ageError),
      .literal (.string initial.termsError), .literal (.boolean initial.disabled),
      .literal (.string "")]),
    .const context (.array <| .ofList [
      .ident nameInput, .ident ageInput, .ident termsInput,
      .ident nameErrorText, .ident ageErrorText, .ident termsErrorText,
      .ident submitButton, .ident statusText, .ident metrics, .ident cache]),
    .expr <| call runtime.append [.ident target, .ident root],
    .const offName <| FormDom.listen (listenerRuntime runtime) checked.nameControl.event
      (.ident nameInput) (.ident state) (.ident context) editName.name,
    .const offAge <| FormDom.listen (listenerRuntime runtime) checked.ageControl.event
      (.ident ageInput) (.ident state) (.ident context) editAge.name,
    .const offAgeChange <| FormDom.listen (listenerRuntime runtime) checked.ageChangeBinding.event
      (.ident ageInput) (.ident state) (.ident context) recordAgeChange.name,
    .const offAccepted <| FormDom.listen (listenerRuntime runtime) checked.acceptedControl.event
      (.ident termsInput) (.ident state) (.ident context) editAccepted.name,
    .const offKey <| FormDom.listen (listenerRuntime runtime) checked.keyBinding.event
      (.ident nameInput) (.ident state) (.ident context) recordKey.name,
    .const offFocus <| FormDom.listen (listenerRuntime runtime) checked.focusBinding.event
      (.ident nameInput) (.ident state) (.ident context) focusField.name,
    .const offBlur <| FormDom.listen (listenerRuntime runtime) checked.blurBinding.event
      (.ident nameInput) (.ident state) (.ident context) blurField.name,
    .const offSubmit <| FormDom.listen (listenerRuntime runtime) checked.submitBinding.event
      (.ident form) (.ident state) (.ident context) submitValidated.name,
    .const disposer <| call runtime.makeDisposer [
      .ident root, .array <| .ofList <| [offName, offAge, offAgeChange, offAccepted, offKey,
        offFocus, offBlur, offSubmit].map Expr.ident,
      .ident metrics],
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
      declarations := #[.function validator, .function render, .function editName,
        .function editAge, .function editAccepted, .function recordAgeChange, .function recordKey,
        .function focusField, .function blurField, .function submitValidated,
        .function { name := mount, params := #[target], body }]
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.ValidatedForm
