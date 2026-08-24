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

private def compileProps (inputs : Array Scalar.InputSpec) :
    List (MountedProp Γ) → Nat → EvalState → Except Error EvalState
  | [], _, state => pure state
  | prop :: rest, index, state => do
      let state ← match prop.binding with
        | .value expr _ =>
            addEvaluator inputs s!"prop:{index}" s!"$lrx_prop_{index}"
              (Lower.rxExpr expr) state
        | .checked expr _ =>
            addEvaluator inputs s!"prop:{index}" s!"$lrx_prop_{index}"
              (Lower.rxExpr expr) state
      compileProps inputs rest (index + 1) state

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

private structure RuntimeNames where
  createElement : Ident
  createText : Ident
  setAttribute : Ident
  setProperty : Ident
  append : Ident
  listen : Ident
  setText : Ident
  makeDisposer : Ident
  listenValue : Ident
  listenKey : Ident
  listenChecked : Ident
  listenSubmit : Ident

private def runtimeNames : Except Error RuntimeNames := do
  pure {
    createElement := ← Ident.checked "createElement"
    createText := ← Ident.checked "createText"
    setAttribute := ← Ident.checked "setAttribute"
    setProperty := ← Ident.checked "setProperty"
    append := ← Ident.checked "append"
    listen := ← Ident.checked "listen"
    setText := ← Ident.checked "setText"
    makeDisposer := ← Ident.checked "makeDisposer"
    listenValue := ← Ident.checked "listenValue"
    listenKey := ← Ident.checked "listenKey"
    listenChecked := ← Ident.checked "listenChecked"
    listenSubmit := ← Ident.checked "listenSubmit"
  }

private def propNextName (index : Nat) : Except Error Ident :=
  Ident.checked s!"prop_next_{index}"

private def propChangedName (index : Nat) : Except Error Ident :=
  Ident.checked s!"prop_changed_{index}"

private def propLabel (index : Nat) (prop : MountedProp Γ) : String :=
  s!"prop:{index}:{prop.binding.name}"

