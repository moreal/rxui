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
  /- Broadcast right-hand sides and removal predicates are sealed row
  expressions lowered inline against each row tuple (ADR-0050); they never
  read component state, so no scalar evaluator exists for them. -/
  | .regionBroadcast .., writeIndex, state => pure (writeIndex + 1, state)
  | .regionRemoveIf .., writeIndex, state => pure (writeIndex + 1, state)
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

/-- Compile the arm bodies of the key-branched events (ADR-0056). Each arm is
one ordinary update body, so it takes the next pseudo event index after the
plain events — the arm functions look their evaluators up under the same
`event:{index}:…` keys. -/
private def compileKeyEvents (inputs : Array Scalar.InputSpec) :
    List (KeyEventSpec Γ) → Nat → EvalState → Except Error EvalState
  | [], _, state => pure state
  | event :: rest, index, state => do
      let mut state := state
      let mut index := index
      for arm in event.arms do
        let (_, next) ← compileUpdate inputs index arm.update 0 state
        state := next
        index := index + 1
      compileKeyEvents inputs rest index state

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

/-- Whether one region declares any ADR-0043 update action — the ADR-0052
key-branched selection included — so its rows can mutate after mount and its
record's pending slot can receive positions. -/
private def regionHasUpdates (region : RegionSpec) : Bool :=
  region.events.toList.any fun event =>
    match event.action with
    | .update _ | .keySelect _ => true
    | .remove => false

/-- Every component-event update body: the plain events and the arms of the
key-branched events (ADR-0056), which carry exactly the same step
vocabulary. -/
private def eventUpdates (spec : ComponentSpec Γ) : List (Update Γ) :=
  spec.events.toList.map (·.update) ++
    spec.keyEvents.toList.flatMap fun event => event.arms.map (·.update)

/-- The regions any component event broadcasts into (ADR-0050), the ADR-0061
payload broadcasts included. A broadcast makes a region's rows mutable
exactly as a `row` update event does, so the real update-callback body (and
its imports) must be emitted for it. -/
private def broadcastRegionNames (spec : ComponentSpec Γ) : List String :=
  ((eventUpdates spec).flatMap fun update => update.regionBroadcastTargets.map (·.1)) ++
    spec.typedEvents.toList.filterMap fun event => event.broadcast?.map (·.1)

/-- Whether one region's rows can mutate after mount: a declared `row` update
event (ADR-0043) or a component-event broadcast into it (ADR-0050). -/
private def regionRowsMutate (broadcasts : List String) (region : RegionSpec) : Bool :=
  regionHasUpdates region || broadcasts.contains region.name

/-- The row fields one region's pending drain can write (ADR-0082): the
assignment targets of every declared `row` update stage, the ADR-0052 key
arms included. A `remove` action — and an ADR-0053 guard hit — raises the
dirty flag instead of queueing a position, and so does a broadcast
(ADR-0050), so neither is a drain path. The list is empty exactly when the
record's pending slot can never receive a position. -/
private def regionDrainWrites (region : RegionSpec) : List Nat :=
  region.events.toList.flatMap fun event =>
    match event.action with
    | .remove => []
    | .update stage => stage.assignments.map (·.1)
    | .keySelect arms => arms.flatMap fun arm => arm.2.assignments.map (·.1)

/-- The row fields one sealed filter table reads (ADR-0082): every arm
predicate's subject, which is the whole of what the emitted `hidden`
expression projects out of a row. -/
private def filterSubjectFields (filter : RegionFilter Γ) : List Nat :=
  filter.arms.flatMap fun arm => arm.2.subject.fieldRefs

/-- Whether one region's filter sweep may skip the pending-drain wake
(ADR-0082): the region has a drain path, and no field that path writes is
read by the filter's arm predicates, so a drain-only transaction provably
leaves every row's selection where the last sweep put it. Regions without a
drain path keep the uniform touched flag — their pending slot is provably
empty, so the two guards are the same predicate. -/
private def filterNarrows (region : RegionSpec) (filter? : Option (RegionFilter Γ)) : Bool :=
  match filter? with
  | none => false
  | some filter =>
      let writes := regionDrainWrites region
      !writes.isEmpty && !(filterSubjectFields filter).any writes.contains

/-- Whether one region's sealed template composes a row-scoped child
component (ADR-0075). -/
private def regionHasChildRef (region : RegionSpec) : Bool :=
  !region.template.childRefs.isEmpty

/-- The record slot of one child-composing region's live children inventory
(ADR-0075): behind the base five slots, the ADR-0050 count slots, and the
ADR-0051 filter slot, mirroring the record construction. -/
private def regionChildSlot (hasCounts hasFilter : Bool) : Nat :=
  5 + (if hasCounts then 2 else 0) + (if hasFilter then 1 else 0)

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
  | .trim value =>
      /- The sealed trim unary (ADR-0054): the ASCII whitespace strip the
      hand-written Todo backend already emits, aligned with Lean's
      `String.trim` — not the Unicode-aware `String.prototype.trim`. -/
      .call (.index (rowExprJs item payload value) (.literal (.string "replace")))
        (.ofList [.literal .asciiTrimPattern, .literal (.string "")])

/-- The inert payload expression for payload-free row expression positions. -/
private def noPayload : Expr := .literal (.string "")

/-- The shared single-field-literal comparison (ADR-0064): the sealed
predicate's subject lowered through `rowExprJs`, compared against its string
literal — for a `.field` subject, exactly the
`item[field + 1] === "literal"` subtree the spelling sites previously rebuilt
by hand, so the printed output is unchanged by construction. -/
private def fieldPredicateJs (item : Ident) (payload : Expr)
    (predicate : FieldPredicate) : Expr :=
  .binary .eq (rowExprJs item payload predicate.subject)
    (.literal (.string predicate.equals))

/-- Lower one sealed row property reflection to its written value
(ADR-0047/0049): a `value` target writes the row expression string; a
`checked` target writes the boolean equality of the row expression against
its literal. -/
private def rowReflectJs (item : Ident) (reflect : RowReflect) : Expr :=
  match reflect.target with
  | .value => rowExprJs item noPayload reflect.value
  | .checkedIf equals => fieldPredicateJs item noPayload ⟨reflect.value, equals⟩

/-- Lower one sealed class selection to its conditional value (ADR-0044). -/
private def rowClassJs (item : Ident) (select : RowClassSelect) : Expr :=
  .conditional (fieldPredicateJs item noPayload select.predicate)
    (.literal (.string select.whenTrue))
    (.literal (.string select.whenFalse))

/-- The sealed ASCII trim emission (ADR-0054/0055/0057): the whitespace strip
the hand-written Todo backend has always used, aligned with Lean's
`String.trim` — not the Unicode-aware `String.prototype.trim`. -/
private def asciiTrimJs (subject : Expr) : Expr :=
  .call (.index subject (.literal (.string "replace")))
    (.ofList [.literal .asciiTrimPattern, .literal (.string "")])

/-- `subject.split(needle).join(replacement)` — the throw-free replace-all the
persistence serialization uses (ADR-0063): no regex literal enters the
generated module and no decode step can throw, so a hand-edited stored value
fails closed instead of failing the mount. -/
private def splitJoinJs (subject : Expr) (needle replacement : String) : Expr :=
  .call
    (.index
      (.call (.index subject (.literal (.string "split")))
        (.ofList [.literal (.string needle)]))
      (.literal (.string "join")))
    (.ofList [.literal (.string replacement)])

/-- Escape one row field for the sealed storage encoding (ADR-0063): `%` first
(so decode can restore it last), then the field and row separators. -/
private def persistEncodeJs (subject : Expr) : Expr :=
  splitJoinJs (splitJoinJs (splitJoinJs subject "%" "%25") "," "%2C") ";" "%3B"

/-- Reverse the sealed storage encoding (ADR-0063): the separators first, `%`
last. -/
private def persistDecodeJs (subject : Expr) : Expr :=
  splitJoinJs (splitJoinJs (splitJoinJs subject "%2C" ",") "%3B" ";") "%25" "%"

/-- One serialized row of a persisted region (ADR-0063): the escaped fields
behind the key slot joined with the field separator. -/
private def persistRowJs (row : Ident) (fieldCount : Nat) : Expr :=
  match (List.range fieldCount).map
      (fun index => persistEncodeJs (.index (.ident row) (uint (index + 1)))) with
  | [] => .literal (.string "")
  | first :: rest =>
      rest.foldl
        (fun acc field => .binary .add (.binary .add acc (.literal (.string ","))) field)
        first

/-- Lower one sealed state-scoped attribute selection to its value expression
(ADR-0045): `class` selects between its two static strings, `aria-pressed`
reflects the equality as `"true"`/`"false"`, and `disabled` is the bare
boolean equality written as an element property. A trimmed subject
(ADR-0057) rides the sealed asciiTrimPattern emission inline — the exact
equality the ADR-0055 skip guard evaluates. A `hiddenIfEmpty` selection
reads no state: its value here is the mount-time constant `true`, because
keyed regions mount empty by construction (ADR-0050/0058) — an empty row
table has zero total rows and zero predicate-satisfying rows alike
(ADR-0059); the commit sweep re-evaluates it from the region's row table
on the region-touch path, never through this state-driven lowering. A
`checkedIfEmpty` selection mounts the same constant `true` for the same
reason read the other way (ADR-0060): an empty region has no row failing
the predicate, so the toggle-all box mounts vacuously checked. -/
private def attrSelectJs (state : Ident) (select : AttrSelect Γ) : Expr :=
  match select with
  | .classSelect field equals whenTrue whenFalse _ trimmed =>
      let subject := stateAt state field.index
      let subject := if trimmed then asciiTrimJs subject else subject
      .conditional (.binary .eq subject (.literal (.string equals)))
        (.literal (.string whenTrue)) (.literal (.string whenFalse))
  | .pressedSelect field equals _ trimmed =>
      let subject := stateAt state field.index
      let subject := if trimmed then asciiTrimJs subject else subject
      .conditional (.binary .eq subject (.literal (.string equals)))
        (.literal (.string "true")) (.literal (.string "false"))
  | .disabledSelect field equals _ trimmed =>
      let subject := stateAt state field.index
      let subject := if trimmed then asciiTrimJs subject else subject
      .binary .eq subject (.literal (.string equals))
  | .hiddenIfEmpty .. => .literal (.boolean true)
  | .checkedIfEmpty .. => .literal (.boolean true)

