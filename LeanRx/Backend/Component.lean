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
  | .regionAppend _ values _, writeIndex, state => do
      let mut state := state
      for (value, fieldIndex) in values.zipIdx do
        state ← addEvaluator inputs s!"event:{eventIndex}:append:{writeIndex}:{fieldIndex}"
          s!"$lrx_event_{eventIndex}_append_{writeIndex}_{fieldIndex}"
          (Lower.rxExpr value.value) state
      pure (writeIndex + 1, state)
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

/-- The context slot carrying the attribute-selection refs (ADR-0045): after
the prop slots when reflected properties exist, directly after `sinkCache`
otherwise. The cache rides one slot later. -/
private def attrSlot (checked : CheckedComponent Γ) : Nat :=
  if checked.view.props.isEmpty then 6 else 8

/-- The context slot carrying the keyed region records: after the prop and
attribute-selection slots when those exist, directly after `sinkCache`
otherwise (ADR-0041/0045). Each record is `[handle, items, nextKey, dirty]`
(plus the pending-update slot for updating regions, ADR-0043). -/
private def regionSlot (checked : CheckedComponent Γ) : Nat :=
  attrSlot checked + (if checked.view.attrSelects.isEmpty then 0 else 2)

private def regionEntry (regions : Ident) (regionIndex slot : Nat) : Expr :=
  .index (.index (.ident regions) (uint regionIndex)) (uint slot)

/-- Whether one region declares any ADR-0043 update action, so its rows can
mutate after mount and its record's pending slot can receive positions. -/
private def regionHasUpdates (region : RegionSpec) : Bool :=
  region.events.toList.any fun event =>
    match event.action with
    | .update _ => true
    | .remove => false

/-- Lower one sealed row expression against the row item array; fields sit
behind the key slot (ADR-0041/0043). `payload` is the delegated payload
expression of the dispatching typed row event (ADR-0046); validation keeps
payload references out of every other row expression position, so the
template/update-callback callers pass an inert empty string. -/
private def rowExprJs (item : Ident) (payload : Expr) : RowExpr → Expr
  | .lit value => .literal (.string value)
  | .field index => .index (.ident item) (uint (index + 1))
  | .payload => payload
  | .append first second =>
      .binary .add (rowExprJs item payload first) (rowExprJs item payload second)

/-- The inert payload expression for payload-free row expression positions. -/
private def noPayload : Expr := .literal (.string "")

/-- Lower one sealed class selection to its conditional value (ADR-0044). -/
private def rowClassJs (item : Ident) (select : RowClassSelect) : Expr :=
  .conditional
    (.binary .eq (.index (.ident item) (uint (select.field + 1)))
      (.literal (.string select.equals)))
    (.literal (.string select.whenTrue))
    (.literal (.string select.whenFalse))

/-- Lower one sealed state-scoped attribute selection to its value expression
(ADR-0045): `class` selects between its two static strings, `aria-pressed`
reflects the equality as `"true"`/`"false"`, and `disabled` is the bare
boolean equality written as an element property. -/
private def attrSelectJs (state : Ident) (select : AttrSelect Γ) : Expr :=
  let predicate := Expr.binary .eq (stateAt state select.fieldIndex)
    (.literal (.string select.equals))
  match select with
  | .classSelect _ _ whenTrue whenFalse _ =>
      .conditional predicate (.literal (.string whenTrue)) (.literal (.string whenFalse))
  | .pressedSelect .. =>
      .conditional predicate (.literal (.string "true")) (.literal (.string "false"))
  | .disabledSelect .. => predicate

