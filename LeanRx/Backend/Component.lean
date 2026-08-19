import LeanRx.Backend.Manifest
import LeanRx.Component.Model
import LeanRx.Graph.Serialize
import LeanRx.Lower.RxExpr

namespace LeanRx.Backend.Component

open LeanRx.Js

structure Emitted where
  module : Module
  manifest : ComponentManifest
deriving Repr, BEq

private structure EvalState where
  declarations : List Decl := []
  bindings : List (String × Ident) := []

private def mergeDecl (state : EvalState) (declaration : Decl) : Except Error EvalState :=
  match state.declarations.find? (fun existing => existing.name == declaration.name) with
  | none => pure { state with declarations := state.declarations ++ [declaration] }
  | some existing =>
      if existing == declaration then pure state
      else .error {
        code := "LRX-BE-021"
        message := s!"component scalar evaluators collide on {declaration.name.raw}"
      }

private def mergeDecls : EvalState → List Decl → Except Error EvalState
  | state, [] => pure state
  | state, declaration :: rest => do
      mergeDecls (← mergeDecl state declaration) rest

private def addEvaluator (inputSpecs : Array Scalar.InputSpec) (key requested : String)
    (value : ReactiveIR.Expr α) (state : EvalState) : Except Error EvalState := do
  let emitted ← Scalar.moduleFor requested inputSpecs value
  let state ← mergeDecls state emitted.module.declarations.toList
  pure { state with bindings := state.bindings ++ [(key, emitted.exportName)] }

private def evaluator (state : EvalState) (key : String) : Except Error Ident :=
  match state.bindings.find? (·.1 == key) with
  | some binding => pure binding.2
  | none => .error {
      code := "LRX-BE-022"
      message := s!"component lowering is missing evaluator {key}"
    }

private def inputSpecs (values : Array (ValueSpec Γ)) : Array Scalar.InputSpec :=
  values.map fun value => { name := value.name, valueType := value.valueType }

private def compileValues (inputs : Array Scalar.InputSpec) :
    List (ValueSpec Γ) → EvalState → Except Error EvalState
  | [], state => pure state
  | .source .. :: rest, state => compileValues inputs rest state
  | .derived _ _ field value _ :: rest, state => do
      let state ← addEvaluator inputs s!"value:{field.index}"
        s!"$lrx_derived_{field.index}" (Lower.rxExpr value) state
      compileValues inputs rest state

private def compileSinks (inputs : Array Scalar.InputSpec) :
    List (TextSink Γ) → Nat → EvalState → Except Error EvalState
  | [], _, state => pure state
  | sink :: rest, index, state => do
      let state ← addEvaluator inputs s!"sink:{index}" s!"$lrx_sink_{index}"
        (Lower.rxExpr sink.value) state
      compileSinks inputs rest (index + 1) state

private def compileUpdate (inputs : Array Scalar.InputSpec) (eventIndex : Nat) :
    Update Γ → Nat → EvalState → Except Error (Nat × EvalState)
  | .set _ value _, writeIndex, state => do
      let state ← addEvaluator inputs s!"event:{eventIndex}:write:{writeIndex}"
        s!"$lrx_event_{eventIndex}_write_{writeIndex}" (Lower.rxExpr value) state
      pure (writeIndex + 1, state)
  | .dispatch .., writeIndex, state => pure (writeIndex, state)
  | .sequence first second, writeIndex, state => do
      let (writeIndex, state) ← compileUpdate inputs eventIndex first writeIndex state
      compileUpdate inputs eventIndex second writeIndex state

private def compileEvents (inputs : Array Scalar.InputSpec) :
    List (EventSpec Γ) → Nat → EvalState → Except Error EvalState
  | [], _, state => pure state
  | event :: rest, index, state => do
      let (_, state) ← compileUpdate inputs index event.update 0 state
      compileEvents inputs rest (index + 1) state

private def uint (value : Nat) : Expr := .literal (.number (UInt32.ofNat value))

private def stateAt (state : Ident) (index : Nat) : Expr :=
  .index (.ident state) (uint index)

private def refsAt (refs : Ident) (index : Nat) : Expr :=
  .index (.ident refs) (uint index)