/-- The broadcast write body shared by the plain ADR-0050 component event and
the ADR-0061 payload broadcast: every row's targets evaluated simultaneously
against that row's old tuple, then the dirty flag — the keyed reconcile
re-renders every retained row with its identity preserved. `payload` is the
delegated payload expression of a dispatching payload broadcast event; the
plain arm passes the inert empty string. -/
private def regionBroadcastStmts (regions tx : Ident) (regionSpecs : Array RegionSpec)
    (regionName : String) (assignments : List (Nat × RowExpr)) (payload : Expr) :
    Except Error (List Stmt) := do
  let regionIndex ← match regionSpecs.toList.findIdx? (·.name == regionName) with
    | some index => pure index
    | none => .error {
        code := "LRX-BE-031"
        message := s!"checked region disappeared: {regionName}"
      }
  let rowItem ← Ident.checked "row_item"
  let mut evaluateStmts : List Stmt := []
  let mut assignStmts : List Stmt := []
  for ((target, rhs), index) in assignments.zipIdx do
    let temp ← Ident.checked s!"row_next_{index}"
    evaluateStmts := evaluateStmts ++ [.const temp (rowExprJs rowItem payload rhs)]
    assignStmts := assignStmts ++
      [.assign (.index (.ident rowItem) (uint (target + 1))) (.ident temp)]
  pure [
    .forOf rowItem (regionEntry regions regionIndex 1)
      (.ofList (evaluateStmts ++ assignStmts)),
    .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
      (.literal (.boolean true)),
    pushTrace tx s!"region:{regionName}:broadcast"
  ]

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
  | .regionBroadcast regionName assignments _, writeIndex => do
      /- The broadcast writes every row's targets from sealed row expressions
      evaluated simultaneously against that row's old tuple, then raises the
      dirty flag: the keyed reconcile re-renders every retained row with its
      identity preserved (ADR-0050). -/
      pure (writeIndex + 1,
        ← regionBroadcastStmts regions tx regionSpecs regionName assignments noPayload)
  | .regionRemoveIf regionName predicate _, writeIndex => do
      /- The predicate removal keeps every row not satisfying the sealed
      field predicate and raises the dirty flag: the keyed reconcile
      disposes exactly the dropped keys (ADR-0050). -/
      let regionIndex ← match regionSpecs.toList.findIdx? (·.name == regionName) with
        | some index => pure index
        | none => .error {
            code := "LRX-BE-031"
            message := s!"checked region disappeared: {regionName}"
          }
      let kept ← Ident.checked s!"kept_{writeIndex}"
      let rowEntry ← Ident.checked "row_entry"
      pure (writeIndex + 1, [
        .const kept (.array .nil),
        .forOf rowEntry (regionEntry regions regionIndex 1) (.ofList [
          .ifThen (.unary .not (fieldPredicateJs rowEntry noPayload predicate)) <|
            .ofList [
            .expr <| .call (.index (.ident kept) (.literal (.string "push")))
              (.ofList [.ident rowEntry])
          ]
        ]),
        .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 1)) (.ident kept),
        .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
          (.literal (.boolean true)),
        pushTrace tx s!"region:{regionName}:removeIf"
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
  detach : Ident
  listenValue : Ident
  listenKey : Ident
  listenChecked : Ident
  listenSubmit : Ident
  focus : Ident
  readHash : Ident
  listenHash : Ident
  writeHash : Ident
  storageGet : Ident
  storageSet : Ident

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
    detach := ← Ident.checked "detach"
    listenValue := ← Ident.checked "listenValue"
    listenKey := ← Ident.checked "listenKey"
    listenChecked := ← Ident.checked "listenChecked"
    listenSubmit := ← Ident.checked "listenSubmit"
    focus := ← Ident.checked "focus"
    readHash := ← Ident.checked "readHash"
    listenHash := ← Ident.checked "listenHash"
    writeHash := ← Ident.checked "writeHash"
    storageGet := ← Ident.checked "storageGet"
    storageSet := ← Ident.checked "storageSet"
  }