private def updateStatements (evaluators : EvalState) (context state tx regions : Ident)
    (regionSpecs : Array RegionSpec) (eventNames : List String)
    (valueCount eventIndex : Nat) :
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
  | .regionAppend regionName values _, writeIndex => do
      let regionIndex ← match regionSpecs.toList.findIdx? (·.name == regionName) with
        | some index => pure index
        | none => .error {
            code := "LRX-BE-031"
            message := s!"checked region disappeared: {regionName}"
          }
      let fieldCalls ← values.zipIdx.mapM fun (_, fieldIndex) => do
        let evaluator ← evaluator evaluators
          s!"event:{eventIndex}:append:{writeIndex}:{fieldIndex}"
        pure (evaluatorCall evaluator state valueCount)
      pure (writeIndex + 1, [
        .expr <| .call (.index (regionEntry regions regionIndex 1) (.literal (.string "push")))
          (.ofList [.array (.ofList (regionEntry regions regionIndex 2 :: fieldCalls))]),
        .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 2))
          (.binary .add (regionEntry regions regionIndex 2) (uint 1)),
        .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
          (.literal (.boolean true)),
        pushTrace tx s!"region:{regionName}:append"
      ])
  | .sequence first second, writeIndex => do
      let (writeIndex, first) ← updateStatements evaluators context state tx regions
        regionSpecs eventNames valueCount eventIndex first writeIndex
      let (writeIndex, second) ← updateStatements evaluators context state tx regions
        regionSpecs eventNames valueCount eventIndex second writeIndex
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
  setKey : Ident
  childAt : Ident
  append : Ident
  listen : Ident
  listenDelegatedCells : Ident
  setText : Ident
  makeDisposer : Ident
  createKeyedRegion : Ident
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
    setKey := ← Ident.checked "setKey"
    childAt := ← Ident.checked "childAt"
    append := ← Ident.checked "append"
    listen := ← Ident.checked "listen"
    listenDelegatedCells := ← Ident.checked "listenDelegatedCells"
    setText := ← Ident.checked "setText"
    makeDisposer := ← Ident.checked "makeDisposer"
    createKeyedRegion := ← Ident.checked "createKeyedRegion"
    listenValue := ← Ident.checked "listenValue"
    listenKey := ← Ident.checked "listenKey"
    listenChecked := ← Ident.checked "listenChecked"
    listenSubmit := ← Ident.checked "listenSubmit"
  }

/-- The write statement of one attribute selection: `disabled` writes the
boolean element property (`setAttribute` cannot clear `disabled`); the other
selections write their attribute string. -/
private def attrSelectWrite (runtime : RuntimeNames) (node : Expr)
    (select : AttrSelect Γ) (value : Expr) : Stmt :=
  match select with
  | .disabledSelect .. =>
      .expr <| call runtime.setProperty [node, .literal (.string "disabled"), value]
  | _ =>
      .expr <| call runtime.setAttribute [node, .literal (.string select.name), value]

private def attrNextName (index : Nat) : Except Error Ident :=
  Ident.checked s!"attr_next_{index}"

private def attrChangedName (index : Nat) : Except Error Ident :=
  Ident.checked s!"attr_changed_{index}"

private def attrLabel (index : Nat) (mounted : MountedAttrSelect Γ) : String :=
  s!"attr:{index}:{mounted.select.name}"

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
  let attrRefs ← Ident.checked "attrRefs"
  let attrCache ← Ident.checked "attrCache"
  let regions ← Ident.checked "regions"
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
  unless checked.view.attrSelects.isEmpty do
    body := body ++ [
      .const attrRefs (arrayAt context (attrSlot checked)),
      .const attrCache (arrayAt context (attrSlot checked + 1))
    ]
  unless checked.spec.regions.isEmpty do
    body := body ++ [.const regions (arrayAt context (regionSlot checked))]
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
  /- State-scoped attribute selections join the commit sweep beside the
  reflected properties with the same evaluate-compare-write shape and the
  same tx[8]/tx[9] counters (ADR-0045). -/
  for (mounted, attrIndex) in checked.view.attrSelects.zipIdx do
    let next ← attrNextName attrIndex
    let differs ← attrChangedName attrIndex
    let label := attrLabel attrIndex mounted
    commitBody := commitBody ++ [.ifThen (anyChanged changed [mounted.select.fieldIndex]) <|
      .ofList [
      incrementAt tx 8,
      pushTrace tx s!"{label}:evaluated",
      .const next (attrSelectJs state mounted.select),
      .const differs <| .unary .not <|
        .binary .eq (arrayAt attrCache attrIndex) (.ident next),
      .ifThen (.ident differs) <| .ofList [
        .assign (.index (.ident attrCache) (uint attrIndex)) (.ident next),
        attrSelectWrite runtime (arrayAt attrRefs attrIndex) mounted.select (.ident next),
        incrementAt tx 9,
        pushTrace tx s!"dom:{label}:write"
      ]
    ]]
  for (region, regionIndex) in checked.spec.regions.toList.zipIdx do
    /- The keyed region reconciles the whole target on commit; the dirty flag
    keeps clean regions out of the sweep entirely (ADR-0041). A structurally
    dirty reconcile re-runs every retained row, so it drops pending update
    positions unrendered; an update-only transaction drains them through
    `updateAt` instead (ADR-0043). -/
    commitBody := commitBody ++ [.ifThen (regionEntry regions regionIndex 3) <| .ofList ([
      .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
        (.literal (.boolean false)),
      .expr <| .call (.index (regionEntry regions regionIndex 0) (.literal (.string "update")))
        (.ofList [regionEntry regions regionIndex 1, .literal .null]),
      pushTrace tx s!"region:{region.name}:update"
    ] ++ (if regionHasUpdates region then [
      .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 4)) (.array .nil)
    ] else []))]
    if regionHasUpdates region then
      let pendingRow ← Ident.checked "pending_row"
      commitBody := commitBody ++ [.ifThen (.unary .not <| .binary .eq
          (.index (regionEntry regions regionIndex 4) (.literal (.string "length"))) (uint 0)) <|
        .ofList [
          .forOf pendingRow (regionEntry regions regionIndex 4) (.ofList [
            .expr <| .call
              (.index (regionEntry regions regionIndex 0) (.literal (.string "updateAt")))
              (.ofList [.ident pendingRow,
                .index (regionEntry regions regionIndex 1) (.ident pendingRow),
                .literal .null]),
            pushTrace tx s!"region:{region.name}:updateAt"
          ]),
          .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 4)) (.array .nil)
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
  let regions ← Ident.checked "regions"
  let (_, writes) ← updateStatements evaluators context state tx regions
    checked.spec.regions eventNames checked.spec.values.size eventIndex event.update 0
  transactionShell checked evaluators runtime (← eventName eventIndex)
    #[context, ignored] event.name writes