private def call (name : Ident) (args : List Expr) : Expr :=
  .call (.ident name) (.ofList args)

private def evaluatorCall (name state : Ident) (valueCount : Nat) : Expr :=
  call name <| (List.range valueCount).map (stateAt state)

private def literal : {α : Type} → ScalarLiteral α → Js.Literal
  | _, .bool value => .boolean value
  | _, .string value => .string value
  | _, .int value => .bigint value
  | _, .nat value => .bigint (Int.ofNat value)

private def initialValues : List (ValueSpec Γ) → List Expr
  | [] => []
  | .source _ _ _ initial _ :: rest => .literal (literal initial) :: initialValues rest
  | .derived .. :: rest => .literal .null :: initialValues rest

private def graphNodeAt? (checked : CheckedComponent Γ) (index : Nat) : Except Error Node :=
  match checked.graph.graph.nodes[index]? with
  | some node => pure node
  | none => .error {
      code := "LRX-BE-023"
      message := s!"component schedule references missing value {index}"
    }

private def nextName (index : Nat) : Except Error Ident :=
  Ident.checked s!"next_{index}"

private def sinkNextName (index : Nat) : Except Error Ident :=
  Ident.checked s!"sink_next_{index}"

private def sinkChangedName (index : Nat) : Except Error Ident :=
  Ident.checked s!"sink_changed_{index}"

private def derivedOrder (checked : CheckedComponent Γ) : List Nat :=
  checked.graph.schedule.order.toList.filterMap fun id =>
    checked.graph.graph.nodes[id.value]?.bind fun node =>
      if node.kind == .derived then some id.value else none

private def txAt (tx : Ident) (index : Nat) : Expr :=
  .index (.ident tx) (uint index)

private def arrayAt (array : Ident) (index : Nat) : Expr :=
  .index (.ident array) (uint index)

private def incrementAt (array : Ident) (index : Nat) : Stmt :=
  .assign (.index (.ident array) (uint index))
    (.binary .add (arrayAt array index) (uint 1))

private def pushTrace (tx : Ident) (message : String) : Stmt :=
  .expr <| .call
    (.index (txAt tx 7) (.literal (.string "push")))
    (.ofList [.literal (.string message)])