/-- The write statement of one attribute selection: `disabled`, `hidden`,
and `checked` write their boolean element properties (`setAttribute` cannot
clear any of them by assignment); the other selections write their
attribute string. -/
private def attrSelectWrite (runtime : RuntimeNames) (node : Expr)
    (select : AttrSelect Γ) (value : Expr) : Stmt :=
  match select with
  | .disabledSelect .. | .hiddenIfEmpty .. | .checkedIfEmpty .. =>
      .expr <| call runtime.setProperty [node, .literal (.string select.name), value]
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
    (writes : List Stmt) (skipIf? : Option Expr := none) : Except Error Function := do
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
  /- The sealed skip guard (ADR-0055): a guard hit returns before the
  transaction begins — no begin bookkeeping, no event trace, no write, no
  commit sweep. The check is emitted only for guarded component events;
  every other dispatch function is byte-identical. -/
  if let some condition := skipIf? then
    body := body ++ [.ifThen condition (.ofList [.return (.literal .null)])]
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
  /- The sealed route write (ADR-0063): whenever the routed field flipped this
  commit, the reverse of the route table writes the canonical hash literal
  through `writeHash` — flip-only behind the field's changed flag, so an
  equal-value transaction writes nothing, and a WHATWG equal-value hash
  assignment fires no hashchange, so the hashchange-dispatched set-field
  commit cannot echo. A state value outside the table writes nothing. -/
  for route in checked.spec.routes do
    let routeField ← graphNodeAt? checked route.field.index
    let writeStmts := route.arms.map fun (hash, literal) =>
      Stmt.ifThen
        (.binary .eq (stateAt state route.field.index) (.literal (.string literal)))
        (.ofList [.expr <| call runtime.writeHash [.literal (.string hash)]])
    commitBody := commitBody ++ [.ifThen (arrayAt changed route.field.index)
      (.ofList (writeStmts ++ [pushTrace tx s!"route:{routeField.name}:write"]))]
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
  same tx[8]/tx[9] counters (ADR-0045). The region-subject `hiddenIfEmpty`
  selections read no state field: they re-evaluate on the region-touch path
  below (ADR-0058), so the state-driven sweep skips them. -/
  for (mounted, attrIndex) in checked.view.attrSelects.zipIdx do
    let some fieldIndex := mounted.select.fieldIndex? | continue
    let next ← attrNextName attrIndex
    let differs ← attrChangedName attrIndex
    let label := attrLabel attrIndex mounted
    commitBody := commitBody ++ [.ifThen (anyChanged changed [fieldIndex]) <|
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
    /- Sealed row aggregates (ADR-0050): whenever this region was touched
    this transaction — structurally dirty or holding pending row updates —
    every count over it is recomputed from the row table, compared against
    its cache slot, and written through `setText`, riding the sink counters
    with `count:{region}:{index}` labels. The sweep reads the flags before
    the reconcile and drain below consume them. -/
    let counts := checked.view.regionCounts.filter (·.region == region.name)
    let filter? := checked.spec.filters.toList.find? (·.region == region.name)
    let hiddens := checked.view.attrSelects.zipIdx.filter
      fun (mounted, _) => mounted.select.regionSubject? == some region.name
    let persist? := checked.spec.persists.toList.find? (·.region == region.name)
    let touched ← Ident.checked s!"region_touched_{regionIndex}"
    /- The ADR-0082 narrowed filter wake: when no drain path writes a field
    the filter's arms read, the sweep is guarded on the structural flag
    alone and the region's touched flag serves only its other sweeps. -/
    let narrowed := filterNarrows region filter?
    let structural ← Ident.checked s!"region_structural_{regionIndex}"
    unless counts.isEmpty && (filter?.isNone || narrowed) && hiddens.isEmpty &&
        persist?.isNone do
      /- The shared touched flag serves the count sweep (ADR-0050), the
      filter sweep (ADR-0051), the empty-region visibility sweep (ADR-0058),
      and the persistence sweep (ADR-0063); all read it before the reconcile
      and drain below consume the dirty flag and the pending positions. -/
      commitBody := commitBody ++ [
        .const touched (.binary .or (regionEntry regions regionIndex 3)
          (.unary .not (.binary .eq
            (.index (regionEntry regions regionIndex 4) (.literal (.string "length")))
            (uint 0))))
      ]
    if narrowed then
      /- Read before the reconcile below clears the dirty bit, exactly as the
      touched flag is (ADR-0082). -/
      commitBody := commitBody ++ [
        .const structural (regionEntry regions regionIndex 3)
      ]
    unless counts.isEmpty do
      let mut countStmts : List Stmt := []
      for (count, slot) in counts.zipIdx do
        let next ← Ident.checked s!"count_next_{regionIndex}_{slot}"
        let differs ← Ident.checked s!"count_changed_{regionIndex}_{slot}"
        let label := s!"count:{region.name}:{slot}"
        let computeStmts : List Stmt ← match count.predicate with
          | none => pure [Stmt.const next
              (.index (regionEntry regions regionIndex 1) (.literal (.string "length")))]
          | some (field, equals) => do
              let scan ← Ident.checked s!"count_scan_{regionIndex}_{slot}"
              let row ← Ident.checked s!"count_row_{regionIndex}_{slot}"
              pure [
                Stmt.const scan (.array (.ofList [uint 0])),
                .forOf row (regionEntry regions regionIndex 1) (.ofList [
                  .ifThen (fieldPredicateJs row noPayload
                      (.ofField field equals)) <| .ofList [
                    .assign (.index (.ident scan) (uint 0))
                      (.binary .add (.index (.ident scan) (uint 0)) (uint 1))
                  ]
                ]),
                .const next (.index (.ident scan) (uint 0))
              ]
        /- A label count selects one of its two static strings from the
        recomputed count against the one literal (ADR-0062); the cache slot
        and the `setText` write then carry the selected string instead of
        the number, riding the same sink counters and labels. -/
        let (value, selectStmts) ← match count.label with
          | none => pure (Expr.ident next, ([] : List Stmt))
          | some (one, other) => do
              let selected ← Ident.checked s!"count_label_{regionIndex}_{slot}"
              pure (Expr.ident selected, [Stmt.const selected <|
                .conditional (.binary .eq (.ident next) (uint 1))
                  (.literal (.string one)) (.literal (.string other))])
        countStmts := countStmts ++ [
          incrementAt tx 5,
          pushTrace tx s!"{label}:evaluated"
        ] ++ computeStmts ++ selectStmts ++ [
          .const differs <| .unary .not <|
            .binary .eq (.index (regionEntry regions regionIndex 6) (uint slot)) value,
          .ifThen (.ident differs) <| .ofList [
            .assign (.index (regionEntry regions regionIndex 6) (uint slot)) value,
            .expr <| call setText [
              .index (regionEntry regions regionIndex 5) (uint slot), value
            ],
            incrementAt tx 6,
            pushTrace tx s!"dom:{label}:write"
          ]
        ]
      commitBody := commitBody ++ [.ifThen (.ident touched) (.ofList countStmts)]
    /- Sealed region-count subjects (ADR-0058/0059/0060): whenever this
    region was touched this transaction, every `hiddenIfEmpty` and
    `checkedIfEmpty` selection over it re-evaluates its row count against
    the zero literal — the total for the ADR-0058 emptiness subject, or the
    ADR-0050 predicate scan for the ADR-0059/0060 predicate-count
    subjects — compares it against the shared attr cache slot, and writes
    its boolean property (`hidden` or `checked`) through the existing
    `setProperty` export, riding the tx[8]/tx[9] counters with the shared
    `attr:{index}:{name}` labels. The subject is the row table, not the
    displayed rows, so an ADR-0051 filter hiding every row leaves the
    section visible — and the toggle-all box unmoved — either way. -/
    unless hiddens.isEmpty do
      let mut hiddenStmts : List Stmt := []
      for (mounted, attrIndex) in hiddens do
        let next ← attrNextName attrIndex
        let differs ← attrChangedName attrIndex
        let label := attrLabel attrIndex mounted
        let computeStmts : List Stmt ← match mounted.select.regionPredicate? with
          | none => pure [Stmt.const next (.binary .eq
              (.index (regionEntry regions regionIndex 1) (.literal (.string "length")))
              (uint 0))]
          | some (field, equals) => do
              let scan ← Ident.checked
                s!"{mounted.select.name}_scan_{regionIndex}_{attrIndex}"
              let row ← Ident.checked
                s!"{mounted.select.name}_row_{regionIndex}_{attrIndex}"
              pure [
                Stmt.const scan (.array (.ofList [uint 0])),
                .forOf row (regionEntry regions regionIndex 1) (.ofList [
                  .ifThen (fieldPredicateJs row noPayload
                      (.ofField field equals)) <| .ofList [
                    .assign (.index (.ident scan) (uint 0))
                      (.binary .add (.index (.ident scan) (uint 0)) (uint 1))
                  ]
                ]),
                .const next (.binary .eq (.index (.ident scan) (uint 0)) (uint 0))
              ]
        hiddenStmts := hiddenStmts ++ [
          incrementAt tx 8,
          pushTrace tx s!"{label}:evaluated"
        ] ++ computeStmts ++ [
          .const differs <| .unary .not <|
            .binary .eq (arrayAt attrCache attrIndex) (.ident next),
          .ifThen (.ident differs) <| .ofList [
            .assign (.index (.ident attrCache) (uint attrIndex)) (.ident next),
            attrSelectWrite runtime (arrayAt attrRefs attrIndex) mounted.select (.ident next),
            incrementAt tx 9,
            pushTrace tx s!"dom:{label}:write"
          ]
        ]
      commitBody := commitBody ++ [.ifThen (.ident touched) (.ofList hiddenStmts)]
    /- The keyed region reconciles the whole target on commit; the dirty flag
    keeps clean regions out of the sweep entirely (ADR-0041). A structurally
    dirty reconcile re-runs every retained row, so it drops pending update
    positions unrendered; an update-only transaction drains them through
    `updateAt` instead (ADR-0043). -/
    /- The row-scoped child context (ADR-0075): a child-composing region's
    record carries the live children inventory in its last slot, and the
    reconcile and drain forward it so the row mount callback pushes and the
    row dispose callback splices; other regions keep the null context. -/
    let rowContext := if regionHasChildRef region then
        regionEntry regions regionIndex (regionChildSlot (!counts.isEmpty) filter?.isSome)
      else Expr.literal .null
    commitBody := commitBody ++ [.ifThen (regionEntry regions regionIndex 3) <| .ofList ([
      .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
        (.literal (.boolean false)),
      .expr <| .call (.index (regionEntry regions regionIndex 0) (.literal (.string "update")))
        (.ofList [regionEntry regions regionIndex 1, rowContext]),
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
                rowContext]),
            pushTrace tx s!"region:{region.name}:updateAt"
          ]),
          .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 4)) (.array .nil)
        ]]
    /- The sealed region filter view (ADR-0051): after the reconcile and
    drain, whenever the region was touched — or, when no drain path writes a
    field the arms read, whenever it was structurally dirty (ADR-0082) — or
    the filter field changed, walk
    the row table in order and write each row root's `hidden` property from
    the sealed state-to-predicate table — a state value outside the table
    shows every row. Row roots are `childAt(container, i)` because the
    region owns its whole container and rows precede the anchor marker in
    `items` order; the container element rides the record's filter slot. -/
    if let some filter := filter? then
      let filterSlot := 5 + (if counts.isEmpty then 0 else 2)
      let scan ← Ident.checked s!"filter_scan_{regionIndex}"
      let filterRow ← Ident.checked s!"filter_row_{regionIndex}"
      let hiddenExpr := filter.arms.foldr
        (fun (equals, predicate) acc =>
          Expr.conditional
            (.binary .eq (stateAt state filter.field.index) (.literal (.string equals)))
            (.unary .not (fieldPredicateJs filterRow noPayload predicate))
            acc)
        (Expr.literal (.boolean false))
      commitBody := commitBody ++ [.ifThen
        (.binary .or (.ident (if narrowed then structural else touched))
          (arrayAt changed filter.field.index)) <| .ofList [
          incrementAt tx 8,
          pushTrace tx s!"filter:{region.name}:evaluated",
          .const scan (.array (.ofList [uint 0])),
          .forOf filterRow (regionEntry regions regionIndex 1) (.ofList [
            .expr <| call runtime.setProperty [
              call runtime.childAt [regionEntry regions regionIndex filterSlot,
                .index (.ident scan) (uint 0)],
              .literal (.string "hidden"), hiddenExpr
            ],
            .assign (.index (.ident scan) (uint 0))
              (.binary .add (.index (.ident scan) (uint 0)) (uint 1))
          ]),
          incrementAt tx 9,
          pushTrace tx s!"dom:filter:{region.name}:write"
        ]]
    /- The sealed persistence sweep (ADR-0063): whenever this region was
    touched this transaction, the whole row table is re-serialized — fields
    behind the key slot escaped by the throw-free split/join encoding, rows
    joined by the row separator — and written through one `storageSet`. One
    write per region-touching transaction; a filter change alone touches
    nothing and therefore persists nothing. -/
    if let some persist := persist? then
      let rows ← Ident.checked s!"persist_rows_{regionIndex}"
      let row ← Ident.checked s!"persist_row_{regionIndex}"
      commitBody := commitBody ++ [.ifThen (.ident touched) <| .ofList [
        .const rows (.array .nil),
        .forOf row (regionEntry regions regionIndex 1) (.ofList [
          .expr <| .call (.index (.ident rows) (.literal (.string "push")))
            (.ofList [persistRowJs row region.fields.size])
        ]),
        .expr <| call runtime.storageSet [
          .literal (.string persist.key),
          .call (.index (.ident rows) (.literal (.string "join")))
            (.ofList [.literal (.string ";")])
        ],
        pushTrace tx s!"storage:{region.name}:write"
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

/-- The ADR-0055 skip guard subject rides the sealed trim emission the row
lowering uses (ADR-0054): a raw subject reads the state slot, a trimmed
subject wraps it in the asciiTrimPattern replace, and the equality is
against the empty literal by construction. -/
private def skipGuardExpr (state : Ident) (guard : EventGuard Γ) : Expr :=
  let subject := stateAt state guard.field.index
  let subject := if guard.trimmed then asciiTrimJs subject else subject
  Expr.binary .eq subject (.literal (.string ""))

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
    #[context, ignored] event.name writes (skipIf? := event.guard?.map (skipGuardExpr state))

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
  let writes : List Stmt ← match event.broadcast? with
    | some (regionName, assignments) =>
        /- The ADR-0061 payload broadcast: the delegated checked boolean
        lowers to the `"true"`/`"false"` strings exactly as the ADR-0049 row
        payload does, and the write body is the shared ADR-0050 broadcast's
        with the payload expression in place of the inert string. -/
        let regions ← Ident.checked "regions"
        let payloadJs := Expr.conditional (.ident payload)
          (.literal (.string "true")) (.literal (.string "false"))
        regionBroadcastStmts regions tx checked.spec.regions regionName
          assignments payloadJs
    | none => do
        let some targetIndex := event.targetIndex?
          | .error { code := "LRX-BE-026", message := "checked typed event lost its target" }
        let some targetName := event.targetName?
          | .error { code := "LRX-BE-026", message := "checked typed event lost its target" }
        pure [
          .assign (.index (.ident state) (uint targetIndex)) (.ident payload),
          incrementAt tx 2,
          pushTrace tx s!"source:{targetName}:write"
        ]
  transactionShell checked evaluators runtime (← typedEventName eventIndex)
    #[hostState, context, payload] event.name writes

private def keyEventName (index : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_key_event_{index}"

private def keyArmName (eventIndex armIndex : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_key_event_{eventIndex}_arm_{armIndex}"

/-- The generated functions of one key-branched component event (ADR-0056):
one transaction function per arm — the ordinary guarded event shell over the
arm's steps, tracing `event:{name}:{key}` — and the dispatch function
`listenKey` calls, which compares the delegated key payload against each
sealed literal and hands the matched arm the context. A key outside the
table (and a matched arm's guard hit) returns before any transaction
exists: no begin bookkeeping, no event trace, no write, no region touch.
`bodyIndex` is the pseudo event index of the first arm — the evaluator
namespace `compileKeyEvents` compiled the arm bodies under. -/
private def keyEventFunctions (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (eventNames : List String) (event : KeyEventSpec Γ)
    (eventIndex bodyIndex : Nat) : Except Error (List Function) := do
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
  let regions ← Ident.checked "regions"
  let mut functions : List Function := []
  let mut dispatchBody : List Stmt := []
  for (arm, armIndex) in event.arms.zipIdx do
    let (_, writes) ← updateStatements evaluators context state tx regions
      checked.spec.regions eventNames checked.spec.values.size
      (bodyIndex + armIndex) arm.update 0
    let armFn ← keyArmName eventIndex armIndex
    functions := functions ++ [← transactionShell checked evaluators runtime armFn
      #[context, ← Ident.checked "ignored"] s!"{event.name}:{arm.key}" writes
      (skipIf? := arm.guard?.map (skipGuardExpr state))]
    dispatchBody := dispatchBody ++ [
      .ifThen (.binary .eq (.ident payload) (.literal (.string arm.key)))
        (.ofList [.return (call armFn [.ident context, .literal .null])])
    ]
  dispatchBody := dispatchBody ++ [.return (.literal .null)]
  pure (functions ++ [{
    name := ← keyEventName eventIndex
    params := #[hostState, context, payload]
    body := dispatchBody.toArray }])

private def routeArmName (routeIndex armIndex : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_route_{routeIndex}_arm_{armIndex}"

private def routeDispatchName (routeIndex : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_route_{routeIndex}"

/-- The declared initial of the routed `String` source (ADR-0063), for the
dispatch fallback arm. -/
private def routeDefault? (values : Array (ValueSpec Γ)) (index : Nat) : Option String :=
  values[index]?.bind fun value =>
    match value with
    | .source _ _ _ (.string literal) _ => some literal
    | _ => none

/-- The generated functions of one sealed route item (ADR-0063): one
transaction function per arm — the filter buttons' set-field transaction
shape with the arm's state literal written directly, tracing
`event:route:{field}:{literal}` — and the dispatch function `listenHash`
calls, which compares the delegated hash against each sealed hash literal and
hands the matched arm the context; an unknown or empty hash falls to the arm
carrying the declared default literal, so the whole hash space lands in the
table. An equal-value dispatch is an ordinary empty commit — `changed` stays
false, so the flip-only `writeHash` ride writes nothing and no echo loop
exists. -/
private def routeFunctions (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (route : RouteSpec Γ) (routeIndex : Nat)
    (defaultLiteral : String) : Except Error (List Function) := do
  let hostState ← Ident.checked "hostState"
  let context ← Ident.checked "context"
  let hash ← Ident.checked "hash"
  let state ← Ident.checked "state"
  let tx ← Ident.checked "tx"
  let routeField ← graphNodeAt? checked route.field.index
  let mut functions : List Function := []
  let mut dispatchBody : List Stmt := []
  let mut defaultArm? : Option Ident := none
  for ((hashLiteral, literal), armIndex) in route.arms.zipIdx do
    let armFn ← routeArmName routeIndex armIndex
    let writes : List Stmt := [
      .assign (.index (.ident state) (uint route.field.index))
        (.literal (.string literal)),
      incrementAt tx 2,
      pushTrace tx s!"source:{routeField.name}:write"
    ]
    functions := functions ++ [← transactionShell checked evaluators runtime armFn
      #[context, ← Ident.checked "ignored"]
      s!"route:{routeField.name}:{literal}" writes]
    dispatchBody := dispatchBody ++ [
      .ifThen (.binary .eq (.ident hash) (.literal (.string hashLiteral)))
        (.ofList [.return (call armFn [.ident context, .literal .null])])
    ]
    if literal == defaultLiteral then
      defaultArm? := some armFn
  let defaultArm ← match defaultArm? with
    | some armFn => pure armFn
    | none => .error {
        code := "LRX-BE-034"
        message := "checked route lost its default arm"
      }
  dispatchBody := dispatchBody ++ [.return (call defaultArm [.ident context, .literal .null])]
  pure (functions ++ [{
    name := ← routeDispatchName routeIndex
    params := #[hostState, context, hash]
    body := dispatchBody.toArray }])

private def hydrateName (persistIndex : Nat) : Except Error Ident :=
  Ident.checked s!"$lrx_hydrate_{persistIndex}"

/-- The generated mount hydration of one persisted region (ADR-0063): one
ordinary transaction function whose writes parse the stored value and push
the parsed rows through the existing append path — region-owned keys, the
nextKey increment, the dirty flag — so the shared commit sweep reconciles the
rows, recomputes every count and visibility subject, applies the filter
table, and re-persists the normalized serialization, all through the code
every other transaction runs. A missing or empty value parses to no rows,
and any row whose field count differs from the declared arity fails the
whole value closed to the empty region. -/
private def hydrateFunction (checked : CheckedComponent Γ) (evaluators : EvalState)
    (runtime : RuntimeNames) (persist : PersistSpec) (persistIndex : Nat) :
    Except Error Function := do
  let context ← Ident.checked "context"
  let regions ← Ident.checked "regions"
  let tx ← Ident.checked "tx"
  let regionIndex ← match checked.spec.regions.toList.findIdx?
      (·.name == persist.region) with
    | some index => pure index
    | none => .error {
        code := "LRX-BE-031"
        message := s!"checked region disappeared: {persist.region}"
      }
  let region ← match checked.spec.regions.toList.find? (·.name == persist.region) with
    | some region => pure region
    | none => .error {
        code := "LRX-BE-031"
        message := s!"checked region disappeared: {persist.region}"
      }
  let stored ← Ident.checked "stored_value"
  let rowsId ← Ident.checked "hydrate_rows"
  let okId ← Ident.checked "hydrate_ok"
  let part ← Ident.checked "hydrate_part"
  let fieldsId ← Ident.checked "hydrate_fields"
  let rowId ← Ident.checked "hydrate_row"
  let writes : List Stmt := [
    .const stored (call runtime.storageGet [.literal (.string persist.key)]),
    .const rowsId (.array .nil),
    .const okId (.array (.ofList [.literal (.boolean true)])),
    .ifThen (.unary .not (.binary .eq (.ident stored) (.literal .null))) <| .ofList [
      .ifThen (.unary .not (.binary .eq (.ident stored) (.literal (.string "")))) <|
        .ofList [
        .forOf part (.call (.index (.ident stored) (.literal (.string "split")))
            (.ofList [.literal (.string ";")])) (.ofList [
          .const fieldsId (.call (.index (.ident part) (.literal (.string "split")))
            (.ofList [.literal (.string ",")])),
          .ifThen (.unary .not (.binary .eq
              (.index (.ident fieldsId) (.literal (.string "length")))
              (uint region.fields.size))) (.ofList [
            .assign (.index (.ident okId) (uint 0)) (.literal (.boolean false))
          ]),
          .expr <| .call (.index (.ident rowsId) (.literal (.string "push")))
            (.ofList [.ident fieldsId])
        ])
      ]
    ],
    .ifThen (.binary .and (.index (.ident okId) (uint 0))
        (.unary .not (.binary .eq
          (.index (.ident rowsId) (.literal (.string "length"))) (uint 0)))) <|
      .ofList [
      .forOf rowId (.ident rowsId) (.ofList [
        .expr <| .call
          (.index (regionEntry regions regionIndex 1) (.literal (.string "push")))
          (.ofList [.array (.ofList (regionEntry regions regionIndex 2 ::
            (List.range region.fields.size).map fun index =>
              persistDecodeJs (.index (.ident rowId) (uint index))))]),
        .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 2))
          (.binary .add (regionEntry regions regionIndex 2) (uint 1))
      ]),
      .assign (.index (.index (.ident regions) (uint regionIndex)) (uint 3))
        (.literal (.boolean true)),
      pushTrace tx s!"region:{persist.region}:hydrate"
    ]
  ]
  transactionShell checked evaluators runtime (← hydrateName persistIndex)
    #[context, ← Ident.checked "ignored"] s!"hydrate:{persist.region}" writes

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
    | .countText label, state => do
        /- Sealed row aggregates mount as `"0"` (ADR-0050): regions mount
        empty by construction, so every count starts at zero and is first
        recomputed by the commit sweep that touches its region. A label
        count mounts as its `else` string for the same reason — the zero
        count differs from the one literal (ADR-0062). -/
        let (name, allocator) ← state.allocator.allocate
          s!"count_text_{state.nodes.length}"
        let state := addNode { state with allocator } path name
        let mounted := match label with
          | none => "0"
          | some (_, other) => other
        pure (name, appendStatement state <| .const name <|
          call runtime.createText [.literal (.string mounted)])
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
        values ride the call as one positional array (ADR-0042), a forwarded
        value reading the parent's own positional mount argument (ADR-0068). -/
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
          else [Expr.array (.ofList (propValues.map fun value => match value with
            | .lit text => .literal (.string text)
            | .forward field => .index (.ident propsName) (uint field)))])
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
one per cell and kind by LRX-VIEW-027). A branch cell draws the action from
whichever branch binds the kind; the cross-branch agreement check
(LRX-VIEW-034) keeps the static action array sound (ADR-0047). -/
mutual
  private def rowActionOf (kind : EventKind) : RowNode → Option String
    | .element _ _ events children _ _ _ _ =>
        match events.find? (·.kind == kind) with
        | some event => some event.eventName
        | none => rowActionOfChildren kind children
    | .text _ _ | .fieldText _ _ | .exprText _ _ | .child .. => none
    | .branch _ _ whenTrue whenFalse _ =>
        match rowActionOf kind whenTrue with
        | some action => some action
        | none => rowActionOf kind whenFalse

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
  | .element _ _ _ cells _ _ _ _ => cells.toList.map fun cell => (rowActionOf kind cell).getD ""
  | _ => []

/-- The closed delegated row event kinds (ADR-0041/0046/0049), in listener
registration order. -/
private def regionEventKinds : List EventKind :=
  [.click, .dblclick, .input, .keydown, .checkedChange]

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
  /- The builder-function pairs of the template's branch cells in traversal
  order (ADR-0047); each branch cell consumes one pair. -/
  branchFns : List (Ident × Ident) := []
  /- The aliased child mount imports by child name (ADR-0075), for row-scoped
  child references; empty outside the row mount callback, where validation
  keeps child references out anyway. -/
  childMounts : List (String × Ident) := []
  /- The row-scoped child mount returns in traversal order (ADR-0075); the
  row mount callback stashes each on the row root for the dispose callback. -/
  childOffs : List Ident := []

private def rowAppend (dom : RowDom) (statement : Stmt) : RowDom :=
  { dom with statements := dom.statements ++ [statement] }

/-- The compiler-owned marker property naming the rendered branch of one
branch cell wrapper, in the `setKey`/`$lrxKey` style (ADR-0047). -/
private def branchMarker : String := "$lrxBranch"

/-- The compiler-owned property stashing a row's child mount return on the
row root (ADR-0075), in the `$lrxKey`/`$lrxBranch` style: every host removal
path hands the row root to the dispose callback, so the stash is the one
place the per-row child disposer stays reachable from. -/
private def rowChildMarker : String := "$lrxRowChild"

mutual
  private def rowNodeStmts (runtime : RuntimeNames) (item : Ident) :
      RowNode → RowDom → Except Error (Ident × RowDom)
    | .element tag attrs _ children _ classIf reflects _, dom => do
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
        for reflect in reflects do
          dom := rowAppend dom <| .expr <| call runtime.setProperty [
            .ident name, .literal (.string reflect.target.propertyName),
            rowReflectJs item reflect
          ]
        let finalDom ← rowChildrenStmts runtime item name children dom
        pure (name, finalDom)
    | .branch field equals _ _ _, dom => do
        /- The branch cell mounts as one wrapper element holding the selected
        sealed subtree, so the cell keeps exactly one row-root child index
        and replacement composes from the existing `detach`/`append` host
        primitives; the wrapper carries the rendered branch as the
        `$lrxBranch` marker property (ADR-0047). -/
        let (whenTrueFn, whenFalseFn, rest) ← match dom.branchFns with
          | (whenTrueFn, whenFalseFn) :: rest => pure (whenTrueFn, whenFalseFn, rest)
          | [] => .error {
              code := "LRX-BE-033"
              message := "row branch cell has no builder functions"
            }
        let dom := { dom with branchFns := rest }
        let (wrapper, allocator) ← dom.allocator.allocate s!"row_{dom.count}"
        let dom := { dom with allocator, count := dom.count + 1 }
        let (flag, allocator) ← dom.allocator.allocate s!"row_{dom.count}"
        let dom := { dom with allocator, count := dom.count + 1 }
        let dom := rowAppend dom <| .const wrapper <|
          call runtime.createElement [.literal (.string HtmlTag.span.name)]
        let dom := rowAppend dom <| .const flag <|
          fieldPredicateJs item noPayload (.ofField field equals)
        let dom := rowAppend dom <| .expr <| call runtime.append [
          .ident wrapper,
          .conditional (.ident flag) (call whenTrueFn [.ident item])
            (call whenFalseFn [.ident item])
        ]
        let dom := rowAppend dom <| .expr <| call runtime.setProperty [
          .ident wrapper, .literal (.string branchMarker), .ident flag
        ]
        pure (wrapper, dom)
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
    | .child .., _ =>
        .error {
          code := "LRX-BE-035"
          message := "a row child reference cannot be the row template root"
        }

  private def rowChildrenStmts (runtime : RuntimeNames) (item : Ident) (parent : Ident) :
      RowChildren → RowDom → Except Error RowDom
    | .nil, dom => pure dom
    | .cons (.child childName propValues _) tail, dom => do
        /- The row-scoped child mount (ADR-0075): the child's `mount(parent)`
        appends its root right here, so document order and structural
        `childAt` navigation hold without a wrapper (the ADR-0039 shape in
        row scope). Prop values are row-mount constants — string literals or
        projections of the row item behind the key slot — and the mount
        return joins the live children inventory the region call sites pass
        as the callback `context` (ADR-0075's extension of the ADR-0066
        republication). -/
        let mountName ← match dom.childMounts.find? (·.1 == childName) with
          | some entry => pure entry.2
          | none => .error {
              code := "LRX-BE-029"
              message := s!"checked child component disappeared: {childName}"
            }
        let (off, allocator) ← dom.allocator.allocate
          s!"row_child_{dom.childOffs.length}"
        let dom := { dom with allocator, childOffs := dom.childOffs ++ [off] }
        let args := [Expr.ident parent] ++ (if propValues.isEmpty then []
          else [Expr.array (.ofList (propValues.map fun value => match value.2 with
            | .lit text => .literal (.string text)
            | .field index => .index (.ident item) (uint (index + 1))))])
        let dom := rowAppend dom <| .const off <| call mountName args
        let context ← Ident.checked "context"
        let dom := rowAppend dom <| .expr <| .call
          (.index (.ident context) (.literal (.string "push"))) (.ofList [.ident off])
        rowChildrenStmts runtime item parent tail dom
    | .cons head tail, dom => do
        let (child, dom) ← rowNodeStmts runtime item head dom
        let dom := rowAppend dom <| .expr <| call runtime.append [.ident parent, .ident child]
        rowChildrenStmts runtime item parent tail dom
end

/-- The branch cells of one row template in traversal order (ADR-0047):
validation confines them to cell positions, so the direct children of the
row root are the whole inventory. -/
private def templateBranches (template : RowNode) : List RowNode :=
  match template with
  | .element _ _ _ cells _ _ _ _ => cells.toList.filter fun cell =>
      match cell with
      | .branch .. => true
      | _ => false
  | _ => []

/- The child-index path (relative to one sealed branch subtree's root) of the
subtree's autoFocus-marked input, when one exists (ADR-0048). Validation
admits at most one marker per branch subtree and never below a nested branch,
so the first hit is the whole inventory. -/
mutual
  private def rowFocusPath? : RowNode → Option (List Nat)
    | .element _ _ _ children _ _ _ autoFocus =>
        if autoFocus then some [] else rowFocusPathChildren 0 children
    | .text _ _ | .fieldText _ _ | .exprText _ _ | .branch .. | .child .. => none

  private def rowFocusPathChildren (index : Nat) : RowChildren → Option (List Nat)
    | .nil => none
    | .cons head tail =>
        match rowFocusPath? head with
        | some path => some (index :: path)
        | none => rowFocusPathChildren (index + 1) tail
end

/-- Whether one region's generated module transfers focus (ADR-0048): the
update callback's replacement arm is emitted only for regions with mutable
rows (ADR-0043/0050), so a marker in an immutable region stays inert and
imports nothing — components without a reachable marker emit byte-identical
modules. -/
private def regionUsesFocus (broadcasts : List String) (region : RegionSpec) : Bool :=
  regionRowsMutate broadcasts region && (templateBranches region.template).any fun cell =>
    match cell with
    | .branch _ _ whenTrue whenFalse _ =>
        (rowFocusPath? whenTrue).isSome || (rowFocusPath? whenFalse).isSome
    | _ => false

/- Whether one sealed subtree carries a row value reflection (ADR-0047), for
the manifest feature flag and the setProperty import. -/
mutual
  private def rowHasReflect : RowNode → Bool
    | .element _ _ _ children _ _ reflects _ =>
        !reflects.isEmpty || rowHasReflectChildren children
    | .text _ _ | .fieldText _ _ | .exprText _ _ | .child .. => false
    | .branch _ _ whenTrue whenFalse _ => rowHasReflect whenTrue || rowHasReflect whenFalse

  private def rowHasReflectChildren : RowChildren → Bool
    | .nil => false
    | .cons head tail => rowHasReflect head || rowHasReflectChildren tail
end

/-- One sealed branch subtree builder (ADR-0047): the mount statements of the
branch root against the row item, shared by the row mount conditional and the
update callback's replacement arm. -/
private def regionBranchFunction (runtime : RuntimeNames) (root : RowNode)
    (name : Ident) : Except Error Function := do
  let item ← Ident.checked "item"
  let initial : RowDom := { allocator := { used := ["item"] } }
  let (rootName, dom) ← rowNodeStmts runtime item root initial
  pure { name, params := #[item]
         body := (dom.statements ++ [Stmt.return (.ident rootName)]).toArray }

private def regionRowFunction (runtime : RuntimeNames) (region : RegionSpec)
    (branchFns : List (Ident × Ident)) (childMounts : List (String × Ident))
    (name : Ident) : Except Error Function := do
  let item ← Ident.checked "item"
  let position ← Ident.checked "position"
  let context ← Ident.checked "context"
  let initial : RowDom :=
    { allocator := { used := ["item", "position", "context"] }, branchFns, childMounts }
  let (root, dom) ← rowNodeStmts runtime item region.template initial
  /- The ADR-0075 stash: the row root carries its child mount return so the
  dispose callback can reach it from the row handle alone — the region's own
  dispose path passes no context. -/
  let stashStmts := dom.childOffs.map fun off =>
    Stmt.assign (.index (.ident root) (.literal (.string rowChildMarker))) (.ident off)
  let body : List Stmt := dom.statements ++ stashStmts ++ [
    .expr <| call runtime.setKey [.ident root, .index (.ident item) (uint 0)],
    .return (.ident root)
  ]
  pure { name, params := #[item, position, context], body := body.toArray }

/- Dynamic positions of one row template with their child-index paths from the
row root, re-rendered by the retained-row update callback
(ADR-0043/0044/0047). A branch target carries its whole cell: the callback
compares the predicate against the rendered marker and either updates the
stable subtree in place or replaces it. -/
private inductive RowUpdateTarget where
  | text (path : List Nat) (value : RowExpr)
  | classSelect (path : List Nat) (select : RowClassSelect)
  | reflect (path : List Nat) (reflect : RowReflect)
  | branchCell (path : List Nat) (field : Nat) (equals : String)
      (whenTrue whenFalse : RowNode)

mutual
  private def rowUpdateTargets (path : List Nat) : RowNode → List RowUpdateTarget
    | .element _ _ _ children _ classIf reflects _ =>
        classIf.map (RowUpdateTarget.classSelect path) ++
          reflects.map (RowUpdateTarget.reflect path) ++
          rowUpdateTargetsChildren path 0 children
    | .text _ _ | .child .. => []
    | .fieldText field _ => [.text path (.field field)]
    | .exprText value _ => [.text path value]
    | .branch field equals whenTrue whenFalse _ =>
        [.branchCell path field equals whenTrue whenFalse]

  private def rowUpdateTargetsChildren (path : List Nat) (index : Nat) :
      RowChildren → List RowUpdateTarget
    | .nil => []
    | .cons head tail =>
        rowUpdateTargets (path ++ [index]) head ++
          rowUpdateTargetsChildren path (index + 1) tail
end

/-- Structural navigation from one base node to a template position: every
direct child mounts exactly one DOM node, so template indices equal
`childNodes` indices at runtime (the regionActions argument again). -/
private def rowNavigate (runtime : RuntimeNames) (base : Expr) (path : List Nat) : Expr :=
  path.foldl (fun acc index => call runtime.childAt [acc, uint index]) base

/-- The in-place write statements of the non-branch targets of one subtree,
rooted at `base` (ADR-0043/0044/0047). Branch targets cannot appear below a
cell, so a nested branch is a compiler error. -/
private def rowTargetWrites (runtime : RuntimeNames) (item : Ident) (base : Expr)
    (targets : List RowUpdateTarget) : Except Error (List Stmt) := do
  targets.mapM fun target =>
    match target with
    | .text path value =>
        pure <| .expr <| call runtime.setText [
          rowNavigate runtime base path, rowExprJs item noPayload value]
    | .classSelect path select =>
        pure <| .expr <| call runtime.setAttribute [
          rowNavigate runtime base path, .literal (.string "class"), rowClassJs item select]
    | .reflect path reflect =>
        pure <| .expr <| call runtime.setProperty [
          rowNavigate runtime base path,
          .literal (.string reflect.target.propertyName),
          rowReflectJs item reflect]
    | .branchCell .. =>
        .error { code := "LRX-BE-033", message := "row branch cells cannot nest" }

/-- The retained-row update callback: a no-op while the region's rows are
immutable (ADR-0041); when the region's rows can mutate — a declared `row`
update event (ADR-0043) or a component-event broadcast (ADR-0050) — it re-renders
every dynamic text, class selection, and value reflection from the current
item by structural `childAt` navigation — the navigate-and-write shape of the
bespoke Todo row update (ADR-0043/0044) — and, for each branch cell,
re-evaluates the sealed predicate against the wrapper's `$lrxBranch` marker:
a stable branch is updated in place and a changed branch is replaced with one
`detach` plus one `append` of the freshly built subtree (ADR-0047). -/
private def regionUpdateFunction (runtime : RuntimeNames) (region : RegionSpec)
    (mutable : Bool) (branchFns : List (Ident × Ident)) (name : Ident) :
    Except Error Function := do
  let row ← Ident.checked "row"
  let item ← Ident.checked "item"
  let position ← Ident.checked "position"
  let context ← Ident.checked "context"
  let mut body : List Stmt := []
  let mut remainingBranchFns := branchFns
  if mutable then
    for target in rowUpdateTargets [] region.template do
      match target with
      | .branchCell path field equals whenTrue whenFalse =>
          let (whenTrueFn, whenFalseFn) ← match remainingBranchFns with
            | pair :: rest =>
                remainingBranchFns := rest
                pure pair
            | [] => .error {
                code := "LRX-BE-033"
                message := "row branch cell has no builder functions"
              }
          let branchIndex := branchFns.length - remainingBranchFns.length - 1
          let cell ← Ident.checked s!"branch_cell_{branchIndex}"
          let want ← Ident.checked s!"branch_want_{branchIndex}"
          let same ← Ident.checked s!"branch_same_{branchIndex}"
          body := body ++ [
            .const cell (rowNavigate runtime (.ident row) path),
            .const want (fieldPredicateJs item noPayload (.ofField field equals)),
            .const same (.binary .eq
              (.index (.ident cell) (.literal (.string branchMarker))) (.ident want))
          ]
          let branchRoot := call runtime.childAt [.ident cell, uint 0]
          let whenTrueWrites ← rowTargetWrites runtime item branchRoot
            (rowUpdateTargets [] whenTrue)
          let whenFalseWrites ← rowTargetWrites runtime item branchRoot
            (rowUpdateTargets [] whenFalse)
          let stable :=
            (if whenTrueWrites.isEmpty then []
              else [Stmt.ifThen (.ident want) (.ofList whenTrueWrites)]) ++
            (if whenFalseWrites.isEmpty then []
              else [Stmt.ifThen (.unary .not (.ident want)) (.ofList whenFalseWrites)])
          unless stable.isEmpty do
            body := body ++ [.ifThen (.ident same) (.ofList stable)]
          /- The ADR-0048 focus transfer: only the replacement arm, after the
          fresh subtree is appended, focuses the incoming branch's marked
          input — row mount and the stable arm never call `focus`. -/
          let focusTrue := match rowFocusPath? whenTrue with
            | some path => [Stmt.ifThen (.ident want) (.ofList [
                .expr <| call runtime.focus [rowNavigate runtime branchRoot path]])]
            | none => []
          let focusFalse := match rowFocusPath? whenFalse with
            | some path => [Stmt.ifThen (.unary .not (.ident want)) (.ofList [
                .expr <| call runtime.focus [rowNavigate runtime branchRoot path]])]
            | none => []
          body := body ++ [.ifThen (.unary .not (.ident same)) (.ofList ([
            .expr <| call runtime.detach [branchRoot],
            .expr <| call runtime.append [
              .ident cell,
              .conditional (.ident want) (call whenTrueFn [.ident item])
                (call whenFalseFn [.ident item])
            ],
            .expr <| call runtime.setProperty [
              .ident cell, .literal (.string branchMarker), .ident want
            ]
          ] ++ focusTrue ++ focusFalse))]
      | _ =>
          body := body ++ (← rowTargetWrites runtime item (.ident row) [target])
  pure { name, params := #[row, item, position, context]
         body := (body ++ [Stmt.return (.literal .null)]).toArray }

private def regionDisposeFunction (hasChild : Bool) (name : Ident) :
    Except Error Function := do
  let row ← Ident.checked "row"
  let key ← Ident.checked "key"
  let context ← Ident.checked "context"
  let body : List Stmt :=
    if hasChild then
      /- The per-row child dispose (ADR-0075): every host removal path — the
      reconcile, `removeAt`, and the region's own dispose — funnels through
      this callback with the row root, so the stashed mount return is called
      here. The live-inventory splice is guarded: the region's full dispose
      passes no context, and by then the whole component is being disposed —
      the inventory keeps its (disposed) entries exactly as the static
      ADR-0066 array does after a root dispose. -/
      [
        .ifThen (.ident context) (.ofList [
          .expr <| .call (.index (.ident context) (.literal (.string "splice")))
            (.ofList [
              .call (.index (.ident context) (.literal (.string "indexOf")))
                (.ofList [.index (.ident row) (.literal (.string rowChildMarker))]),
              uint 1
            ])
        ]),
        .expr <| .call (.index (.ident row) (.literal (.string rowChildMarker))) .nil,
        .return (.literal .null)
      ]
    else [.return (.literal .null)]
  pure { name, params := #[row, key, context], body := body.toArray }

/-- The row removal sequence of one dispatch branch: filter the dispatching
key out of the row table, mark the region dirty for the reconcile, and push
the region trace. Shared by the sealed `remove` action and the guard hit of
an ADR-0053 guarded stage. -/
private def rowRemoveStmts (regions tx key : Ident) (regionIndex : Nat)
    (regionName eventName : String) : Except Error (List Stmt) := do
  let kept ← Ident.checked s!"kept_{regionIndex}"
  let rowEntry ← Ident.checked "row_entry"
  pure [
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
    pushTrace tx s!"region:{regionName}:{eventName}"
  ]

/-- The ADR-0043 scan-evaluate-assign-queue sequence of one row stage:
resolve the dispatching row by key scan (`scan` is `[cursor, match]`),
evaluate every right-hand side against the old tuple, write the targets, and
queue the position for the commit sweep's `updateAt` drain. Shared by the
plain update action and each key arm of an ADR-0052 key-branched action. A
stage with an ADR-0053 remove-if guard first evaluates the sealed field
equality against the resolved row: a guard hit runs the removal sequence
instead — no field write and no queued position — and a miss commits the
assignments exactly as an unguarded stage does. -/
private def rowUpdateApplyStmts (regions tx key : Ident) (regionIndex : Nat)
    (regionName eventName : String) (payloadExpr : Expr)
    (stage : RowStage) : Except Error (List Stmt) := do
  let assignments := stage.assignments
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
  let applyStmts := evaluateStmts ++ assignStmts ++ [
    .expr <| .call
      (.index (regionEntry regions regionIndex 4) (.literal (.string "push")))
      (.ofList [.index (.ident scan) (uint 1)]),
    pushTrace tx s!"region:{regionName}:{eventName}"
  ]
  let foundStmts ← match stage.removeIf with
    | none => pure applyStmts
    | some guard => do
        let rowGuard ← Ident.checked "row_guard"
        pure [
          /- The guard subject rides the same `rowExprJs` lowering the commit
          assignments use (ADR-0054): a raw field projects the row slot, a
          trimmed subject wraps it in the sealed trim emission. -/
          .const rowGuard (fieldPredicateJs rowItem noPayload guard),
          .ifThen (.ident rowGuard) (.ofList
            (← rowRemoveStmts regions tx key regionIndex regionName eventName)),
          .ifThen (.unary .not (.ident rowGuard)) (.ofList applyStmts)
        ]
  pure [
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
    ] ++ foundStmts)
  ]

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
        writes := writes ++ [
          .ifThen (.binary .eq (.ident action) (.literal (.string event.name)))
            (.ofList (← rowRemoveStmts regions tx key regionIndex
              region.name event.name))
        ]
    | .update stage =>
        /- The ADR-0043 scan-evaluate-assign-queue sequence. A typed row
        event's payload is the delegated `value`, `key`, or
        `"true"`/`"false"`-lowered `checked` argument selected by its
        template binding kind (ADR-0046/0049). -/
        let payloadExpr : Expr :=
          if event.takesPayload then
            match rowEventBindingKind? region event.name with
            | some .keydown => .ident eventKey
            | some .checkedChange =>
                .conditional (.ident checkedFlag)
                  (.literal (.string "true")) (.literal (.string "false"))
            | _ => .ident value
          else noPayload
        writes := writes ++ [
          .ifThen (.binary .eq (.ident action) (.literal (.string event.name)))
            (.ofList (← rowUpdateApplyStmts regions tx key regionIndex
              region.name event.name payloadExpr stage))
        ]
    | .keySelect arms =>
        /- The ADR-0052 key-branched selection: one `eventKey` equality per
        arm wrapping the shared scan-evaluate-assign-queue sequence, so a
        matched key drains exactly one retained-row `updateAt` and a
        non-matching key never reaches the row scan — no field write, no
        queued position, no region trace. Arm right-hand sides are
        payload-free by validation, so the inert payload is passed. -/
        let mut armStmts : List Stmt := []
        for (keyLiteral, stage) in arms do
          armStmts := armStmts ++ [
            .ifThen (.binary .eq (.ident eventKey) (.literal (.string keyLiteral)))
              (.ofList (← rowUpdateApplyStmts regions tx key regionIndex
                region.name event.name noPayload stage))
          ]
        writes := writes ++ [
          .ifThen (.binary .eq (.ident action) (.literal (.string event.name)))
            (.ofList armStmts)
        ]
  transactionShell checked evaluators runtime name
    #[hostState, context, action, key, value, checkedFlag, eventKey]
    s!"region:{region.name}" writes

private def manifest (moduleName : String) (checked : CheckedComponent Γ) : ComponentManifest :=
  let broadcasts := broadcastRegionNames checked.spec
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
    eventCount := checked.spec.events.size + checked.spec.typedEvents.size +
      checked.spec.keyEvents.size
    hostImports :=
      (if checked.view.events.any (fun mounted =>
          mounted.binding.kind.payload != .none || mounted.binding.kind == .submit) then
        #["./leanrx_dom.mjs", "./leanrx_form_events.mjs"]
      else #["./leanrx_dom.mjs"]) ++
      (if checked.spec.regions.isEmpty then #[] else #["./leanrx_region.mjs"]) ++
      checked.spec.children.map (·.moduleSpecifier)
    features := #["scalar", "events", "transactions", "instrumentation", "trace"] ++
      (if checked.spec.typedEvents.isEmpty then #[] else #["typed-events"]) ++
      (if checked.spec.events.toList.any (·.guard?.isSome) ||
          checked.spec.keyEvents.toList.any (fun event =>
            event.arms.any (·.guard?.isSome)) then
        #["event-guards"]
      else #[]) ++
      (if checked.spec.keyEvents.isEmpty then #[] else #["event-key-branches"]) ++
      (if checked.view.props.isEmpty then #[] else #["controlled-props"]) ++
      (if checked.view.attrSelects.isEmpty then #[] else #["attr-selections"]) ++
      (if checked.spec.children.isEmpty then #[] else #["child-components"]) ++
      (if checked.spec.regions.isEmpty then #[] else #["keyed-regions"]) ++
      (if checked.spec.regions.toList.any regionHasChildRef then
        #["row-child-components"]
      else #[]) ++
      (if checked.spec.regions.toList.any
          (fun region => region.events.toList.any (·.takesPayload)) then
        #["typed-row-events"]
      else #[]) ++
      (if checked.spec.regions.toList.any
          (fun region => region.events.toList.any (·.action.isKeySelect)) then
        #["row-key-branches"]
      else #[]) ++
      (if checked.spec.regions.toList.any
          (fun region => region.events.toList.any (·.action.hasGuard)) then
        #["row-guards"]
      else #[]) ++
      (if checked.spec.regions.toList.any (fun region =>
            region.events.toList.any (·.action.hasTrim) ||
              region.template.hasTrim) ||
          (eventUpdates checked.spec).any (fun update =>
            update.regionBroadcastTargets.any
              (fun entry => entry.2.any (·.2.hasTrim))) ||
          checked.spec.typedEvents.toList.any (fun event =>
            (event.broadcast?.map (fun entry => entry.2.any (·.2.hasTrim))).getD false) then
        #["row-trim"]
      else #[]) ++
      (if checked.spec.regions.toList.any
          (fun region => !(templateBranches region.template).isEmpty) then
        #["row-branches"]
      else #[]) ++
      (if checked.spec.regions.toList.any
          (fun region => rowHasReflect region.template) then
        #["row-reflects"]
      else #[]) ++
      (if checked.spec.regions.toList.any (regionUsesFocus broadcasts) then
        #["row-focus"]
      else #[]) ++
      (if checked.view.regionCounts.isEmpty then #[] else #["row-aggregates"]) ++
      (if checked.view.regionCounts.any (·.label.isSome) then #["count-labels"]
      else #[]) ++
      (if broadcasts.isEmpty && (eventUpdates checked.spec).all
          (fun update => update.regionRemoveIfTargets.isEmpty) then #[]
      else #["region-broadcasts"]) ++
      (if checked.spec.typedEvents.toList.any (·.broadcast?.isSome) then
        #["payload-broadcasts"]
      else #[]) ++
      (if checked.spec.filters.isEmpty then #[] else #["region-filters"]) ++
      (if checked.view.attrSelects.any (fun mounted =>
          mounted.select.hiddenRegion?.isSome) then
        #["region-visibility"]
      else #[]) ++
      (if checked.view.attrSelects.any (fun mounted =>
          mounted.select.hiddenPredicate?.isSome) then
        #["predicate-visibility"]
      else #[]) ++
      (if checked.view.attrSelects.any (fun mounted =>
          mounted.select.checkedRegion?.isSome) then
        #["region-checked"]
      else #[]) ++
      (if checked.spec.props.isEmpty then #[] else #["immutable-props"]) ++
      (if checked.spec.routes.isEmpty then #[] else #["routing"]) ++
      (if checked.spec.persists.isEmpty then #[] else #["persistence"]) }

/-- Lower a checked explicit component to a validated direct-DOM ESM module. -/
def emit (moduleName : String) (checked : CheckedComponent Γ) : Except Error Emitted := do
  let runtime ← runtimeNames
  let inputs := inputSpecs checked.spec.values
  let evaluators ← compileKeyEvents inputs checked.spec.keyEvents.toList
      checked.spec.events.size <|
    ← compileEvents inputs checked.spec.events.toList 0 <|
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
  let broadcasts := broadcastRegionNames checked.spec
  let eventNames := checked.spec.events.toList.map (·.name)
  let typedNames := checked.spec.typedEvents.toList.map (·.name)
  let eventFunctions ← checked.spec.events.toList.zipIdx.mapM fun (event, index) =>
    eventFunction checked evaluators runtime eventNames event index
  let typedEventFunctions ← checked.spec.typedEvents.toList.zipIdx.mapM fun (event, index) =>
    typedEventFunction checked evaluators runtime event index
  let keyEventNames := checked.spec.keyEvents.toList.map (·.name)
  let mut keyFunctions : List Function := []
  let mut keyBodyIndex := checked.spec.events.size
  for (event, index) in checked.spec.keyEvents.toList.zipIdx do
    keyFunctions := keyFunctions ++
      (← keyEventFunctions checked evaluators runtime eventNames event index keyBodyIndex)
    keyBodyIndex := keyBodyIndex + event.arms.length
  let mut routeFunctionList : List Function := []
  for (route, index) in checked.spec.routes.toList.zipIdx do
    let defaultLiteral ← match routeDefault? checked.spec.values route.field.index with
      | some literal => pure literal
      | none => .error {
          code := "LRX-BE-034"
          message := "checked route lost its default literal"
        }
    routeFunctionList := routeFunctionList ++
      (← routeFunctions checked evaluators runtime route index defaultLiteral)
  let hydrateFunctions ← checked.spec.persists.toList.zipIdx.mapM fun (persist, index) =>
    hydrateFunction checked evaluators runtime persist index
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
  let regionBranchFns ← checked.spec.regions.toList.zipIdx.mapM fun (region, index) => do
    (templateBranches region.template).zipIdx.mapM fun (_, branchIndex) => do
      pure (← Ident.checked s!"$lrx_region_{index}_branch_{branchIndex}_t",
        ← Ident.checked s!"$lrx_region_{index}_branch_{branchIndex}_f")
  let regionFunctions ← (checked.spec.regions.toList.zip regionMounts).zip regionBranchFns
    |>.mapM fun ((region, (_, (rowFn, updateFn, disposeFn))), branchFns) => do
      let mut functions : List Function := []
      for (cell, (whenTrueFn, whenFalseFn)) in
          (templateBranches region.template).zip branchFns do
        if let .branch _ _ whenTrue whenFalse _ := cell then
          functions := functions ++ [
            ← regionBranchFunction runtime whenTrue whenTrueFn,
            ← regionBranchFunction runtime whenFalse whenFalseFn]
      pure (functions ++ [← regionRowFunction runtime region branchFns childMounts rowFn,
        ← regionUpdateFunction runtime region (regionRowsMutate broadcasts region)
          branchFns updateFn,
        ← regionDisposeFunction (regionHasChildRef region) disposeFn])
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
  /- The sealed route seed (ADR-0063): mount reads the hash once and folds it
  through the route table into the routed state slot before the derived
  initials and the DOM mount run, so mounted selections and sweeps read the
  routed value; an unknown or empty hash keeps the declared initial. -/
  let mut routeSeed : List Stmt := []
  for (route, routeIndex) in checked.spec.routes.toList.zipIdx do
    let hashConst ← Ident.checked s!"route_hash_{routeIndex}"
    let seedExpr := route.arms.foldr
      (fun (hashLiteral, literal) acc =>
        Expr.conditional (.binary .eq (.ident hashConst) (.literal (.string hashLiteral)))
          (.literal (.string literal)) acc)
      (stateAt state route.field.index)
    routeSeed := routeSeed ++ [
      .const hashConst (call runtime.readHash []),
      .assign (.index (.ident state) (uint route.field.index)) seedExpr
    ]
  let mut mountBody : List Stmt := [
    .const state (.array <| .ofList (initialValues checked.spec.values.toList))
  ] ++ routeSeed ++ derivedInitial ++ dom.statements ++ [
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
  let hasChildRegions := checked.spec.regions.toList.any regionHasChildRef
  let childInventory ← Ident.checked "childInventory"
  unless checked.spec.regions.isEmpty do
    /- The live children inventory (ADR-0075): one shared array seeded with
    the static child mount returns in declaration order; each child-composing
    region's record references it so row mounts push and row disposes splice,
    and the disposer republishes the same array on `children`. -/
    if hasChildRegions then
      mountBody := mountBody ++ [
        .const childInventory (.array (.ofList (dom.childOffs.map Expr.ident)))
      ]
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
      /- Regions with counts carry two extra region-local slots — the count
      text refs and the numeric count cache, both in view order (ADR-0050) —
      and filtered regions one more holding the container element, so the
      commit sweep can navigate to row roots from the context alone
      (ADR-0051). -/
      let counts := checked.view.regionCounts.filter (·.region == region.name)
      let countRefs ← counts.mapM fun count => do
        pure (Expr.ident (← nodeAt dom.nodes count.path))
      let containerRef ← if checked.spec.filters.toList.any (·.region == region.name) then do
          let reference ← match checked.view.regionRefs.find? (·.name == region.name) with
            | some reference => pure reference
            | none => .error {
                code := "LRX-BE-032"
                message := s!"checked region {region.name} was never mounted"
              }
          pure [Expr.ident (← nodeAt dom.nodes reference.path.dropLast)]
        else pure []
      pure <| Expr.array <| .ofList ([
        Expr.ident handle, .array .nil, uint 0, .literal (.boolean false), .array .nil
      ] ++ (if counts.isEmpty then [] else [
        Expr.array (.ofList countRefs),
        /- Label counts cache the mounted `else` string instead of the
        numeric zero, so the first sweep's compare starts from the mounted
        DOM text either way (ADR-0062). -/
        Expr.array (.ofList (counts.map fun count => match count.label with
          | none => uint 0
          | some (_, other) => .literal (.string other)))
      ]) ++ containerRef ++
        (if regionHasChildRef region then [Expr.ident childInventory] else []))
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
    /- The ADR-0060 payload-less toggle binding: a static change binding
    naming a plain event discards the checked payload and mounts through
    the same plain `listen` export a click binding uses — no form-event
    adapter and no new host export. -/
    let plainChange := mounted.binding.kind == .change &&
      (eventNames.idxOf? mounted.binding.eventName).isSome
    match (if plainChange then EventPayload.none else mounted.binding.kind.payload) with
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
        /- A keydown binding may name a key-branched event (ADR-0056); the
        dispatch function receives the same `listenKey` arguments a typed
        event's does. -/
        let handler ← match typedNames.idxOf? mounted.binding.eventName with
          | some value => typedEventName value
          | none =>
              match keyEventNames.idxOf? mounted.binding.eventName with
              | some value => keyEventName value
              | none => .error { code := "LRX-BE-026", message := "checked event binding disappeared" }
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
  /- The hashchange listener (ADR-0063): the first listener whose lifetime is
  not rooted in the mounted subtree, so its removal closure joins the
  listenerDisposers array explicitly. -/
  for (_, routeIndex) in checked.spec.routes.toList.zipIdx do
    let off ← Ident.checked s!"route_off_{routeIndex}"
    mountBody := mountBody ++ [.const off <| call runtime.listenHash [
      .ident state, .ident context, .ident (← routeDispatchName routeIndex)
    ]]
    disposers := disposers ++ [.ident off]
  /- Mount hydration (ADR-0063): one ordinary transaction per persisted
  region, run once after the listeners are wired — the shared commit sweep
  mounts the parsed rows and settles every count, visibility, and filter
  slot. -/
  for (_, persistIndex) in checked.spec.persists.toList.zipIdx do
    mountBody := mountBody ++ [.expr <| call (← hydrateName persistIndex) [
      .ident context, .literal .null
    ]]
  for (_, handle) in dom.regionHandles do
    disposers := disposers ++ [.index (.ident handle) (.literal (.string "dispose"))]
  mountBody := mountBody ++ [
    .const disposer <| call runtime.makeDisposer ([
      .ident root, .array (.ofList disposers), .ident tx
    ] ++ (if dom.regionHandles.isEmpty then []
      else [.array (.ofList (dom.regionHandles.map fun (_, handle) => Expr.ident handle))]))
  ] ++ (if hasChildRegions then [
    /- Live child reachability (ADR-0075): the disposer republishes the
    shared inventory array — static child mount returns in declaration order,
    then the mounted rows' children in mount order, spliced as rows leave.
    The array identity is fixed at mount, so the ADR-0066 reachability
    contract is unchanged; only its contents became live. -/
    Stmt.assign (.index (.ident disposer) (.literal (.string "children")))
      (.ident childInventory)
  ] else if dom.childOffs.isEmpty then [] else [
    /- Child reachability (ADR-0066): the parent disposer republishes each
    child's mount return in declaration order, so child instrumentation stays
    reachable after the parent's dispose splices its listener list. The host
    disposer surface is unchanged; only child-composed modules emit this. -/
    Stmt.assign (.index (.ident disposer) (.literal (.string "children")))
      (.array (.ofList (dom.childOffs.map Expr.ident)))
  ]) ++ [
    .return (.ident disposer)
  ]
  let mount ← Ident.checked "mount"
  /- An ADR-0060 payload-less change binding mounts through the plain
  `listen` export, so it never demands the value adapter. -/
  let usesValueListener := checked.view.events.any
    fun mounted => mounted.binding.kind.payload == .value &&
      !(mounted.binding.kind == .change &&
        eventNames.contains mounted.binding.eventName)
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
  let usesRowUpdates := checked.spec.regions.toList.any (regionRowsMutate broadcasts)
  let usesBranches := checked.spec.regions.toList.any
    fun region => !(templateBranches region.template).isEmpty
  let usesBranchReplace := checked.spec.regions.toList.any
    fun region => regionRowsMutate broadcasts region &&
      !(templateBranches region.template).isEmpty
  let usesReflects := checked.spec.regions.toList.any
    fun region => rowHasReflect region.template
  let usesFocus := checked.spec.regions.toList.any (regionUsesFocus broadcasts)
  let usesFilters := !checked.spec.filters.isEmpty
  let usesRouting := !checked.spec.routes.isEmpty
  let usesPersistence := !checked.spec.persists.isEmpty
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
                | .disabledSelect .. | .hiddenIfEmpty .. | .checkedIfEmpty .. => true
                | _ => false) && !usesBranches && !usesReflects &&
              !usesFilters then #[]
            else #[(runtime.setProperty, runtime.setProperty)]) ++
          (if checked.spec.regions.isEmpty then #[]
            else #[(runtime.setKey, runtime.setKey)]) ++
          (if usesRowUpdates || usesFilters then
            #[(runtime.childAt, runtime.childAt)]
          else #[]) ++
          (if usesDelegation then
            #[(runtime.listenDelegatedCells, runtime.listenDelegatedCells)]
          else #[]) ++
          (if usesFocus then #[(runtime.focus, runtime.focus)] else #[]) ++
          /- Both ADR-0063 vocabularies are reachability-gated (the ADR-0048
          arm shape): a component with no route/persist item emits a
          byte-identical module and the benchmark bundle never names the
          exports, so the compactor prunes them before renaming. -/
          (if usesRouting then
            #[(runtime.readHash, runtime.readHash),
              (runtime.listenHash, runtime.listenHash),
              (runtime.writeHash, runtime.writeHash)]
          else #[]) ++
          (if usesPersistence then
            #[(runtime.storageGet, runtime.storageGet),
              (runtime.storageSet, runtime.storageSet)]
          else #[]) }
      ] ++ (if formImportNames.isEmpty then #[] else #[
        { source := "./leanrx_form_events.mjs", names := formImportNames }
      ]) ++ (if checked.spec.regions.isEmpty then #[] else #[
        { source := "./leanrx_region.mjs", names := #[
            (runtime.createKeyedRegion, runtime.createKeyedRegion)
          ] ++ (if usesBranchReplace then #[(runtime.detach, runtime.detach)]
            else #[]) }
      ]) ++ childImports.toArray
      declarations := (evaluators.declarations ++ eventFunctions.map Decl.function ++
        typedEventFunctions.map Decl.function ++ keyFunctions.map Decl.function ++
        routeFunctionList.map Decl.function ++ hydrateFunctions.map Decl.function ++
        regionFunctionDecls.map Decl.function ++ [
        Decl.function { name := mount, params := mountParams, body := mountBody.toArray }
      ]).toArray
      exports := #[{ localName := mount, exportName := mount }] }
  module.validate
  pure { module, manifest := manifest moduleName checked }

end LeanRx.Backend.Component
