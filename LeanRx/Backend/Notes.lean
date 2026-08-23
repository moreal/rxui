import LeanRx.Backend.FormDom
import LeanRx.Backend.Manifest
import LeanRx.Notes.Model

namespace LeanRx.Backend.Notes

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
  setProperty : Ident
  listenValue : Ident
  makeDisposer : Ident
  createEffectRuntime : Ident
  makeEffectDisposer : Ident

private def runtimeNames : Except Js.Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    append := ← Ident.checked "append"
    setText := ← Ident.checked "setText"
    setProperty := ← Ident.checked "setProperty"
    listenValue := ← Ident.checked "listenValue"
    makeDisposer := ← Ident.checked "makeDisposer"
    createEffectRuntime := ← Ident.checked "createEffectRuntime"
    makeEffectDisposer := ← Ident.checked "makeEffectDisposer"
  }

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))
private def indexAt (target : Expr) (index : Nat) : Expr := .index target (uint index)
private def arrayAt (name : Ident) (index : Nat) : Expr := indexAt (.ident name) index
private def property (target : Expr) (name : String) : Expr :=
  .index target (.literal (.string name))
private def call (name : Ident) (args : List Expr) : Expr :=
  .call (.ident name) (.ofList args)
private def callExpr (callee : Expr) (args : List Expr) : Expr := .call callee (.ofList args)
private def method (target : Expr) (name : String) (args : List Expr) : Expr :=
  callExpr (property target name) args

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def assignState (state metrics : Ident) (index : Nat) (value : Expr) : List Stmt := [
  .assign (.index (.ident state) (uint index)) value,
  incrementAt metrics 2
]

private def trace (metrics : Ident) (message : String) : Stmt :=
  .expr <| method (arrayAt metrics 7) "push" [.literal (.string message)]

private def stateAt (state : Ident) (index : Nat) : Expr := arrayAt state index
private def contextAt (context : Ident) (index : Nat) : Expr := arrayAt context index
private def equals (left right : Expr) : Expr := .binary .eq left right
private def both (left right : Expr) : Expr := .binary .and left right

private def renderFunction (runtime : RuntimeNames) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_notesRender"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let metrics ← Ident.checked "metrics"
  let code ← Ident.checked "persistenceCode"
  let restoreCode ← Ident.checked "restoreCode"
  let restoreError ← Ident.checked "restoreError"
  let saveError ← Ident.checked "saveError"
  let status ← Ident.checked "statusValue"
  let fallback :=
    .conditional (equals (.ident code) (uint 1)) (.literal (.string "Waiting to save")) <|
    .conditional (equals (.ident code) (uint 2)) (.literal (.string "Saving")) <|
    .conditional (equals (.ident code) (uint 3)) (.literal (.string "Saved")) <|
    .conditional (equals (.ident code) (uint 4)) (.ident saveError) <|
    .literal (.string "Not saved")
  pure {
    name
    params := #[state, context]
    body := #[
      .const metrics (contextAt context 3),
      .const code (stateAt state 2),
      .const restoreCode (stateAt state 6),
      .const restoreError (stateAt state 8),
      .const saveError (stateAt state 9),
      .const status (.conditional (equals (.ident restoreCode) (uint 3))
        (.ident restoreError) fallback),
      incrementAt metrics 5,
      .expr <| call runtime.setText [contextAt context 1, .ident status],
      incrementAt metrics 6,
      .return (.literal .null)
    ]
  }

private def restoredFunction (runtime : RuntimeNames) (render : Ident) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_notesRestored"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let handle ← Ident.checked "handle"
  let result ← Ident.checked "result"
  let metrics ← Ident.checked "metrics"
  let value ← Ident.checked "storageValue"
  let condition := both (equals (stateAt state 6) (uint 1))
    (equals (stateAt state 7) (.ident handle))
  pure {
    name
    params := #[state, context, handle, result]
    body := #[
      .const metrics (contextAt context 3),
      .ifThen condition <| .ofList <|
        [.ifThen (property (.ident result) "ok") <| .ofList <|
          assignState state metrics 6 (uint 2) ++
          assignState state metrics 8 (.literal (.string "")) ++ [
          .const value (property (.ident result) "value"),
          .ifThen (equals (property (.ident value) "kind") (.literal (.string "found"))) <|
            .ofList <| assignState state metrics 0 (property (.ident value) "value") ++ [
              .expr <| call runtime.setProperty [
                contextAt context 0, .literal (.string "value"), stateAt state 0],
              incrementAt metrics 6
            ]
        ],
        .ifThen (.unary .not <| property (.ident result) "ok") <| .ofList <|
          assignState state metrics 6 (uint 3) ++
          assignState state metrics 8 (.binary .add (.literal (.string "Restore failed: "))
            (property (property (.ident result) "error") "message")) ++ [
          trace metrics "command:storageGet:failed"
        ],
        incrementAt metrics 1,
        .expr <| call render [.ident state, .ident context]
      ],
      .return (.literal .null)
    ]
  }