private def eventName (index : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_event_{index}"

private def updateStatements (evaluators : EvalState) (context state tx : Ident)
    (eventNames : List String) (valueCount eventIndex : Nat) :
    Update Γ → Nat → Except Error (Nat × List Stmt)
  | .set field _ _, writeIndex => do
      let evaluator ← evaluator evaluators s!"event:{eventIndex}:write:{writeIndex}"
      pure (writeIndex + 1, [
        .assign (.index (.ident state) (uint field.index))
          (evaluatorCall evaluator state valueCount),
        incrementAt tx 2,
        pushTrace tx s!"source:{field.name}:write"
      ])
  | .dispatch target _, writeIndex => do
      let targetIndex ← match eventNames.idxOf? target with
        | some index => pure index
        | none => .error {
            code := "LRX-BE-027"
            message := s!"checked nested event disappeared: {target}"
          }
      pure (writeIndex, [.expr <| call (← eventName targetIndex) [
        .ident context, .literal .null
      ]])
  | .sequence first second, writeIndex => do
      let (writeIndex, first) ← updateStatements evaluators context state tx eventNames
        valueCount eventIndex first writeIndex
      let (writeIndex, second) ← updateStatements evaluators context state tx eventNames
        valueCount eventIndex second writeIndex
      pure (writeIndex, first ++ second)

private def anyChanged (changed : Ident) (deps : List Nat) : Expr :=
  let values := deps.map (arrayAt changed)
  match values with
    | [] => .literal (.boolean false)
    | head :: tail => tail.foldl (fun acc value => .binary .or acc value) head

private def eventFunction (checked : CheckedComponent Γ) (evaluators : EvalState)
    (setText : Ident) (eventNames : List String) (event : EventSpec Γ) (eventIndex : Nat) :
    Except Error Function := do
  let context ← Ident.checked "context"
  let ignored ← Ident.checked "ignored"
  let state ← Ident.checked "state"
  let refs ← Ident.checked "refs"
  let tx ← Ident.checked "tx"
  let oldSources ← Ident.checked "oldSources"
  let changed ← Ident.checked "changed"
  let sinkCache ← Ident.checked "sinkCache"
  let valueCount := checked.spec.values.size
  let mut body : List Stmt := [
    .const state (arrayAt context 0),
    .const refs (arrayAt context 1),
    .const tx (arrayAt context 2),
    .const oldSources (arrayAt context 3),
    .const changed (arrayAt context 4),
    .const sinkCache (arrayAt context 5)
  ]
  let mut beginBody : List Stmt := [pushTrace tx "transaction:begin"]
  for id in List.range valueCount do
    beginBody := beginBody ++ [
      .assign (.index (.ident changed) (uint id)) (.literal (.boolean false))
    ]
  for sourceId in List.range checked.sourceCount do
    beginBody := beginBody ++ [
      .assign (.index (.ident oldSources) (uint sourceId)) (stateAt state sourceId)
    ]
  body := body ++ [
    .ifThen (.binary .eq (txAt tx 0) (uint 0)) (.ofList beginBody),
    incrementAt tx 0,
    pushTrace tx s!"event:{event.name}"
  ]
  let (_, writes) ← updateStatements evaluators context state tx eventNames
    valueCount eventIndex event.update 0
  body := body ++ writes ++ [
    .assign (.index (.ident tx) (uint 0)) (.binary .sub (txAt tx 0) (uint 1))
  ]
  let mut commitBody : List Stmt := []
  for sourceId in List.range checked.sourceCount do
    let source ← graphNodeAt? checked sourceId
    commitBody := commitBody ++ [
      .assign (.index (.ident changed) (uint sourceId)) <|
        .unary .not (.binary .eq (arrayAt oldSources sourceId) (stateAt state sourceId)),
      .ifThen (arrayAt changed sourceId) <| .ofList [
        pushTrace tx s!"source:{source.name}:changed"
      ]
    ]
  for id in derivedOrder checked do
    let value ← graphNodeAt? checked id
    let evalName ← evaluator evaluators s!"value:{id}"
    let next ← nextName id
    commitBody := commitBody ++ [
      .assign (.index (.ident changed) (uint id)) (.literal (.boolean false)),
      .ifThen (anyChanged changed (value.deps.toList.map (·.value))) <| .ofList [
        incrementAt tx 3,
        pushTrace tx s!"derived:{value.name}:evaluated",
        .const next (evaluatorCall evalName state valueCount),
        .assign (.index (.ident changed) (uint id)) <|
          .unary .not (.binary .eq (stateAt state id) (.ident next)),
        .ifThen (arrayAt changed id) <| .ofList [
          incrementAt tx 4,
          pushTrace tx s!"derived:{value.name}:changed"
        ],
        .assign (.index (.ident state) (uint id)) (.ident next)
      ]
    ]
  for (sink, sinkIndex) in checked.view.textSinks.zipIdx do
    let evalName ← evaluator evaluators s!"sink:{sinkIndex}"
    let next ← sinkNextName sinkIndex
    let differs ← sinkChangedName sinkIndex
    commitBody := commitBody ++ [.ifThen (anyChanged changed sink.value.dependencies.ids) <|
      .ofList [
      incrementAt tx 5,
      pushTrace tx s!"sink:{sink.name}:evaluated",
      .const next (evaluatorCall evalName state valueCount),
      .const differs <| .unary .not <|
        .binary .eq (arrayAt sinkCache sinkIndex) (.ident next),
      .ifThen (.ident differs) <| .ofList [
        .assign (.index (.ident sinkCache) (uint sinkIndex)) (.ident next),
        .expr <| call setText [refsAt refs sinkIndex, .ident next],
        incrementAt tx 6,
        pushTrace tx s!"dom:{sink.name}:write"
      ]
    ]]
  commitBody := commitBody ++ [
    incrementAt tx 1,
    pushTrace tx "transaction:commit"
  ]
  body := body ++ [
    .ifThen (.binary .eq (txAt tx 0) (uint 0)) (.ofList commitBody),
    .return (.literal .null)
  ]
  pure {
    name := ← eventName eventIndex
    params := #[context, ignored]
    body := body.toArray
  }

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

private structure DomBinding where
  path : List Nat
  name : Ident

private structure DomState where
  allocator : NameAllocator
  statements : List Stmt := []
  nodes : List DomBinding := []

private structure SinkBinding where
  path : List Nat
  index : Nat
  evaluator : Ident

private def appendStatement (state : DomState) (statement : Stmt) : DomState :=
  { state with statements := state.statements ++ [statement] }

private def addNode (state : DomState) (path : List Nat) (name : Ident) : DomState :=
  { state with nodes := state.nodes ++ [{ path, name }] }

private def sinkAt (sinks : List SinkBinding) (path : List Nat) : Except Error SinkBinding :=
  match sinks.find? (·.path == path) with
  | some sink => pure sink
  | none => .error { code := "LRX-BE-024", message := "dynamic text has no scalar sink" }

mutual
  private def mountNode (runtime : RuntimeNames) (stateName : Ident) (valueCount : Nat)
      (sinks : List SinkBinding) (path : List Nat) :
      MountNode → DomState → Except Error (Ident × DomState)
    | .element tag attrs children, state => do
        let (name, allocator) ← state.allocator.allocate s!"node_{state.nodes.length}"
        let state := addNode { state with allocator } path name
        let state := appendStatement state <| .const name <|
          call runtime.createElement [.literal (.string tag.name)]
        let mut state := state
        for attr in attrs do
          state := appendStatement state <| .expr <| call runtime.setAttribute [
            .ident name, .literal (.string attr.name), .literal (.string attr.value)
          ]
        let finalState ← mountChildren runtime stateName valueCount sinks name path 0 children state
        pure (name, finalState)
    | .text value, state => do
        let (name, allocator) ← state.allocator.allocate s!"node_{state.nodes.length}"
        let state := addNode { state with allocator } path name
        pure (name, appendStatement state <| .const name <|
          call runtime.createText [.literal (.string value)])
    | .dynamicText, state => do
        let sink ← sinkAt sinks path
        let (name, allocator) ← state.allocator.allocate s!"text_{sink.index}"
        let state := addNode { state with allocator } path name
        pure (name, appendStatement state <| .const name <|
          call runtime.createText [evaluatorCall sink.evaluator stateName valueCount])

  private def mountChildren (runtime : RuntimeNames) (stateName : Ident) (valueCount : Nat)
      (sinks : List SinkBinding) (parent : Ident) (path : List Nat) (index : Nat) :
      MountChildren → DomState → Except Error DomState
    | .nil, state => pure state
    | .cons head tail, state => do
        let (child, state) ← mountNode runtime stateName valueCount sinks
          (path ++ [index]) head state
        let state := appendStatement state <| .expr <| call runtime.append [.ident parent, .ident child]
        mountChildren runtime stateName valueCount sinks parent path (index + 1) tail state
end

private def nodeAt (nodes : List DomBinding) (path : List Nat) : Except Error Ident :=
  match nodes.find? (·.path == path) with
  | some node => pure node.name
  | none => .error { code := "LRX-BE-025", message := "view binding path has no mounted node" }

private def manifest (moduleName : String) (checked : CheckedComponent Γ) : ComponentManifest :=
  let graph := checked.graph.toJson
  let hash := graph.toList.foldl
    (fun value char => (value * 16777619 + char.toNat) % 4294967296) 2166136261
  { compilerVersion := LeanRx.version
    leanToolchain := LeanRx.leanToolchain
    moduleName
    graphHash := toString hash
    runtimeAbi := LeanRx.runtimeAbi
    exports := #["mount"]
    stateSlots := checked.spec.values.map ValueSpec.valueType
    sourceCount := checked.sourceCount
    derivedCount := checked.spec.values.size - checked.sourceCount
    textSinkCount := checked.view.textSinks.length
    eventCount := checked.spec.events.size
    hostImports := #["./leanrx_dom.mjs", "./leanrx_host.mjs"]
    features := #["scalar", "events", "transactions", "instrumentation", "trace"] }

/-- Lower a checked explicit component to a validated direct-DOM ESM module. -/
def emit (moduleName : String) (checked : CheckedComponent Γ) : Except Error Emitted := do
  let runtime ← runtimeNames
  let inputs := inputSpecs checked.spec.values
  let evaluators ← compileEvents inputs checked.spec.events.toList 0 <|
    ← compileSinks inputs checked.view.textSinks 0 <|
    ← compileValues inputs checked.spec.values.toList {}
  let state ← Ident.checked "state"
  let refs ← Ident.checked "refs"
  let tx ← Ident.checked "tx"
  let oldSources ← Ident.checked "oldSources"
  let changed ← Ident.checked "changed"
  let sinkCache ← Ident.checked "sinkCache"
  let context ← Ident.checked "context"
  let disposer ← Ident.checked "disposer"
  let target ← Ident.checked "target"
  let valueCount := checked.spec.values.size
  let eventNames := checked.spec.events.toList.map (·.name)
  let eventFunctions ← checked.spec.events.toList.zipIdx.mapM fun (event, index) =>
    eventFunction checked evaluators runtime.setText eventNames event index
  let derivedInitial ← derivedOrder checked |>.mapM fun id => do
    pure (.assign (.index (.ident state) (uint id)) <|
      evaluatorCall (← evaluator evaluators s!"value:{id}") state valueCount)
  let sinkBindings ← checked.view.textSinks.zipIdx.mapM fun (sink, index) => do
    pure { path := sink.path, index, evaluator := ← evaluator evaluators s!"sink:{index}" }
  let initialDom : DomState := { allocator := { used := [
    "state", "refs", "tx", "oldSources", "changed", "sinkCache", "context",
    "disposer", "target"
  ] } }
  let (root, dom) ← mountNode runtime state valueCount sinkBindings [] checked.view.template initialDom
  let sinkRefs ← checked.view.textSinks.mapM fun sink => do
    pure (.ident (← nodeAt dom.nodes sink.path))
  let sinkInitialValues ← sinkBindings.mapM fun sink =>
    pure (evaluatorCall sink.evaluator state valueCount)
  let mut mountBody : List Stmt := [
    .const state (.array <| .ofList (initialValues checked.spec.values.toList))
  ] ++ derivedInitial ++ dom.statements ++ [
    .const refs (.array <| .ofList sinkRefs),
    .const sinkCache (.array <| .ofList sinkInitialValues),
    .const tx (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil
    ]),
    .const oldSources (.array <| .ofList <|
      List.replicate checked.sourceCount (.literal .null)),
    .const changed (.array <| .ofList <|
      List.replicate valueCount (.literal (.boolean false))),
    .const context (.array <| .ofList [
      .ident state, .ident refs, .ident tx, .ident oldSources, .ident changed,
      .ident sinkCache
    ]),
    .expr <| call runtime.append [.ident target, .ident root]
  ]
  let mut disposers : List Expr := []
  for (mounted, index) in checked.view.events.zipIdx do
    let eventIndex ← match eventNames.idxOf? mounted.binding.eventName with
      | some value => pure value
      | none => .error { code := "LRX-BE-026", message := "checked event binding disappeared" }
    let handler ← eventName eventIndex
    let off ← Ident.checked s!"off_{index}"
    let node ← nodeAt dom.nodes mounted.path
    mountBody := mountBody ++ [.const off <| call runtime.listen [
      .ident node, .literal (.string mounted.binding.kind.name), .ident context,
      .literal .null, .ident handler
    ]]
    disposers := disposers ++ [.ident off]
  mountBody := mountBody ++ [
    .const disposer <| call runtime.makeDisposer [
      .ident root, .array (.ofList disposers), .ident tx
    ],
    .return (.ident disposer)
  ]
  let mount ← Ident.checked "mount"
  let module : Module :=
    { globals := #[← Ident.checked "String"]
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
      declarations := (evaluators.declarations ++ eventFunctions.map Decl.function ++ [
        Decl.function { name := mount, params := #[target], body := mountBody.toArray }
      ]).toArray
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Component