private def typedEventName (index : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_typed_event_{index}"

/-- Names owned by the dispatch shell; a typed payload parameter may not shadow
them. -/
private def shellLocals : List String :=
  ["state", "refs", "tx", "oldSources", "changed", "sinkCache", "propRefs",
    "propCache", "attrRefs", "attrCache", "regions", "context", "hostState"]

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
  regionHandles : List (String × Ident) := []

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
  private def mountNode (runtime : RuntimeNames) (stateName propsName : Ident)
      (valueCount : Nat) (sinks : List SinkBinding) (childMounts : List (String × Ident))
      (regionMounts : List (String × (Ident × Ident × Ident))) (path : List Nat) :
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
        let finalState ← mountChildren runtime stateName propsName valueCount sinks
          childMounts regionMounts name path 0 children state
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
    | .propText field, state => do
        /- Immutable props are mount-time constants: the text node reads the
        positional mount argument once and is never revisited (ADR-0042). -/
        let (name, allocator) ← state.allocator.allocate s!"prop_text_{field}"
        let state := addNode { state with allocator } path name
        pure (name, appendStatement state <| .const name <|
          call runtime.createText [.index (.ident propsName) (uint field)])
    | .child _ _, _ =>
        .error {
          code := "LRX-BE-030"
          message := "a child component cannot be the component view root"
        }
    | .region _, _ =>
        .error {
          code := "LRX-BE-032"
          message := "a keyed region cannot be the component view root"
        }

  private def mountChildren (runtime : RuntimeNames) (stateName propsName : Ident)
      (valueCount : Nat) (sinks : List SinkBinding) (childMounts : List (String × Ident))
      (regionMounts : List (String × (Ident × Ident × Ident))) (parent : Ident)
      (path : List Nat) (index : Nat) :
      MountChildren → DomState → Except Error DomState
    | .nil, state => pure state
    | .cons (.child childName propValues) tail, state => do
        /- The child's `mount(parent)` appends its root right here, so document
        order is preserved without a wrapper element (ADR-0039); immutable prop
        values ride the call as one positional array (ADR-0042). -/
        let mountName ← match childMounts.find? (·.1 == childName) with
          | some entry => pure entry.2
          | none => .error {
              code := "LRX-BE-029"
              message := s!"checked child component disappeared: {childName}"
            }
        let (off, allocator) ← state.allocator.allocate
          s!"child_off_{state.childOffs.length}"
        let state := { state with allocator, childOffs := state.childOffs ++ [off] }
        let args := [Expr.ident parent] ++ (if propValues.isEmpty then []
          else [Expr.array (.ofList (propValues.map fun value => .literal (.string value)))])
        let state := appendStatement state <| .const off <| call mountName args
        mountChildren runtime stateName propsName valueCount sinks childMounts
          regionMounts parent path (index + 1) tail state
    | .cons (.region regionName) tail, state => do
        /- `createKeyedRegion(parent, …)` appends its anchor marker right here;
        rows are reconciled before it on commit (ADR-0041). -/
        let (rowFn, updateFn, disposeFn) ← match regionMounts.find? (·.1 == regionName) with
          | some entry => pure entry.2
          | none => .error {
              code := "LRX-BE-031"
              message := s!"checked region disappeared: {regionName}"
            }
        let (handle, allocator) ← state.allocator.allocate
          s!"region_{state.regionHandles.length}"
        let state := { state with allocator }
        let state :=
          { state with regionHandles := state.regionHandles ++ [(regionName, handle)] }
        let state := appendStatement state <| .const handle <| call runtime.createKeyedRegion [
          .ident parent, .ident rowFn, .ident updateFn, .ident disposeFn
        ]
        mountChildren runtime stateName propsName valueCount sinks childMounts
          regionMounts parent path (index + 1) tail state
    | .cons head tail, state => do
        let (child, state) ← mountNode runtime stateName propsName valueCount sinks
          childMounts regionMounts (path ++ [index]) head state
        let state := appendStatement state <| .expr <| call runtime.append [.ident parent, .ident child]
        mountChildren runtime stateName propsName valueCount sinks childMounts
          regionMounts parent path (index + 1) tail state
end

private def nodeAt (nodes : List DomBinding) (path : List Nat) : Except Error Ident :=
  match nodes.find? (·.path == path) with
  | some node => pure node.name
  | none => .error { code := "LRX-BE-025", message := "view binding path has no mounted node" }

/- The first row event of one delegated kind bound in one row-template
subtree: the delegated cell action for the enclosing cell and kind (at most
one per cell and kind by LRX-VIEW-027). -/
mutual
  private def rowActionOf (kind : EventKind) : RowNode → Option String
    | .element _ _ events children _ _ =>
        match events.find? (·.kind == kind) with
        | some event => some event.eventName
        | none => rowActionOfChildren kind children
    | .text _ _ | .fieldText _ _ | .exprText _ _ => none

  private def rowActionOfChildren (kind : EventKind) : RowChildren → Option String
    | .nil => none
    | .cons head tail =>
        match rowActionOf kind head with
        | some action => some action
        | none => rowActionOfChildren kind tail
end

/-- Delegated cell actions of one region and event kind: per direct child of
the row root, the row event name bound inside it with that kind, or `""` for
an actionless cell. Every direct child mounts exactly one DOM node, so
template indices equal `childNodes` indices at runtime. Each kind gets its
own action array so a click inside an input cell never resolves that cell's
typed action (ADR-0046). -/
private def regionActions (region : RegionSpec) (kind : EventKind) : List String :=
  match region.template with
  | .element _ _ _ cells _ _ => cells.toList.map fun cell => (rowActionOf kind cell).getD ""
  | _ => []

/-- The closed delegated row event kinds, in listener registration order. -/
private def regionEventKinds : List EventKind := [.click, .input, .keydown]

/-- The template binding kind of one row event, for payload lowering: a
payload-taking event is bound exactly once (LRX-VIEW-033), so the first
binding is the binding. -/
private def rowEventBindingKind? (region : RegionSpec) (name : String) :
    Option EventKind :=
  regionEventKinds.find? fun kind =>
    (regionActions region kind).contains name

private structure RowDom where
  allocator : NameAllocator
  statements : List Stmt := []
  count : Nat := 0

private def rowAppend (dom : RowDom) (statement : Stmt) : RowDom :=
  { dom with statements := dom.statements ++ [statement] }

mutual
  private def rowNodeStmts (runtime : RuntimeNames) (item : Ident) :
      RowNode → RowDom → Except Error (Ident × RowDom)
    | .element tag attrs _ children _ classIf, dom => do
        let (name, allocator) ← dom.allocator.allocate s!"row_{dom.count}"
        let dom := rowAppend { dom with allocator, count := dom.count + 1 } <| .const name <|
          call runtime.createElement [.literal (.string tag.name)]
        let mut dom := dom
        for attr in attrs do
          dom := rowAppend dom <| .expr <| call runtime.setAttribute [
            .ident name, .literal (.string attr.name), .literal (.string attr.value)
          ]
        for select in classIf do
          dom := rowAppend dom <| .expr <| call runtime.setAttribute [
            .ident name, .literal (.string "class"), rowClassJs item select
          ]
        let finalDom ← rowChildrenStmts runtime item name children dom
        pure (name, finalDom)
    | .text value _, dom => do
        let (name, allocator) ← dom.allocator.allocate s!"row_{dom.count}"
        let dom := { dom with allocator, count := dom.count + 1 }
        pure (name, rowAppend dom <| .const name <|
          call runtime.createText [.literal (.string value)])
    | .fieldText field _, dom => do
        /- Sealed row binder (ADR-0041): the projection reads `item[field + 1]`
        behind the key slot; the retained-row update callback re-renders it
        only when the region declares update actions (ADR-0043). -/
        let (name, allocator) ← dom.allocator.allocate s!"row_{dom.count}"
        let dom := { dom with allocator, count := dom.count + 1 }
        pure (name, rowAppend dom <| .const name <|
          call runtime.createText [.index (.ident item) (uint (field + 1))])
    | .exprText value _, dom => do
        let (name, allocator) ← dom.allocator.allocate s!"row_{dom.count}"
        let dom := { dom with allocator, count := dom.count + 1 }
        pure (name, rowAppend dom <| .const name <|
          call runtime.createText [rowExprJs item noPayload value])

  private def rowChildrenStmts (runtime : RuntimeNames) (item : Ident) (parent : Ident) :
      RowChildren → RowDom → Except Error RowDom
    | .nil, dom => pure dom
    | .cons head tail, dom => do
        let (child, dom) ← rowNodeStmts runtime item head dom
        let dom := rowAppend dom <| .expr <| call runtime.append [.ident parent, .ident child]
        rowChildrenStmts runtime item parent tail dom
end

private def regionRowFunction (runtime : RuntimeNames) (region : RegionSpec)
    (name : Ident) : Except Error Function := do
  let item ← Ident.checked "item"
  let position ← Ident.checked "position"
  let context ← Ident.checked "context"
  let initial : RowDom := { allocator := { used := ["item", "position", "context"] } }
  let (root, dom) ← rowNodeStmts runtime item region.template initial
  let body : List Stmt := dom.statements ++ [
    .expr <| call runtime.setKey [.ident root, .index (.ident item) (uint 0)],
    .return (.ident root)
  ]
  pure { name, params := #[item, position, context], body := body.toArray }

/- Dynamic positions of one row template with their child-index paths from the
row root, re-rendered by the retained-row update callback (ADR-0043/0044). -/
private inductive RowUpdateTarget where
  | text (path : List Nat) (value : RowExpr)
  | classSelect (path : List Nat) (select : RowClassSelect)

mutual
  private def rowUpdateTargets (path : List Nat) : RowNode → List RowUpdateTarget
    | .element _ _ _ children _ classIf =>
        classIf.map (RowUpdateTarget.classSelect path) ++
          rowUpdateTargetsChildren path 0 children
    | .text _ _ => []
    | .fieldText field _ => [.text path (.field field)]
    | .exprText value _ => [.text path value]

  private def rowUpdateTargetsChildren (path : List Nat) (index : Nat) :
      RowChildren → List RowUpdateTarget
    | .nil => []
    | .cons head tail =>
        rowUpdateTargets (path ++ [index]) head ++
          rowUpdateTargetsChildren path (index + 1) tail
end

/-- Structural navigation from the row root to one template position: every
direct child mounts exactly one DOM node, so template indices equal
`childNodes` indices at runtime (the regionActions argument again). -/
private def rowNavigate (runtime : RuntimeNames) (row : Ident) (path : List Nat) : Expr :=
  path.foldl (fun acc index => call runtime.childAt [acc, uint index]) (.ident row)

/-- The retained-row update callback: a no-op while the region's rows are
immutable (ADR-0041); when the region declares update actions, it re-renders
every dynamic text and class selection from the current item by structural
`childAt` navigation — the navigate-and-write shape of the bespoke Todo row
update (ADR-0043/0044). -/
private def regionUpdateFunction (runtime : RuntimeNames) (region : RegionSpec)
    (name : Ident) : Except Error Function := do
  let row ← Ident.checked "row"
  let item ← Ident.checked "item"
  let position ← Ident.checked "position"
  let context ← Ident.checked "context"
  let mut body : List Stmt := []
  if regionHasUpdates region then
    for target in rowUpdateTargets [] region.template do
      match target with
      | .text path value =>
          body := body ++ [.expr <| call runtime.setText [
            rowNavigate runtime row path, rowExprJs item noPayload value]]
      | .classSelect path select =>
          body := body ++ [.expr <| call runtime.setAttribute [
            rowNavigate runtime row path, .literal (.string "class"), rowClassJs item select]]
  pure { name, params := #[row, item, position, context]
         body := (body ++ [Stmt.return (.literal .null)]).toArray }

private def regionDisposeFunction (name : Ident) : Except Error Function := do
  let row ← Ident.checked "row"
  let key ← Ident.checked "key"
  let context ← Ident.checked "context"
  let body : Array Stmt := #[.return (.literal .null)]
  pure { name, params := #[row, key, context], body }

/-- The delegated dispatcher of one region: `listenDelegatedCells` resolves the
action by row structure and calls this with the row key; each declared row
event becomes one action branch running inside the shared transaction shell
(ADR-0040/0041). -/
private def regionDispatchFunction (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (region : RegionSpec) (regionIndex : Nat) (name : Ident) :
    Except Error Function := do
  let hostState ← Ident.checked "hostState"
  let context ← Ident.checked "context"
  let action ← Ident.checked "action"
  let key ← Ident.checked "key"
  let value ← Ident.checked "value"
  let checkedFlag ← Ident.checked "checked"
  let eventKey ← Ident.checked "eventKey"
  let regions ← Ident.checked "regions"
  let tx ← Ident.checked "tx"
  let mut writes : List Stmt := []
  for event in region.events do
    match event.action with
    | .remove =>
        let kept ← Ident.checked s!"kept_{regionIndex}"
        let rowEntry ← Ident.checked "row_entry"
        writes := writes ++ [
          .ifThen (.binary .eq (.ident action) (.literal (.string event.name))) (.ofList [
            .const kept (.array .nil),
            .forOf rowEntry (regionEntry regions regionIndex 1) (.ofList [
              .ifThen (.unary .not
                  (.binary .eq (.index (.ident rowEntry) (uint 0)) (.ident key))) <| .ofList [
                .expr <| .call (.index (.ident kept) (.literal (.string "push")))
                  (.ofList [.ident rowEntry])
              ]
            ]),
            .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 1))
              (.ident kept),
            .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
              (.literal (.boolean true)),
            pushTrace tx s!"region:{region.name}:{event.name}"
          ])
        ]
    | .update assignments =>
        /- Resolve the dispatching row by key scan (`scan` is
        `[cursor, match]`), evaluate every right-hand side against the old
        tuple, write the targets, and queue the position for the commit
        sweep's `updateAt` drain (ADR-0043). A typed row event's payload is
        the delegated `value` or `key` argument selected by its template
        binding kind (ADR-0046). -/
        let payloadExpr : Expr :=
          if event.takesPayload then
            match rowEventBindingKind? region event.name with
            | some .keydown => .ident eventKey
            | _ => .ident value
          else noPayload
        let scan ← Ident.checked "scan"
        let rowEntry ← Ident.checked "row_entry"
        let rowItem ← Ident.checked "row_item"
        let negativeOne : Expr := .unary .neg (uint 1)
        let mut evaluateStmts : List Stmt := []
        let mut assignStmts : List Stmt := []
        for ((target, rhs), index) in assignments.zipIdx do
          let temp ← Ident.checked s!"row_next_{index}"
          evaluateStmts := evaluateStmts ++
            [.const temp (rowExprJs rowItem payloadExpr rhs)]
          assignStmts := assignStmts ++
            [.assign (.index (.ident rowItem) (uint (target + 1))) (.ident temp)]
        writes := writes ++ [
          .ifThen (.binary .eq (.ident action) (.literal (.string event.name))) (.ofList [
            .const scan (.array (.ofList [uint 0, negativeOne])),
            .forOf rowEntry (regionEntry regions regionIndex 1) (.ofList [
              .ifThen (.binary .eq (.index (.ident rowEntry) (uint 0)) (.ident key)) <|
                .ofList [
                  .assign (.index (.ident scan) (uint 1)) (.index (.ident scan) (uint 0))
                ],
              .assign (.index (.ident scan) (uint 0))
                (.binary .add (.index (.ident scan) (uint 0)) (uint 1))
            ]),
            .ifThen (.unary .not
                (.binary .eq (.index (.ident scan) (uint 1)) negativeOne)) <| .ofList ([
              .const rowItem (.index (regionEntry regions regionIndex 1)
                (.index (.ident scan) (uint 1)))
            ] ++ evaluateStmts ++ assignStmts ++ [
              .expr <| .call
                (.index (regionEntry regions regionIndex 4) (.literal (.string "push")))
                (.ofList [.index (.ident scan) (uint 1)]),
              pushTrace tx s!"region:{region.name}:{event.name}"
            ])
          ])
        ]
  transactionShell checked evaluators runtime name
    #[hostState, context, action, key, value, checkedFlag, eventKey]
    s!"region:{region.name}" writes

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
      (if checked.spec.regions.isEmpty then #[] else #["./leanrx_region.mjs"]) ++
      checked.spec.children.map (·.moduleSpecifier)
    features := #["scalar", "events", "transactions", "instrumentation", "trace"] ++
      (if checked.spec.typedEvents.isEmpty then #[] else #["typed-events"]) ++
      (if checked.view.props.isEmpty then #[] else #["controlled-props"]) ++
      (if checked.view.attrSelects.isEmpty then #[] else #["attr-selections"]) ++
      (if checked.spec.children.isEmpty then #[] else #["child-components"]) ++
      (if checked.spec.regions.isEmpty then #[] else #["keyed-regions"]) ++
      (if checked.spec.regions.toList.any
          (fun region => region.events.toList.any (·.takesPayload)) then
        #["typed-row-events"]
      else #[]) ++
      (if checked.spec.props.isEmpty then #[] else #["immutable-props"]) }

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
  let attrRefs ← Ident.checked "attrRefs"
  let attrCache ← Ident.checked "attrCache"
  let regions ← Ident.checked "regions"
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
  let propsParam ← Ident.checked "props"
  let regionMounts ← checked.spec.regions.toList.zipIdx.mapM fun (region, index) => do
    pure (region.name,
      (← Ident.checked s!"$lrx_region_{index}_row",
        ← Ident.checked s!"$lrx_region_{index}_update",
        ← Ident.checked s!"$lrx_region_{index}_dispose"))
  let regionFunctions ← checked.spec.regions.toList.zip regionMounts |>.mapM
    fun (region, (_, (rowFn, updateFn, disposeFn))) => do
      pure [← regionRowFunction runtime region rowFn,
        ← regionUpdateFunction runtime region updateFn,
        ← regionDisposeFunction disposeFn]
  let regionDispatches ← checked.spec.regions.toList.zipIdx.mapM fun (region, index) => do
    if regionEventKinds.any fun kind => (regionActions region kind).any (· ≠ "") then
      let name ← Ident.checked s!"$lrx_region_{index}_dispatch"
      pure (some (name, ← regionDispatchFunction checked evaluators runtime region index name))
    else
      pure none
  let initialDom : DomState := { allocator := { used := [
    "state", "refs", "tx", "oldSources", "changed", "sinkCache", "propRefs",
    "propCache", "attrRefs", "attrCache", "regions", "props", "context",
    "disposer", "target"
  ] } }
  let (root, dom) ← mountNode runtime state propsParam valueCount sinkBindings childMounts
    regionMounts [] checked.view.template initialDom
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
  unless checked.view.attrSelects.isEmpty do
    /- Attribute selections mirror the reflected-property mount shape: the
    cache holds the evaluated initial values and the initial writes reuse
    the sweep's write statements (ADR-0045). -/
    let attrRefExprs ← checked.view.attrSelects.mapM fun mounted => do
      pure (Expr.ident (← nodeAt dom.nodes mounted.path))
    let attrInitialValues := checked.view.attrSelects.map fun mounted =>
      attrSelectJs state mounted.select
    mountBody := mountBody ++ [
      .const attrRefs (.array <| .ofList attrRefExprs),
      .const attrCache (.array <| .ofList attrInitialValues)
    ]
    for (mounted, index) in checked.view.attrSelects.zipIdx do
      mountBody := mountBody ++ [attrSelectWrite runtime (arrayAt attrRefs index)
        mounted.select (arrayAt attrCache index)]
  unless checked.spec.regions.isEmpty do
    /- One record per region in declaration order: `[handle, items, nextKey,
    dirty, pending]`. Keys are region-owned monotone safe integers
    (ADR-0027/0029), so uniqueness holds by construction; `pending` holds the
    positions an update-only transaction drains through `updateAt`
    (ADR-0043). -/
    let regionRecords ← checked.spec.regions.toList.mapM fun region => do
      let handle ← match dom.regionHandles.find? (·.1 == region.name) with
        | some entry => pure entry.2
        | none => .error {
            code := "LRX-BE-032"
            message := s!"checked region {region.name} was never mounted"
          }
      pure <| Expr.array <| .ofList [
        .ident handle, .array .nil, uint 0, .literal (.boolean false), .array .nil
      ]
    mountBody := mountBody ++ [
      .const regions (.array (.ofList regionRecords))
    ]
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
      else [.ident propRefs, .ident propCache]) ++
      (if checked.view.attrSelects.isEmpty then []
      else [.ident attrRefs, .ident attrCache]) ++
      (if checked.spec.regions.isEmpty then [] else [.ident regions])),
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
  for ((region, regionIndex), dispatch?) in checked.spec.regions.toList.zipIdx.zip
      regionDispatches do
    /- One structural delegated listener per region container and bound event
    kind (ADR-0030/0041/0046); each kind's cell action array maps row-root
    child indices to that kind's row event names. -/
    match dispatch? with
    | none => pure ()
    | some (dispatchName, _) =>
        let reference ← match checked.view.regionRefs.find? (·.name == region.name) with
          | some reference => pure reference
          | none => .error {
              code := "LRX-BE-031"
              message := s!"checked region disappeared: {region.name}"
            }
        let container ← nodeAt dom.nodes reference.path.dropLast
        for kind in regionEventKinds do
          let actions := regionActions region kind
          if actions.any (· ≠ "") then
            let off ← Ident.checked (if kind == .click then s!"region_off_{regionIndex}"
              else s!"region_off_{regionIndex}_{kind.name}")
            mountBody := mountBody ++ [.const off <| call runtime.listenDelegatedCells [
              .ident container, .literal (.string kind.name), .ident state, .ident context,
              .ident dispatchName,
              .array (.ofList (actions.map fun action => .literal (.string action)))
            ]]
            disposers := disposers ++ [.ident off]
  for (_, handle) in dom.regionHandles do
    disposers := disposers ++ [.index (.ident handle) (.literal (.string "dispose"))]
  mountBody := mountBody ++ [
    .const disposer <| call runtime.makeDisposer ([
      .ident root, .array (.ofList disposers), .ident tx
    ] ++ (if dom.regionHandles.isEmpty then []
      else [.array (.ofList (dom.regionHandles.map fun (_, handle) => Expr.ident handle))])),
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
  let usesDelegation := regionDispatches.any (·.isSome)
  let usesRowUpdates := checked.spec.regions.toList.any regionHasUpdates
  let regionFunctionDecls :=
    regionFunctions.flatMap id ++ regionDispatches.filterMap (·.map (·.2))
  let mountParams := #[target] ++
    (if checked.spec.props.isEmpty then #[] else #[propsParam])
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
          ] ++ (if checked.view.props.isEmpty && !checked.view.attrSelects.any
              (fun mounted => match mounted.select with
                | .disabledSelect .. => true
                | _ => false) then #[]
            else #[(runtime.setProperty, runtime.setProperty)]) ++
          (if checked.spec.regions.isEmpty then #[]
            else #[(runtime.setKey, runtime.setKey)]) ++
          (if usesRowUpdates then #[(runtime.childAt, runtime.childAt)] else #[]) ++
          (if usesDelegation then
            #[(runtime.listenDelegatedCells, runtime.listenDelegatedCells)]
          else #[]) }
      ] ++ (if formImportNames.isEmpty then #[] else #[
        { source := "./leanrx_form_events.mjs", names := formImportNames }
      ]) ++ (if checked.spec.regions.isEmpty then #[] else #[
        { source := "./leanrx_region.mjs", names := #[
            (runtime.createKeyedRegion, runtime.createKeyedRegion)
          ] }
      ]) ++ childImports.toArray
      declarations := (evaluators.declarations ++ eventFunctions.map Decl.function ++
        typedEventFunctions.map Decl.function ++ regionFunctionDecls.map Decl.function ++ [
        Decl.function { name := mount, params := mountParams, body := mountBody.toArray }
      ]).toArray
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Component