private def storedFunction (render : Ident) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_notesStored"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let handle ← Ident.checked "handle"
  let result ← Ident.checked "result"
  let metrics ← Ident.checked "metrics"
  let condition := both (equals (stateAt state 2) (uint 2))
    (equals (stateAt state 3) (.ident handle))
  pure {
    name
    params := #[state, context, handle, result]
    body := #[
      .const metrics (contextAt context 3),
      .ifThen condition <| .ofList <| [
        .ifThen (property (.ident result) "ok") <| .ofList <|
          assignState state metrics 2 (uint 3) ++
          assignState state metrics 9 (.literal (.string "")) ++ [
          trace metrics "command:storageSet:succeeded"
        ],
        .ifThen (.unary .not <| property (.ident result) "ok") <| .ofList <|
          assignState state metrics 2 (uint 4) ++
          assignState state metrics 9 (.binary .add (.literal (.string "Save failed: "))
            (property (property (.ident result) "error") "message")) ++ [
          trace metrics "command:storageSet:failed"
        ],
        incrementAt metrics 1,
        .expr <| call render [.ident state, .ident context]
      ],
      .return (.literal .null)
    ]
  }

private def debounceFunction (render stored : Ident) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_notesDebounce"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let handle ← Ident.checked "handle"
  let result ← Ident.checked "result"
  let metrics ← Ident.checked "metrics"
  let saveHandle ← Ident.checked "saveHandle"
  let effects ← Ident.checked "effects"
  let condition := both (equals (stateAt state 2) (uint 1))
    (equals (stateAt state 3) (.ident handle))
  pure {
    name
    params := #[state, context, handle, result]
    body := #[
      .const metrics (contextAt context 3),
      .const effects (contextAt context 2),
      .ifThen condition <| .ofList <| [
        .const saveHandle (stateAt state 4)
      ] ++ assignState state metrics 4 (.binary .add (.ident saveHandle) (uint 1)) ++
        assignState state metrics 2 (uint 2) ++
        assignState state metrics 3 (.ident saveHandle) ++ [
        incrementAt metrics 1,
        trace metrics "command:timeout:delivered",
        .expr <| call render [.ident state, .ident context],
        .expr <| method (.ident effects) "storageSet" [
          .ident saveHandle, .literal (.string "leanrx.notes"), stateAt state 0,
          .ident state, .ident context, .ident stored]
      ],
      .return (.literal .null)
    ]
  }

private def inputFunction (render debounce : Ident) : Except Js.Error Function := do
  let name ← Ident.checked "$lrx_notesInput"
  let state ← Ident.checked "state"
  let context ← Ident.checked "context"
  let value ← Ident.checked "value"
  let metrics ← Ident.checked "metrics"
  let effects ← Ident.checked "effects"
  let handle ← Ident.checked "debounceHandle"
  let hadRestore ← Ident.checked "hadRestore"
  let restoreHandle ← Ident.checked "restoreHandle"
  let hadPersistence ← Ident.checked "hadPersistence"
  let persistenceHandle ← Ident.checked "persistenceHandle"
  let body : List Stmt := [
    .const metrics (contextAt context 3),
    .const effects (contextAt context 2),
    .ifThen (stateAt state 5) <| .ofList [.return (.literal .null)],
    .const hadRestore (equals (stateAt state 6) (uint 1)),
    .const restoreHandle (stateAt state 7),
    .const hadPersistence (.binary .or (equals (stateAt state 2) (uint 1))
      (equals (stateAt state 2) (uint 2))),
    .const persistenceHandle (stateAt state 3),
    .const handle (stateAt state 4)
  ] ++ [
    .ifThen (.ident hadRestore) <| .ofList <| assignState state metrics 6 (uint 4)
  ] ++ assignState state metrics 0 (.ident value) ++
    assignState state metrics 4 (.binary .add (.ident handle) (uint 1)) ++
    assignState state metrics 2 (uint 1) ++
    assignState state metrics 3 (.ident handle) ++
    assignState state metrics 9 (.literal (.string "")) ++ [
    incrementAt metrics 1,
    trace metrics "event:edit",
    .expr <| call render [.ident state, .ident context],
    .ifThen (.ident hadRestore) <| .ofList [
      .expr <| method (.ident effects) "cancel" [.ident restoreHandle],
      trace metrics "command:storageGet:cancel"
    ],
    .ifThen (.ident hadPersistence) <| .ofList [
      .expr <| method (.ident effects) "cancel" [.ident persistenceHandle],
      trace metrics "command:persistence:cancel"
    ],
    .expr <| method (.ident effects) "timeout" [
      .ident handle, uint 250, .ident state, .ident context, .ident debounce],
    .return (.literal .null)
  ]
  pure {
    name
    params := #[state, context, value]
    body := body.toArray
  }