/-- Shared transaction shell for every generated dispatch function: begin
bookkeeping, the provided write statements, and the commit sweep over derived
values, text sinks, and reflected properties. -/
private def transactionShell (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (name : Ident) (params : Array Ident) (label : String)
    (writes : List Stmt) : Except Error Function := do
  let setText := runtime.setText
  let context ← Ident.checked "context"
  let state ← Ident.checked "state"
  let refs ← Ident.checked "refs"
  let tx ← Ident.checked "tx"
  let oldSources ← Ident.checked "oldSources"
  let changed ← Ident.checked "changed"
  let sinkCache ← Ident.checked "sinkCache"
  let propRefs ← Ident.checked "propRefs"
  let propCache ← Ident.checked "propCache"
  let valueCount := checked.spec.values.size
  let mut body : List Stmt := [
    .const state (arrayAt context 0),
    .const refs (arrayAt context 1),
    .const tx (arrayAt context 2),
    .const oldSources (arrayAt context 3),
    .const changed (arrayAt context 4),
    .const sinkCache (arrayAt context 5)
  ]
  unless checked.view.props.isEmpty do
    body := body ++ [
      .const propRefs (arrayAt context 6),
      .const propCache (arrayAt context 7)
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
    pushTrace tx s!"event:{label}"
  ]
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
  for (prop, propIndex) in checked.view.props.zipIdx do
    let evalName ← evaluator evaluators s!"prop:{propIndex}"
    let next ← propNextName propIndex
    let differs ← propChangedName propIndex
    let label := propLabel propIndex prop
    commitBody := commitBody ++ [.ifThen (anyChanged changed prop.binding.dependencyIds) <|
      .ofList [
      incrementAt tx 8,
      pushTrace tx s!"{label}:evaluated",
      .const next (evaluatorCall evalName state valueCount),
      .const differs <| .unary .not <|
        .binary .eq (arrayAt propCache propIndex) (.ident next),
      .ifThen (.ident differs) <| .ofList [
        .assign (.index (.ident propCache) (uint propIndex)) (.ident next),
        .expr <| call runtime.setProperty [
          arrayAt propRefs propIndex, .literal (.string prop.binding.name), .ident next
        ],
        incrementAt tx 9,
        pushTrace tx s!"dom:{label}:write"
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
  pure { name, params, body := body.toArray }

private def eventFunction (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (eventNames : List String) (event : EventSpec Γ) (eventIndex : Nat) :
    Except Error Function := do
  let context ← Ident.checked "context"
  let ignored ← Ident.checked "ignored"
  let state ← Ident.checked "state"
  let tx ← Ident.checked "tx"
  let (_, writes) ← updateStatements evaluators context state tx eventNames
    checked.spec.values.size eventIndex event.update 0
  transactionShell checked evaluators runtime (← eventName eventIndex)
    #[context, ignored] event.name writes

private def typedEventName (index : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_typed_event_{index}"

/-- Names owned by the dispatch shell; a typed payload parameter may not shadow
them. -/
private def shellLocals : List String :=
  ["state", "refs", "tx", "oldSources", "changed", "sinkCache", "propRefs",
    "propCache", "context", "hostState"]

private def typedEventFunction (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (event : AnyTypedEvent Γ) (eventIndex : Nat) :
    Except Error Function := do
  unless !shellLocals.contains event.parameterName do
    throw {
      code := "LRX-BE-028"
      message := s!"typed event parameter {event.parameterName} shadows a generated local"
    }
  let hostState ← Ident.checked "hostState"
  let context ← Ident.checked "context"
  let payload ← Ident.checked event.parameterName
  let state ← Ident.checked "state"
  let tx ← Ident.checked "tx"
  let writes : List Stmt := [
    .assign (.index (.ident state) (uint event.targetIndex)) (.ident payload),
    incrementAt tx 2,
    pushTrace tx s!"source:{event.targetName}:write"
  ]
  transactionShell checked evaluators runtime (← typedEventName eventIndex)
    #[hostState, context, payload] event.name writes

private structure DomBinding where
  path : List Nat
  name : Ident

private structure DomState where
  allocator : NameAllocator
  statements : List Stmt := []
  nodes : List DomBinding := []
  childOffs : List Ident := []

private structure SinkBinding where
  path : List Nat
  index : Nat
  evaluator : Ident

private structure PropSlot where
  path : List Nat
  name : String
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
      (sinks : List SinkBinding) (childMounts : List (String × Ident)) (path : List Nat) :
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
        let finalState ← mountChildren runtime stateName valueCount sinks childMounts
          name path 0 children state
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
    | .child _, _ =>
        .error {
          code := "LRX-BE-030"
          message := "a child component cannot be the component view root"
        }

  private def mountChildren (runtime : RuntimeNames) (stateName : Ident) (valueCount : Nat)
      (sinks : List SinkBinding) (childMounts : List (String × Ident)) (parent : Ident)
      (path : List Nat) (index : Nat) :
      MountChildren → DomState → Except Error DomState
    | .nil, state => pure state
    | .cons (.child childName) tail, state => do
        /- The child's `mount(parent)` appends its root right here, so document
        order is preserved without a wrapper element (ADR-0039). -/
        let mountName ← match childMounts.find? (·.1 == childName) with
          | some entry => pure entry.2
          | none => .error {
              code := "LRX-BE-029"
              message := s!"checked child component disappeared: {childName}"
            }
        let (off, allocator) ← state.allocator.allocate
          s!"child_off_{state.childOffs.length}"
        let state := { state with allocator, childOffs := state.childOffs ++ [off] }
        let state := appendStatement state <| .const off <| call mountName [.ident parent]
        mountChildren runtime stateName valueCount sinks childMounts parent
          path (index + 1) tail state
    | .cons head tail, state => do
        let (child, state) ← mountNode runtime stateName valueCount sinks childMounts
          (path ++ [index]) head state
        let state := appendStatement state <| .expr <| call runtime.append [.ident parent, .ident child]
        mountChildren runtime stateName valueCount sinks childMounts parent
          path (index + 1) tail state
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
    stateSlots := checked.spec.values.map (ManifestTypeId.ofRuntime ∘ ValueSpec.valueType)
    sourceCount := checked.sourceCount
    derivedCount := checked.spec.values.size - checked.sourceCount
    textSinkCount := checked.view.textSinks.length
    eventCount := checked.spec.events.size + checked.spec.typedEvents.size
    hostImports :=
      (if checked.view.events.any (fun mounted =>
          mounted.binding.kind.payload != .none || mounted.binding.kind == .submit) then
        #["./leanrx_dom.mjs", "./leanrx_form_events.mjs"]
      else #["./leanrx_dom.mjs"]) ++
      checked.spec.children.map (·.moduleSpecifier)
    features := #["scalar", "events", "transactions", "instrumentation", "trace"] ++
      (if checked.spec.typedEvents.isEmpty then #[] else #["typed-events"]) ++
      (if checked.view.props.isEmpty then #[] else #["controlled-props"]) ++
      (if checked.spec.children.isEmpty then #[] else #["child-components"]) }

/-- Lower a checked explicit component to a validated direct-DOM ESM module. -/
def emit (moduleName : String) (checked : CheckedComponent Γ) : Except Error Emitted := do
  let runtime ← runtimeNames
  let inputs := inputSpecs checked.spec.values
  let evaluators ← compileEvents inputs checked.spec.events.toList 0 <|
    ← compileProps inputs checked.view.props 0 <|
    ← compileSinks inputs checked.view.textSinks 0 <|
    ← compileValues inputs checked.spec.values.toList {}
  let state ← Ident.checked "state"
  let refs ← Ident.checked "refs"
  let tx ← Ident.checked "tx"
  let oldSources ← Ident.checked "oldSources"
  let changed ← Ident.checked "changed"
  let sinkCache ← Ident.checked "sinkCache"
  let propRefs ← Ident.checked "propRefs"
  let propCache ← Ident.checked "propCache"
  let context ← Ident.checked "context"
  let disposer ← Ident.checked "disposer"
  let target ← Ident.checked "target"
  let valueCount := checked.spec.values.size
  let eventNames := checked.spec.events.toList.map (·.name)
  let typedNames := checked.spec.typedEvents.toList.map (·.name)
  let eventFunctions ← checked.spec.events.toList.zipIdx.mapM fun (event, index) =>
    eventFunction checked evaluators runtime eventNames event index
  let typedEventFunctions ← checked.spec.typedEvents.toList.zipIdx.mapM fun (event, index) =>
    typedEventFunction checked evaluators runtime event index
  let derivedInitial ← derivedOrder checked |>.mapM fun id => do
    pure (.assign (.index (.ident state) (uint id)) <|
      evaluatorCall (← evaluator evaluators s!"value:{id}") state valueCount)
  let sinkBindings ← checked.view.textSinks.zipIdx.mapM fun (sink, index) => do
    pure { path := sink.path, index, evaluator := ← evaluator evaluators s!"sink:{index}" }
  let childMounts ← checked.spec.children.toList.zipIdx.mapM fun (child, index) => do
    pure (child.name, ← Ident.checked s!"$lrx_child_{index}")
  let initialDom : DomState := { allocator := { used := [
    "state", "refs", "tx", "oldSources", "changed", "sinkCache", "propRefs",
    "propCache", "context", "disposer", "target"
  ] } }
  let (root, dom) ← mountNode runtime state valueCount sinkBindings childMounts []
    checked.view.template initialDom
  let sinkRefs ← checked.view.textSinks.mapM fun sink => do
    pure (.ident (← nodeAt dom.nodes sink.path))
  let sinkInitialValues ← sinkBindings.mapM fun sink =>
    pure (evaluatorCall sink.evaluator state valueCount)
  let propSlots : List PropSlot ← checked.view.props.zipIdx.mapM fun (prop, index) => do
    pure {
      path := prop.path
      name := prop.binding.name
      evaluator := ← evaluator evaluators s!"prop:{index}"
    }
  let propRefExprs ← propSlots.mapM fun slot => do
    pure (Expr.ident (← nodeAt dom.nodes slot.path))
  let propInitialValues := propSlots.map fun slot =>
    evaluatorCall slot.evaluator state valueCount
  let mut mountBody : List Stmt := [
    .const state (.array <| .ofList (initialValues checked.spec.values.toList))
  ] ++ derivedInitial ++ dom.statements ++ [
    .const refs (.array <| .ofList sinkRefs),
    .const sinkCache (.array <| .ofList sinkInitialValues)
  ]
  unless checked.view.props.isEmpty do
    mountBody := mountBody ++ [
      .const propRefs (.array <| .ofList propRefExprs),
      .const propCache (.array <| .ofList propInitialValues)
    ]
    for (slot, index) in propSlots.zipIdx do
      mountBody := mountBody ++ [Stmt.expr <| call runtime.setProperty [
        arrayAt propRefs index, .literal (.string slot.name),
        arrayAt propCache index
      ]]
  mountBody := mountBody ++ [
    .const tx (.array <| .ofList [
      uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, uint 0, .array .nil,
      uint 0, uint 0
    ]),
    .const oldSources (.array <| .ofList <|
      List.replicate checked.sourceCount (.literal .null)),
    .const changed (.array <| .ofList <|
      List.replicate valueCount (.literal (.boolean false))),
    .const context (.array <| .ofList <| [
      .ident state, .ident refs, .ident tx, .ident oldSources, .ident changed,
      .ident sinkCache
    ] ++ (if checked.view.props.isEmpty then []
      else [.ident propRefs, .ident propCache])),
    .expr <| call runtime.append [.ident target, .ident root]
  ]
  let mut disposers : List Expr := dom.childOffs.map Expr.ident
  for (mounted, index) in checked.view.events.zipIdx do
    let off ← Ident.checked s!"off_{index}"
    let node ← nodeAt dom.nodes mounted.path
    match mounted.binding.kind.payload with
    | .none =>
        let eventIndex ← match eventNames.idxOf? mounted.binding.eventName with
          | some value => pure value
          | none => .error { code := "LRX-BE-026", message := "checked event binding disappeared" }
        let handler ← eventName eventIndex
        if mounted.binding.kind == .submit then
          /- The submit adapter owns `preventDefault` and takes no event-type
          argument (ADR-0021); state/refs mirror the plain `listen` wiring. -/
          mountBody := mountBody ++ [.const off <| call runtime.listenSubmit [
            .ident node, .ident context, .literal .null, .ident handler
          ]]
        else
          mountBody := mountBody ++ [.const off <| call runtime.listen [
            .ident node, .literal (.string mounted.binding.kind.name), .ident context,
            .literal .null, .ident handler
          ]]
    | .value | .key | .checked =>
        let eventIndex ← match typedNames.idxOf? mounted.binding.eventName with
          | some value => pure value
          | none => .error { code := "LRX-BE-026", message := "checked event binding disappeared" }
        let handler ← typedEventName eventIndex
        let listener := match mounted.binding.kind.payload with
          | .key => runtime.listenKey
          | .checked => runtime.listenChecked
          | _ => runtime.listenValue
        mountBody := mountBody ++ [.const off <| call listener [
          .ident node, .literal (.string mounted.binding.kind.name), .ident state,
          .ident context, .ident handler
        ]]
    disposers := disposers ++ [.ident off]
  mountBody := mountBody ++ [
    .const disposer <| call runtime.makeDisposer [
      .ident root, .array (.ofList disposers), .ident tx
    ],
    .return (.ident disposer)
  ]
  let mount ← Ident.checked "mount"
  let usesValueListener := checked.view.events.any
    fun mounted => mounted.binding.kind.payload == .value
  let usesKeyListener := checked.view.events.any
    fun mounted => mounted.binding.kind.payload == .key
  let usesCheckedListener := checked.view.events.any
    fun mounted => mounted.binding.kind.payload == .checked
  let usesSubmitListener := checked.view.events.any
    fun mounted => mounted.binding.kind == .submit
  let formImportNames : Array (Ident × Ident) :=
    (if usesValueListener then #[(runtime.listenValue, runtime.listenValue)] else #[]) ++
    (if usesKeyListener then #[(runtime.listenKey, runtime.listenKey)] else #[]) ++
    (if usesCheckedListener then #[(runtime.listenChecked, runtime.listenChecked)] else #[]) ++
    (if usesSubmitListener then #[(runtime.listenSubmit, runtime.listenSubmit)] else #[])
  let childImports := checked.spec.children.toList.zip childMounts |>.map
    fun (child, (_, localName)) =>
      { source := child.moduleSpecifier
        names := #[(mount, localName)] : Import }
  let module : Module :=
    { globals := #[← Ident.checked "String"]
      imports := #[
        { source := "./leanrx_dom.mjs", names := #[
            (runtime.createElement, runtime.createElement),
            (runtime.createText, runtime.createText),
            (runtime.setAttribute, runtime.setAttribute),
            (runtime.append, runtime.append),
            (runtime.listen, runtime.listen),
            (runtime.setText, runtime.setText),
            (runtime.makeDisposer, runtime.makeDisposer)
          ] ++ (if checked.view.props.isEmpty then #[]
            else #[(runtime.setProperty, runtime.setProperty)]) }
      ] ++ (if formImportNames.isEmpty then #[] else #[
        { source := "./leanrx_form_events.mjs", names := formImportNames }
      ]) ++ childImports.toArray
      declarations := (evaluators.declarations ++ eventFunctions.map Decl.function ++
        typedEventFunctions.map Decl.function ++ [
        Decl.function { name := mount, params := #[target], body := mountBody.toArray }
      ]).toArray
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Component