private def mountFunction (runtime : RuntimeNames) (componentName : String)
    (restored input : Ident) : Except Js.Error Function := do
  let name ← Ident.checked "mount"
  let target ← Ident.checked "target"
  let adapters ← Ident.checked "adapters"
  let root ← Ident.checked "root"
  let heading ← Ident.checked "heading"
  let headingText ← Ident.checked "headingText"
  let textarea ← Ident.checked "noteInput"
  let status ← Ident.checked "status"
  let statusText ← Ident.checked "statusText"
  let metrics ← Ident.checked "metrics"
  let state ← Ident.checked "state"
  let effects ← Ident.checked "effects"
  let context ← Ident.checked "context"
  let offInput ← Ident.checked "offInput"
  let baseDisposer ← Ident.checked "baseDisposer"
  let disposer ← Ident.checked "disposer"
  pure {
    name
    params := #[target, adapters]
    body := #[
      .const root (call runtime.createElement [.literal (.string "main")]),
      .expr <| call runtime.setAttribute [
        .ident root, .literal (.string "class"), .literal (.string "leanrx-notes")],
      .const heading (call runtime.createElement [.literal (.string "h1")]),
      .const headingText (call runtime.createText [.literal (.string componentName)]),
      .expr <| call runtime.append [.ident heading, .ident headingText],
      .expr <| call runtime.append [.ident root, .ident heading],
      .const textarea (call runtime.createElement [.literal (.string "textarea")]),
      .expr <| call runtime.setAttribute [
        .ident textarea, .literal (.string "aria-label"), .literal (.string "Note")],
      .expr <| call runtime.append [.ident root, .ident textarea],
      .const status (call runtime.createElement [.literal (.string "p")]),
      .expr <| call runtime.setAttribute [
        .ident status, .literal (.string "role"), .literal (.string "status")],
      .expr <| call runtime.setAttribute [
        .ident status, .literal (.string "aria-live"), .literal (.string "polite")],
      .const statusText (call runtime.createText [.literal (.string "Not saved")]),
      .expr <| call runtime.append [.ident status, .ident statusText],
      .expr <| call runtime.append [.ident root, .ident status],
      .const metrics (.array <| .ofList [
        uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil,
        uint 0, uint 0]),
      .const state (.array <| .ofList [
        .literal (.string ""), uint 0, uint 0, uint 0, uint 1,
        .literal (.boolean false), uint 1, uint 0, .literal (.string ""),
        .literal (.string "")]),
      .const effects (call runtime.createEffectRuntime [.ident metrics, .ident adapters]),
      .const context (.array <| .ofList [
        .ident textarea, .ident statusText, .ident effects, .ident metrics]),
      .expr <| call runtime.append [.ident target, .ident root],
      .const offInput (call runtime.listenValue [
        .ident textarea, .literal (.string "input"), .ident state, .ident context,
        .ident input]),
      .const baseDisposer (call runtime.makeDisposer [
        .ident root, .array (.ofList [.ident offInput]), .ident metrics]),
      .const disposer (call runtime.makeEffectDisposer [
        .ident baseDisposer, .ident state, uint 5, .ident effects]),
      .expr <| method (.ident effects) "storageGet" [
        uint 0, .literal (.string "leanrx.notes"), .ident state, .ident context,
        .ident restored],
      .return (.ident disposer)
    ]
  }

def emit (moduleName : String) (checked : LeanRx.Notes.Spec.Checked) : Except Js.Error Emitted := do
  let runtime ← runtimeNames
  let render ← renderFunction runtime
  let restored ← restoredFunction runtime render.name
  let stored ← storedFunction render.name
  let debounce ← debounceFunction render.name stored.name
  let input ← inputFunction render.name debounce.name
  let mount ← mountFunction runtime checked.spec.name restored.name input.name
  let module : Module := {
    imports := #[
      { source := "./leanrx_dom.mjs", names := #[
          (runtime.createElement, runtime.createElement),
          (runtime.createText, runtime.createText),
          (runtime.setAttribute, runtime.setAttribute),
          (runtime.append, runtime.append),
          (runtime.setText, runtime.setText),
          (runtime.setProperty, runtime.setProperty),
          (runtime.makeDisposer, runtime.makeDisposer)
        ] },
      { source := "./leanrx_form_events.mjs", names := #[
          (runtime.listenValue, runtime.listenValue)
        ] },
      { source := "./leanrx_effects.mjs", names := #[
          (runtime.createEffectRuntime, runtime.createEffectRuntime),
          (runtime.makeEffectDisposer, runtime.makeEffectDisposer)
        ] }
    ]
    declarations := #[.function render, .function restored, .function stored,
      .function debounce, .function input, .function mount]
    exports := #[{ localName := mount.name, exportName := mount.name }]
  }
  module.validate
  pure ⟨module, {
    compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := "notes:text->status"
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := #[.string]
    sourceCount := 1
    derivedCount := 0
    textSinkCount := 1
    eventCount := 1
    hostImports := #["./leanrx_dom.mjs", "./leanrx_form_events.mjs", "./leanrx_effects.mjs"]
    features := #["commands", "timer", "storage", "owned-cancellation", "instrumentation"]
  }⟩

end LeanRx.Backend.Notes
