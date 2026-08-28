import LeanRx.Graph.Topological
import LeanRx.Component.Dependent
import LeanRx.View.Model

namespace LeanRx

/-- One state/derived declaration, retaining all evidence needed by graph and backend phases. -/
inductive ValueSpec (Γ : Schema) where
  | source (runtime : RuntimeRep α) (equality : @RuntimeEq α runtime) (field : Field Γ α)
      (initial : ScalarLiteral α) (span : SourceSpan := .generated)
  | derived (runtime : RuntimeRep α) (equality : @RuntimeEq α runtime) (field : Field Γ α)
      (value : RxExpr Γ deps α) (span : SourceSpan := .generated)

namespace ValueSpec

def state [runtime : RuntimeRep α] [equality : RuntimeEq α]
    (field : Field Γ α) (initial : ScalarLiteral α)
    (span : SourceSpan := .generated) : ValueSpec Γ :=
  .source runtime equality field initial span

def computed [runtime : RuntimeRep α] [equality : RuntimeEq α]
    (field : Field Γ α) (value : RxExpr Γ deps α)
    (span : SourceSpan := .generated) : ValueSpec Γ :=
  .derived runtime equality field value span

def fieldIndex : ValueSpec Γ → Nat
  | .source _ _ field _ _ | .derived _ _ field _ _ => field.index

def name : ValueSpec Γ → String
  | .source _ _ field _ _ | .derived _ _ field _ _ => field.name

def valueType : ValueSpec Γ → RuntimeTypeId
  | .source runtime _ _ _ _ | .derived runtime _ _ _ _ => runtime.runtimeType.id

def isSource : ValueSpec Γ → Bool
  | .source .. => true
  | .derived .. => false

def dependencyIds : ValueSpec Γ → List Nat
  | .source .. => []
  | .derived _ _ _ value _ => value.dependencies.ids

def evaluatorName : ValueSpec Γ → String
  | .source .. => ""
  | .derived _ _ _ value _ => "rx:" ++ value.debug

def span : ValueSpec Γ → SourceSpan
  | .source _ _ _ _ span | .derived _ _ _ _ span => span

def withSpan (value : ValueSpec Γ) (span : SourceSpan) : ValueSpec Γ :=
  match value with
  | .source runtime equality field initial _ => .source runtime equality field initial span
  | .derived runtime equality field expression _ =>
      .derived runtime equality field expression span

end ValueSpec

/-- One appended row field value, evaluated against component state at event
time (ADR-0041). Rows are `String` tuples in stage 1. -/
structure RowValue (Γ : Schema) where
  deps : DepSet Γ
  value : RxExpr Γ deps String

def RowValue.of {Γ : Schema} {d : DepSet Γ} (value : RxExpr Γ d String) : RowValue Γ :=
  ⟨d, value⟩

/-- Pure transaction-local update program. M4 validates writes target sources;
`regionAppend` pushes one row (fresh region-owned key, evaluated field values)
onto a declared keyed region (ADR-0041); `regionBroadcast` writes sealed row
expressions into every row of a declared region simultaneously, and
`regionRemoveIf` removes every row satisfying the sealed field predicate —
one projected field against one literal (ADR-0064) —
both re-render through the keyed reconcile with retained-row identity
preserved (ADR-0050). -/
inductive Update (Γ : Schema) where
  | set (field : Field Γ α) (value : RxExpr Γ deps α) (span : SourceSpan := .generated)
  | dispatch (eventName : String) (span : SourceSpan := .generated)
  | regionAppend (region : String) (values : List (RowValue Γ))
      (span : SourceSpan := .generated)
  | regionBroadcast (region : String) (assignments : List (Nat × RowExpr))
      (span : SourceSpan := .generated)
  | regionRemoveIf (region : String) (predicate : FieldPredicate)
      (span : SourceSpan := .generated)
  | sequence (first second : Update Γ)

namespace Update

def directWriteTargets : Update Γ → List Nat
  | .set field _ _ => [field.index]
  | .dispatch .. | .regionAppend .. | .regionBroadcast .. | .regionRemoveIf .. => []
  | .sequence first second => first.directWriteTargets ++ second.directWriteTargets

def directReadDependencies : Update Γ → List Nat
  | .set _ value _ => value.dependencies.ids
  | .dispatch .. => []
  | .regionAppend _ values _ => values.flatMap (·.deps.ids)
  /- Broadcast right-hand sides and removal predicates are sealed row
  expressions: they read row fields only, never component state (ADR-0050). -/
  | .regionBroadcast .. | .regionRemoveIf .. => []
  | .sequence first second => first.directReadDependencies ++ second.directReadDependencies

def dispatchTargets : Update Γ → List String
  | .set .. | .regionAppend .. | .regionBroadcast .. | .regionRemoveIf .. => []
  | .dispatch eventName _ => [eventName]
  | .sequence first second => first.dispatchTargets ++ second.dispatchTargets

/-- Region append targets with their field arity, for region-table checks. -/
def regionAppendTargets : Update Γ → List (String × Nat)
  | .set .. | .dispatch .. | .regionBroadcast .. | .regionRemoveIf .. => []
  | .regionAppend region values _ => [(region, values.length)]
  | .sequence first second => first.regionAppendTargets ++ second.regionAppendTargets

/-- Region broadcast targets with their assignments, for region-table checks
and the mutable-rows decision (ADR-0050). -/
def regionBroadcastTargets : Update Γ → List (String × List (Nat × RowExpr))
  | .set .. | .dispatch .. | .regionAppend .. | .regionRemoveIf .. => []
  | .regionBroadcast region assignments _ => [(region, assignments)]
  | .sequence first second => first.regionBroadcastTargets ++ second.regionBroadcastTargets

/-- Region removal targets with their sealed predicate, for region-table
checks (ADR-0050/0064). -/
def regionRemoveIfTargets : Update Γ → List (String × FieldPredicate)
  | .set .. | .dispatch .. | .regionAppend .. | .regionBroadcast .. => []
  | .regionRemoveIf region predicate _ => [(region, predicate)]
  | .sequence first second => first.regionRemoveIfTargets ++ second.regionRemoveIfTargets

end Update

/-- The sealed skip-if guard of one component event (ADR-0055): when the
subject — one `String` state field, raw or behind the one ADR-0054/0055 trim
unary — equals the empty literal, the whole event is a no-op: no write, no
append, no dispatch, no trace, before the transaction even begins. The empty
literal is the entire predicate language: no other literal, subject
expression, or hit action is representable — TodoMVC's add contract, not a
conditional event vocabulary. The typed `Field Γ String` makes a cross-typed
or out-of-bounds subject unrepresentable. -/
structure EventGuard (Γ : Schema) where
  field : Field Γ String
  trimmed : Bool
  span : SourceSpan := .generated

structure EventSpec (Γ : Schema) where
  name : String
  update : Update Γ
  span : SourceSpan := .generated
  guard? : Option (EventGuard Γ) := none

def EventSpec.withSpan (event : EventSpec Γ) (span : SourceSpan) : EventSpec Γ :=
  { event with span }

/-- The state reads of one event's skip guard (ADR-0055): the guard subject
is a real read of its `String` source at dispatch time. -/
def EventSpec.guardReads (event : EventSpec Γ) : List Nat :=
  match event.guard? with
  | some guard => [guard.field.index]
  | none => []

/-- One arm of a key-branched component event (ADR-0056): one sealed key
literal selecting an ordinary component step sequence, optionally behind the
ADR-0055 skip guard. The discriminant is consumed by the selection — the
component update language has no payload reference, so an arm body cannot
observe the key beyond the literal that matched it. -/
structure KeyEventArm (Γ : Schema) where
  key : String
  update : Update Γ
  span : SourceSpan := .generated
  guard? : Option (EventGuard Γ) := none

/-- The state reads of one arm's skip guard (ADR-0055/0056). -/
def KeyEventArm.guardReads (arm : KeyEventArm Γ) : List Nat :=
  match arm.guard? with
  | some guard => [guard.field.index]
  | none => []

/-- One key-branched component event (ADR-0056): the ADR-0052 sealed key
selection lifted to component scope. The declared `String` parameter is the
discriminant, named in the head and compared implicitly by each arm; key
literals come from the sealed Enter/Escape set; a key outside the table is a
whole-event no-op — the generated dispatch function returns before any
transaction exists. -/
structure KeyEventSpec (Γ : Schema) where
  name : String
  parameterName : String
  arms : List (KeyEventArm Γ)
  span : SourceSpan := .generated

structure EventSummary where
  name : String
  directWrites : List Nat
  directReads : List Nat
  dispatchedEvents : List String
  effectiveWrites : List Nat
  effectiveReads : List Nat
deriving Repr, BEq

inductive SurfaceRole where
  | state | derived | event
deriving Repr, BEq, DecidableEq

def SurfaceRole.name : SurfaceRole → String
  | .state => "state"
  | .derived => "derived"
  | .event => "event"

structure SurfaceDecl where
  role : SurfaceRole
  name : String
  span : SourceSpan
deriving Repr, BEq

def SurfaceDecl.debug (value : SurfaceDecl) : String :=
  value.role.name ++ ":" ++ value.name

/-- One statically nested child component (ADR-0039). The parent's emitted
module imports the child's `mount` export from `moduleSpecifier`; the child
keeps its own independent state, schema, and events. -/
structure ChildComponent where
  name : String
  moduleSpecifier : String
  span : SourceSpan := .generated
deriving Repr, BEq

def ChildComponent.of (name : String) (span : SourceSpan := .generated) : ChildComponent :=
  { name, moduleSpecifier := s!"./{name}.mjs", span }

/-- One declared immutable component input (ADR-0042). The value arrives from
the parent through the mount ABI (`mount(target, props)`); updates cannot
target it and stage 1 fixes the payload type to `String`. -/
structure PropSpec where
  name : String
  span : SourceSpan := .generated
deriving Repr, BEq

/-- One sealed region filter view (ADR-0051): a correspondence from distinct
`String` state literals of one component value to row-field equality
predicates, selecting which of a keyed region's rows are displayed. Each arm
is `(stateLiteral, predicate)` — the sealed single-field-literal equality
(ADR-0064): while the filter field equals
`stateLiteral`, exactly the rows satisfying the predicate
stay visible; a state value outside the table carries no predicate and shows
every row. The commit sweep records the selection as each row root's
`hidden` property — rows never mount or dispose on a filter change, so row
identity is untouched by construction. The typed `Field Γ String` makes a
cross-typed selector unrepresentable. -/
structure RegionFilter (Γ : Schema) where
  region : String
  field : Field Γ String
  arms : List (String × FieldPredicate)
  span : SourceSpan := .generated

/-- One sealed route view (ADR-0063): a one-to-one correspondence from sealed
`#/`-shaped hash literals to existing state literals of the routed field — the
one component state field that already carries a declared ADR-0051 region
filter. Mount seeds the field through `readHash` (an unknown or empty hash
falls to the declared default), `hashchange` dispatches the same set-field
transaction the filter buttons dispatch, and `writeHash` rides the set-field
commit flip-only behind the field's changed flag. Exactly one arm must map the
declared default literal, so the unknown-hash fallback is a table entry, not a
separate path. The typed `Field Γ String` makes a cross-typed selector
unrepresentable. -/
structure RouteSpec (Γ : Schema) where
  field : Field Γ String
  arms : List (String × String)
  span : SourceSpan := .generated

/-- One sealed persistence declaration (ADR-0063): one declared keyed region's
row table persisted under one sealed literal storage key — one key per
component in stage 1. Mount hydrates through the existing append path from one
`storageGet` (a missing, empty, or wrong-arity value mounts the region empty,
fail closed), and one `storageSet` rides the region-touch sweep per
region-touching transaction; serialization lives in generated code, so the
host moves strings only. -/
structure PersistSpec where
  region : String
  key : String
  span : SourceSpan := .generated
deriving Repr, BEq

structure ComponentSpec (Γ : Schema) where
  name : String
  values : Array (ValueSpec Γ)
  events : Array (EventSpec Γ)
  typedEvents : Array (AnyTypedEvent Γ) := #[]
  keyEvents : Array (KeyEventSpec Γ) := #[]
  view : View Γ
  surface : Array SurfaceDecl := #[]
  children : Array ChildComponent := #[]
  regions : Array RegionSpec := #[]
  filters : Array (RegionFilter Γ) := #[]
  routes : Array (RouteSpec Γ) := #[]
  persists : Array PersistSpec := #[]
  props : Array PropSpec := #[]
  span : SourceSpan := .generated

/-- Declared immutable prop names in declaration order; the parent-side jsx
elaboration validates child prop bindings against this list (ADR-0042). -/
def ComponentSpec.propNames (spec : ComponentSpec Γ) : List String :=
  spec.props.toList.map (·.name)

structure ComponentError where
  code : String
  message : String
  path : Array String := #[]
  spans : Array SourceSpan := #[]
deriving Repr, BEq

namespace ComponentError

private def spanLine (span : SourceSpan) : String :=
  if span.file.isEmpty then "<generated>"
  else s!"{span.file}:{span.start.line}:{span.start.column}"

def render (error : ComponentError) : String :=
  let path := if error.path.isEmpty then ""
    else "\n  path: " ++ String.intercalate " → " error.path.toList
  let spans := if error.spans.isEmpty then ""
    else "\n  declarations: " ++ String.intercalate ", "
      (error.spans.toList.map spanLine)
  s!"error[{error.code}]: {error.message}" ++ path ++ spans

end ComponentError

structure CheckedComponent (Γ : Schema) where
  private mk ::
  spec : ComponentSpec Γ
  graph : PlannedGraph
  sourceCount : Nat
  eventSummaries : Array EventSummary
  view : ViewSplit Γ

namespace ComponentSpec

private def duplicate? (values : List String) : Bool :=
  match values with
  | [] => false
  | head :: tail => tail.contains head || duplicate? tail

private def sourceCount (values : List (ValueSpec Γ)) : Nat :=
  match values with
  | [] => 0
  | head :: tail => if head.isSource then sourceCount tail + 1 else 0

/-- The shared bounds rule of every projected-row-field position (ADR-0064):
one throw shape for the nineteen near-identical out-of-bounds checks, each
call site keeping its error code, subject phrasing, path, and spans
verbatim. -/
private def checkFieldBound (code : String) (subject : String) (field : Nat)
    (region : RegionSpec) (spans : Array SourceSpan)
    (path : Array String := #[]) : Except ComponentError Unit := do
  unless field < region.fields.size do
    throw {
      code
      message :=
        s!"{subject} field {field} outside region {region.name}'s {region.fields.size} field(s)"
      path, spans
    }

private def refsFor (values : Array (ValueSpec Γ)) (ids : List Nat) :
    Except ComponentError (Array TypedNodeRef) := do
  let refs ← ids.mapM fun id =>
    match values[id]? with
    | some value => pure { id := ⟨id⟩, valueType := value.valueType }
    | none => throw {
        code := "LRX-TYPE-106"
        message := s!"expression dependency {id} is outside the component value table"
      }
  pure refs.toArray

private def valueNodes (values : Array (ValueSpec Γ)) :
    Except ComponentError (Array NodeSpec) := do
  let nodes ← values.toList.mapM fun value =>
    if value.isSource then
      pure <| NodeSpec.source value.name value.valueType value.span
    else do
      pure <| NodeSpec.derived value.name value.valueType
        (← refsFor values value.dependencyIds) value.evaluatorName value.span
  pure nodes.toArray

private def sinkNodes (values : Array (ValueSpec Γ))
    (sinks : List (TextSink Γ)) : Except ComponentError (Array NodeSpec) := do
  let nodes ← sinks.mapM fun sink => do
    pure <| NodeSpec.sink sink.name .string
      (← refsFor values sink.value.dependencies.ids) ("rx:" ++ sink.value.debug) sink.span
  pure nodes.toArray

private def propNodes (values : Array (ValueSpec Γ))
    (props : List (MountedProp Γ)) : Except ComponentError (Array NodeSpec) := do
  let nodes ← props.zipIdx.mapM fun (prop, index) => do
    pure <| NodeSpec.sink s!"prop:{index}:{prop.binding.name}" prop.binding.valueType
      (← refsFor values prop.binding.dependencyIds) prop.binding.debug prop.binding.span
  pure nodes.toArray

private def attrSelectNodes (values : Array (ValueSpec Γ))
    (selects : List (MountedAttrSelect Γ)) : Except ComponentError (Array NodeSpec) := do
  /- A `hiddenIfEmpty` or `checkedIfEmpty` selection reads no state field:
  like the ADR-0050 count texts it is region-driven, so it joins the
  region-touch sweep instead of the planned graph (ADR-0058/0060). The
  field selections keep their global selection indices, matching the
  emitted `attr:{index}` labels. -/
  let nodes ← selects.zipIdx.filterMapM fun (mounted, index) => do
    match mounted.select.fieldIndex? with
    | none => pure none
    | some fieldIndex =>
        pure <| some <| NodeSpec.sink s!"attr:{index}:{mounted.select.name}"
          mounted.select.valueType (← refsFor values [fieldIndex])
          mounted.select.debug mounted.select.span
  pure nodes.toArray

/- Region filter views join the planned graph as sink nodes over their state
field, beside the ADR-0045 selection sinks (ADR-0051). -/
private def filterNodes (values : Array (ValueSpec Γ))
    (filters : Array (RegionFilter Γ)) : Except ComponentError (Array NodeSpec) := do
  let nodes ← filters.toList.zipIdx.mapM fun (filter, index) => do
    pure <| NodeSpec.sink s!"filter:{index}:{filter.region}" .string
      (← refsFor values [filter.field.index])
      s!"filter:{filter.region}:{filter.field.index}" filter.span
  pure nodes.toArray

private def validateValues (spec : ComponentSpec Γ) : Except ComponentError Nat := do
  if spec.values.isEmpty then
    throw { code := "LRX-TYPE-101", message := "component must declare at least one value" }
  unless spec.values.size == Γ.size do
    throw {
      code := "LRX-TYPE-102"
      message := "component value declarations must align exactly with its schema"
      spans := #[spec.span]
    }
  for index in List.range spec.values.size do
    match spec.values[index]? with
    | none =>
        throw { code := "LRX-TYPE-102", message := "component value table changed during validation" }
    | some value =>
        unless value.fieldIndex == index do
          throw {
            code := "LRX-TYPE-103"
            message := s!"component value at position {index} uses field {value.fieldIndex}"
            spans := #[value.span]
          }
  if duplicate? (spec.values.toList.map ValueSpec.name) then
    throw { code := "LRX-TYPE-104", message := "component value names must be unique" }
  let count := sourceCount spec.values.toList
  unless spec.values.toList.take count |>.all ValueSpec.isSource do
    throw { code := "LRX-TYPE-105", message := "component sources must form a leading prefix" }
  unless spec.values.toList.drop count |>.all (fun value => ¬value.isSource) do
    throw { code := "LRX-TYPE-105", message := "component sources must form a leading prefix" }
  pure count

private def actualSurface (spec : ComponentSpec Γ) : Array SurfaceDecl :=
  spec.values.map (fun value => {
    role := if value.isSource then .state else .derived
    name := value.name
    span := value.span
  }) ++ spec.events.map (fun event => {
    role := .event
    name := event.name
    span := event.span
  }) ++ spec.typedEvents.map (fun event => {
    role := .event
    name := event.name
    span := event.span
  }) ++ spec.keyEvents.map (fun event => {
    role := .event
    name := event.name
    span := event.span
  })

private def validateSurface (spec : ComponentSpec Γ) : Except ComponentError Unit := do
  if spec.surface.isEmpty then return
  let actual := actualSurface spec
  unless spec.surface.size == actual.size do
    throw {
      code := "LRX-ELAB-103"
      message := "surface declarations must align exactly with component values and events"
      spans := spec.surface.map (·.span)
    }
  for pair in spec.surface.toList.zip actual.toList do
    let declared := pair.1
    let value := pair.2
    unless declared.role == value.role && declared.name == value.name do
      throw {
        code := "LRX-ELAB-103"
        message := s!"surface declaration {declared.debug} does not match {value.debug}"
        path := #[declared.debug, value.debug]
        spans := #[declared.span, value.span]
      }

/-- Payload classes one typed event declaration can satisfy: `String` events
serve `value`/`key` bindings, `Bool` events — the ADR-0061 payload broadcast
included — serve `checked` bindings. -/
private def acceptsPayload : AnyTypedEvent Γ → EventPayload → Bool
  | .string _, .value | .string _, .key => true
  | .bool _, .checked | .boolBroadcast _, .checked => true
  | _, _ => false

/- Whether one element's static attributes carry `type="checkbox"` — the
only elements a delegated `change` binding or a `checked` reflection may sit
on (ADR-0049): the `checked` payload and property originate from checkbox
inputs alone. The ADR-0060 static-scope rules read the same predicate: the
toggle-all checked selection and the payload-less change binding both
demand a `type="checkbox"` input. -/
private def isCheckboxAttrs (attrs : List StaticAttr) : Bool :=
  attrs.any (· == .inputType .checkbox)

/- The element mounted at one child-index path of the view, for rules that
need the bound element's tag and static attributes (ADR-0060). -/
mutual
private def viewElementAt? : View Γ → List Nat →
    Option (HtmlTag × List StaticAttr)
  | .element tag attrs _ _ _ _ _, [] => some (tag, attrs)
  | .element _ _ _ children _ _ _, index :: rest =>
      viewChildElementAt? children index rest
  | _, _ => none

private def viewChildElementAt? : ViewChildren Γ → Nat → List Nat →
    Option (HtmlTag × List StaticAttr)
  | .nil, _, _ => none
  | .cons head _, 0, rest => viewElementAt? head rest
  | .cons _ tail, index + 1, rest => viewChildElementAt? tail index rest
end

private def validateEvents (spec : ComponentSpec Γ) (sourceCount : Nat)
    (split : ViewSplit Γ) : Except ComponentError Unit := do
  let names := spec.events.toList.map (·.name)
  let typedNames := spec.typedEvents.toList.map (·.name)
  let keyNames := spec.keyEvents.toList.map (·.name)
  if (names ++ typedNames ++ keyNames).any String.isEmpty ||
      duplicate? (names ++ typedNames ++ keyNames) then
    throw { code := "LRX-ELAB-102", message := "component event names must be nonempty and unique" }
  for event in spec.typedEvents do
    if let some targetIndex := event.targetIndex? then
      unless targetIndex < sourceCount do
        throw {
          code := "LRX-TYPE-107"
          message := s!"event {event.name} writes non-source value {targetIndex}"
          spans := #[event.span]
        }
  /- Payload broadcast events (ADR-0061): the body is exactly one region
  broadcast into a declared region — nonempty simultaneous writes over
  distinct in-bounds targets, the ADR-0050 obligations — whose right-hand
  sides are sealed payload-free row expressions or the bare payload
  reference. The payload must be written at least once (a payload the body
  never writes is a plain broadcast wearing a parameter), and it stands
  alone: trim, concatenation, and every other composition over the payload
  is rejected. -/
  for event in spec.typedEvents do
    if let .boolBroadcast broadcast := event then
      match spec.regions.toList.find? (·.name == broadcast.region) with
      | none =>
          throw {
            code := "LRX-TYPE-116"
            message := s!"event {broadcast.name} broadcasts its payload to unknown region {broadcast.region}"
            path := #[broadcast.name, broadcast.region]
            spans := #[broadcast.span]
          }
      | some region =>
          if broadcast.assignments.isEmpty then
            throw {
              code := "LRX-TYPE-116"
              message := s!"event {broadcast.name} broadcasts no field to region {broadcast.region}"
              path := #[broadcast.name, broadcast.region]
              spans := #[broadcast.span]
            }
          if duplicate? (broadcast.assignments.map (toString ·.1)) then
            throw {
              code := "LRX-TYPE-116"
              message := s!"event {broadcast.name} broadcasts one field of region {broadcast.region} twice"
              path := #[broadcast.name, broadcast.region]
              spans := #[broadcast.span]
            }
          for (fieldIndex, value) in broadcast.assignments do
            checkFieldBound "LRX-TYPE-116" s!"event {broadcast.name} broadcasts"
              fieldIndex region #[broadcast.span, region.span]
              #[broadcast.name, broadcast.region]
            unless value == .payload || !value.hasPayload do
              throw {
                code := "LRX-TYPE-116"
                message := s!"event {broadcast.name} composes its payload; the broadcast payload stands alone on a set right-hand side"
                path := #[broadcast.name, broadcast.region]
                spans := #[broadcast.span]
              }
            for field in value.fieldRefs do
              checkFieldBound "LRX-TYPE-116"
                s!"event {broadcast.name} broadcasts a read of" field region
                #[broadcast.span, region.span] #[broadcast.name, broadcast.region]
          unless broadcast.assignments.any (·.2 == .payload) do
            throw {
              code := "LRX-TYPE-116"
              message := s!"event {broadcast.name} never writes its payload; a payload broadcast assigns the bare parameter to at least one field of region {broadcast.region}"
              path := #[broadcast.name, broadcast.region]
              spans := #[broadcast.span]
            }
  /- Key-branched component events (ADR-0056): the arm table is sealed —
  nonempty, each literal drawn from the sealed Enter/Escape key set and
  appearing at most once — and each arm body then carries exactly the
  obligations of an ordinary component event, skip guard included, through
  the shared body loop below. -/
  for event in spec.keyEvents do
    if event.arms.isEmpty then
      throw {
        code := "LRX-TYPE-115"
        message := s!"key-branched event {event.name} declares no arms"
        spans := #[event.span]
      }
    for arm in event.arms do
      unless RowAction.keyLiterals.contains arm.key do
        throw {
          code := "LRX-TYPE-115"
          message := s!"key-branched event {event.name} selects on key {arm.key} outside the sealed Enter/Escape set"
          path := #[event.name, arm.key]
          spans := #[arm.span]
        }
    if duplicate? (event.arms.map (·.key)) then
      throw {
        code := "LRX-TYPE-115"
        message := s!"key-branched event {event.name} selects one key twice"
        spans := #[event.span]
      }
  let bodies : List (String × Update Γ × Option (EventGuard Γ) × SourceSpan) :=
    spec.events.toList.map (fun event =>
      (event.name, event.update, event.guard?, event.span)) ++
    spec.keyEvents.toList.flatMap (fun event => event.arms.map fun arm =>
      (event.name, arm.update, arm.guard?, arm.span))
  for (eventName, update, guard?, span) in bodies do
    for target in update.directWriteTargets do
      unless target < sourceCount do
        throw {
          code := "LRX-TYPE-107"
          message := s!"event {eventName} writes non-source value {target}"
          spans := #[span]
        }
    for dependency in update.directReadDependencies do
      unless dependency < sourceCount do
        throw {
          code := "LRX-TYPE-108"
          message := s!"event {eventName} reads derived value {dependency}; derived reads require a transaction barrier"
          spans := #[span]
        }
    /- The sealed skip guard (ADR-0055) reads its subject before the
    transaction begins, so the subject must be a source: a derived value is
    not yet recomputed at dispatch time. The `Field Γ String` type already
    seals the payload type and the bounds. -/
    if let some guard := guard? then
      unless guard.field.index < sourceCount do
        throw {
          code := "LRX-TYPE-114"
          message := s!"event {eventName} guards on derived value {guard.field.index}; a skip guard reads one String state field"
          spans := #[span, guard.span]
        }
    for target in update.dispatchTargets do
      unless names.contains target do
        throw {
          code := "LRX-ELAB-106"
          message := s!"event {eventName} dispatches unknown event {target}"
          path := #[eventName, target]
          spans := #[span]
        }
  unless spec.events.isEmpty do
    let dispatchNodes := spec.events.map fun event =>
      let deps := event.update.dispatchTargets.eraseDups.filterMap fun target =>
        names.idxOf? target |>.map fun id => { id := ⟨id⟩, valueType := .bool }
      NodeSpec.derived event.name .bool deps.toArray "nested-dispatch" event.span
    match Graph.plan dispatchNodes with
    | .ok _ => pure ()
    | .error error =>
        throw {
          code := "LRX-ELAB-107"
          message := "nested event dispatch must be acyclic"
          path := error.path
          spans := error.spans
        }
  for (eventName, update, _, span) in bodies do
    for (target, arity) in update.regionAppendTargets do
      match spec.regions.toList.find? (·.name == target) with
      | none =>
          throw {
            code := "LRX-TYPE-109"
            message := s!"event {eventName} appends to unknown region {target}"
            path := #[eventName, target]
            spans := #[span]
          }
      | some region =>
          unless arity == region.fields.size do
            throw {
              code := "LRX-TYPE-110"
              message := s!"event {eventName} appends {arity} field(s) to region {target}, which declares {region.fields.size}"
              path := #[eventName, target]
              spans := #[span, region.span]
            }
  /- Region broadcasts and removals (ADR-0050): the target region must be
  declared; broadcast assignments are nonempty simultaneous writes over
  distinct in-bounds targets, reading only in-bounds row fields and never a
  payload (no row event is dispatching); removal predicates project one
  in-bounds row field. -/
  for (eventName, update, _, span) in bodies do
    for (target, assignments) in update.regionBroadcastTargets do
      match spec.regions.toList.find? (·.name == target) with
      | none =>
          throw {
            code := "LRX-TYPE-111"
            message := s!"event {eventName} broadcasts to unknown region {target}"
            path := #[eventName, target]
            spans := #[span]
          }
      | some region =>
          if assignments.isEmpty then
            throw {
              code := "LRX-TYPE-111"
              message := s!"event {eventName} broadcasts no field to region {target}"
              path := #[eventName, target]
              spans := #[span]
            }
          if duplicate? (assignments.map (toString ·.1)) then
            throw {
              code := "LRX-TYPE-111"
              message := s!"event {eventName} broadcasts one field of region {target} twice"
              path := #[eventName, target]
              spans := #[span]
            }
          for (fieldIndex, value) in assignments do
            checkFieldBound "LRX-TYPE-111" s!"event {eventName} broadcasts"
              fieldIndex region #[span, region.span] #[eventName, target]
            if value.hasPayload then
              throw {
                code := "LRX-TYPE-111"
                message := s!"event {eventName} broadcasts a payload reference to region {target}; broadcasts dispatch no row event"
                path := #[eventName, target]
                spans := #[span]
              }
            for field in value.fieldRefs do
              checkFieldBound "LRX-TYPE-111"
                s!"event {eventName} broadcasts a read of" field region
                #[span, region.span] #[eventName, target]
    for (target, predicate) in update.regionRemoveIfTargets do
      match spec.regions.toList.find? (·.name == target) with
      | none =>
          throw {
            code := "LRX-TYPE-112"
            message := s!"event {eventName} removes rows from unknown region {target}"
            path := #[eventName, target]
            spans := #[span]
          }
      | some region =>
          for fieldIndex in predicate.subject.fieldRefs do
            checkFieldBound "LRX-TYPE-112" s!"event {eventName} removes rows by"
              fieldIndex region #[span, region.span] #[eventName, target]
  for mounted in split.events do
    if mounted.binding.kind.payload == .none then
      unless names.contains mounted.binding.eventName do
        throw {
          code := "LRX-VIEW-006"
          message := s!"view references unknown event {mounted.binding.eventName}"
          spans := #[mounted.binding.span]
        }
    else if mounted.binding.kind == .change &&
        names.contains mounted.binding.eventName then
      /- The payload-less toggle binding (ADR-0060): a static `change`
      binding may name a plain component event — the toggle-all checkbox
      fires it whole, discarding the checked payload — but only from a
      `type="checkbox"` input, the ADR-0049 origin rule in static scope.
      Every other change binding still resolves a typed value event. -/
      match viewElementAt? spec.view mounted.path with
      | some (.input, attrs) =>
          unless isCheckboxAttrs attrs do
            throw {
              code := "LRX-VIEW-043"
              message := s!"a change binding to plain event {mounted.binding.eventName} requires a type=\"checkbox\" input element"
              spans := #[mounted.binding.span]
            }
      | _ =>
          throw {
            code := "LRX-VIEW-043"
            message := s!"a change binding to plain event {mounted.binding.eventName} requires a type=\"checkbox\" input element"
            spans := #[mounted.binding.span]
          }
    else
      match spec.typedEvents.toList.find? (·.name == mounted.binding.eventName) with
      | none =>
          /- A key-branched component event (ADR-0056) compares the delegated
          `key` payload, so only a keydown binding can serve it — a key
          equality over a `value` or `checked` payload is meaningless. -/
          match spec.keyEvents.toList.find? (·.name == mounted.binding.eventName) with
          | none =>
              throw {
                code := "LRX-VIEW-017"
                message := s!"view references unknown typed event {mounted.binding.eventName}"
                spans := #[mounted.binding.span]
              }
          | some event =>
              unless mounted.binding.kind == .keydown do
                throw {
                  code := "LRX-VIEW-041"
                  message := s!"key-branched event {event.name} selects on the key payload and cannot serve a {mounted.binding.kind.name} binding"
                  spans := #[mounted.binding.span, event.span]
                }
      | some event =>
          unless acceptsPayload event mounted.binding.kind.payload do
            throw {
              code := "LRX-VIEW-018"
              message := s!"typed event {event.name} takes a {event.payloadType.debug} payload and cannot serve a {mounted.binding.kind.name} binding"
              spans := #[mounted.binding.span, event.span]
            }
  /- A key-branched event must be bound exactly once, mirroring the ADR-0052
  row rule: the selection is dispatch logic of one input's keydown stream,
  and an unbound table would be dead vocabulary. -/
  for event in spec.keyEvents do
    let bindings := split.events.filter (·.binding.eventName == event.name)
    unless bindings.length == 1 do
      throw {
        code := "LRX-VIEW-041"
        message := s!"key-branched event {event.name} must be bound exactly once through onKeyDown; the view binds it {bindings.length} time(s)"
        spans := #[event.span] ++ (bindings.map (·.binding.span)).toArray
      }

private def eventByName? (events : Array (EventSpec Γ)) (name : String) : Option (EventSpec Γ) :=
  events.toList.find? (·.name == name)

private def effectiveWrites (events : Array (EventSpec Γ)) : Nat → Update Γ → List Nat
  | 0, update => update.directWriteTargets.eraseDups
  | fuel + 1, update =>
      (update.directWriteTargets ++ update.dispatchTargets.flatMap fun target =>
        match eventByName? events target with
        | some event => effectiveWrites events fuel event.update
        | none => []).eraseDups

private def effectiveReads (events : Array (EventSpec Γ)) : Nat → Update Γ → List Nat
  | 0, update => update.directReadDependencies.eraseDups
  | fuel + 1, update =>
      (update.directReadDependencies ++ update.dispatchTargets.flatMap fun target =>
        match eventByName? events target with
        | some event => effectiveReads events fuel event.update
        | none => []).eraseDups

private def summarizeTypedEvents (events : Array (AnyTypedEvent Γ)) : Array EventSummary :=
  events.map fun event => {
    name := event.name
    directWrites := event.targetIndex?.toList
    directReads := []
    dispatchedEvents := []
    effectiveWrites := event.targetIndex?.toList
    effectiveReads := []
  }

private def summarizeEvents (events : Array (EventSpec Γ)) : Array EventSummary :=
  events.map fun event => {
    name := event.name
    directWrites := event.update.directWriteTargets.eraseDups
    directReads := (event.guardReads ++ event.update.directReadDependencies).eraseDups
    dispatchedEvents := event.update.dispatchTargets.eraseDups
    effectiveWrites := effectiveWrites events events.size event.update
    effectiveReads :=
      (event.guardReads ++ effectiveReads events events.size event.update).eraseDups
  }

/-- Summaries of key-branched events (ADR-0056): the union over the arm
table, guard reads included; nested dispatch resolves through the plain
event table exactly as an ordinary event's does. -/
private def summarizeKeyEvents (events : Array (EventSpec Γ))
    (keyEvents : Array (KeyEventSpec Γ)) : Array EventSummary :=
  keyEvents.map fun event => {
    name := event.name
    directWrites := (event.arms.flatMap (·.update.directWriteTargets)).eraseDups
    directReads := (event.arms.flatMap fun arm =>
      arm.guardReads ++ arm.update.directReadDependencies).eraseDups
    dispatchedEvents := (event.arms.flatMap (·.update.dispatchTargets)).eraseDups
    effectiveWrites := (event.arms.flatMap fun arm =>
      effectiveWrites events events.size arm.update).eraseDups
    effectiveReads := (event.arms.flatMap fun arm =>
      arm.guardReads ++ effectiveReads events events.size arm.update).eraseDups
  }

mutual
private def validateView : View Γ → Except ComponentError Unit
  | .element tag attrs events children span props selects => do
      /- A state-scoped attribute selection counts as its attribute for
      duplicate detection, so a static attribute beside one — or two
      selections of the same attribute — duplicates (ADR-0045). -/
      if duplicate? (attrs.map StaticAttr.name ++ selects.map AttrSelect.name) then
        throw { code := "LRX-VIEW-001", message := "element has duplicate static attributes", spans := #[span] }
      for select in selects do
        match select with
        | .classSelect .. | .hiddenIfEmpty .. => pure ()
        | .pressedSelect .. | .disabledSelect .. =>
            unless tag == .button do
              throw {
                code := "LRX-VIEW-032"
                message := s!"a {select.name} selection requires a native button element"
                spans := #[select.span]
              }
        | .checkedIfEmpty .. =>
            /- The ADR-0049 checkbox rule in static scope (ADR-0060): the
            `checked` property originates from checkbox inputs alone. -/
            unless tag == .input && isCheckboxAttrs attrs do
              throw {
                code := "LRX-VIEW-043"
                message := "a checked reflection over a region count requires a type=\"checkbox\" input element"
                spans := #[select.span]
              }
      if duplicate? (events.map fun event => event.kind.name) then
        throw { code := "LRX-VIEW-002", message := "element has duplicate event bindings", spans := #[span] }
      if events.any (fun event => event.kind == .click || event.kind == .dblclick) &&
          tag != .button then
        throw {
          code := "LRX-VIEW-005"
          message := "click handlers require a native button in the M4 safe view"
          spans := #[span]
        }
      if events.any (fun event => event.kind == .submit) && tag != .form then
        throw {
          code := "LRX-VIEW-019"
          message := "submit handlers require a native form element"
          spans := #[span]
        }
      if events.any (fun event => event.kind.payload != .none) && tag != .input then
        throw {
          code := "LRX-VIEW-016"
          message := "typed payload events require a native input element"
          spans := #[span]
        }
      if !props.isEmpty && tag != .input then
        throw {
          code := "LRX-VIEW-020"
          message := "reflected properties require a native input element"
          spans := #[span]
        }
      /- A `checked` selection counts as a reflected property here (ADR-0060):
      a controlled `checked` binding beside the toggle-all selection would
      race two writers over one element property. -/
      if duplicate? (props.map PropBinding.name ++ selects.map AttrSelect.name) then
        throw {
          code := "LRX-VIEW-021"
          message := "element reflects duplicate properties"
          spans := #[span]
        }
      for attr in attrs do
        if let .buttonType _ := attr then
          unless tag == .button do
            throw { code := "LRX-VIEW-003", message := "button type is valid only on button elements", spans := #[span] }
        if let .inputType _ := attr then
          unless tag == .input do
            throw { code := "LRX-VIEW-022", message := "input type is valid only on input elements", spans := #[span] }
      validateChildren children
  | .text _ _ => pure ()
  | .scalarText name _ span =>
      if name.isEmpty then
        throw { code := "LRX-VIEW-004", message := "text sink name must not be empty", spans := #[span] }
      else pure ()
  | .child _ _ _ => pure ()
  | .region _ _ => pure ()
  | .regionCount _ _ _ _ => pure ()
  | .propText _ _ => pure ()

private def validateChildren : ViewChildren Γ → Except ComponentError Unit
  | .nil => pure ()
  | .cons head tail => do
      validateView head
      validateChildren tail
end

/-- Every nested component reference must name a declared child, and the child
table itself must be well formed: nonempty unique names and same-directory
`.mjs` module specifiers. -/
private def validateChildComponents (spec : ComponentSpec Γ)
    (split : ViewSplit Γ) : Except ComponentError Unit := do
  let names := spec.children.toList.map (·.name)
  if names.any String.isEmpty || duplicate? names then
    throw {
      code := "LRX-VIEW-024"
      message := "child component names must be nonempty and unique"
      spans := spec.children.map (·.span)
    }
  for entry in spec.children do
    unless entry.moduleSpecifier.startsWith "./" &&
        entry.moduleSpecifier.endsWith ".mjs" &&
        entry.moduleSpecifier.length > "./.mjs".length &&
        !((entry.moduleSpecifier.drop 2).toString.toList.contains '/') do
      throw {
        code := "LRX-VIEW-024"
        message := s!"child component {entry.name} has invalid module specifier {entry.moduleSpecifier}"
        spans := #[entry.span]
      }
  for reference in split.childRefs do
    unless names.contains reference.name do
      throw {
        code := "LRX-VIEW-023"
        message := s!"view references unknown child component {reference.name}"
        spans := #[reference.span]
      }
    /- A forwarded child prop reads one of this component's own immutable
    props at mount (ADR-0068); the declaration index must exist. -/
    for (bound, value) in reference.props do
      if let .forward field := value then
        unless field < spec.props.size do
          throw {
            code := "LRX-VIEW-044"
            message := s!"child prop {bound} forwards parent prop index {field}, but only {spec.props.size} immutable props are declared"
            spans := #[reference.span]
          }

/- Row event bindings bound anywhere inside one row-template subtree; a
branch cell contributes the bindings of both of its sealed subtrees. -/
mutual
  private def rowBindings : RowNode → List EventBinding
    | .element _ _ events children _ _ _ _ => events ++ rowBindingsChildren children
    | .text _ _ | .fieldText _ _ | .exprText _ _ => []
    | .branch _ _ whenTrue whenFalse _ => rowBindings whenTrue ++ rowBindings whenFalse

  private def rowBindingsChildren : RowChildren → List EventBinding
    | .nil => []
    | .cons head tail => rowBindings head ++ rowBindingsChildren tail
end

/- The autoFocus markers carried anywhere inside one sealed subtree; the
ADR-0048 rule admits at most one per branch subtree so the replacement arm
has one unambiguous focus target. -/
mutual
  private def rowFocusCount : RowNode → Nat
    | .element _ _ _ children _ _ _ autoFocus =>
        (if autoFocus then 1 else 0) + rowFocusCountChildren children
    | .text _ _ | .fieldText _ _ | .exprText _ _ => 0
    | .branch _ _ whenTrue whenFalse _ => rowFocusCount whenTrue + rowFocusCount whenFalse

  private def rowFocusCountChildren : RowChildren → Nat
    | .nil => 0
    | .cons head tail => rowFocusCount head + rowFocusCountChildren tail
end

/- Whether one sealed subtree contains an element of the given tag; the
one-sided delegation rule of ADR-0047 asks whether the unbound branch could
originate events of a delegated kind. -/
mutual
  private def rowContainsTag (tag : HtmlTag) : RowNode → Bool
    | .element nodeTag _ _ children _ _ _ _ =>
        nodeTag == tag || rowContainsTagChildren tag children
    | .text _ _ | .fieldText _ _ | .exprText _ _ => false
    | .branch _ _ whenTrue whenFalse _ =>
        rowContainsTag tag whenTrue || rowContainsTag tag whenFalse

  private def rowContainsTagChildren (tag : HtmlTag) : RowChildren → Bool
    | .nil => false
    | .cons head tail => rowContainsTag tag head || rowContainsTagChildren tag tail
end

/- The closed delegated row event kinds (ADR-0041/0046/0049): one structural
delegated listener per kind on the region container. -/
private def rowEventKinds : List EventKind :=
  [.click, .dblclick, .input, .keydown, .checkedChange]

/- Validate one sealed row template node (ADR-0041). `depth` is the distance
from the row root: the root is 0, cells are 1, and delegated row events may
only sit at depth ≥ 2 so structural resolution can find a strict cell
descendant. `inBranch` marks the sealed subtrees of a two-branch cell — the
only positions where the ADR-0048 autoFocus marker may sit. -/
mutual
  private def validateRowNode (region : RegionSpec) (depth : Nat) (inBranch : Bool) :
      RowNode → Except ComponentError Unit
    | .element tag attrs events children span classIf reflects autoFocus => do
        /- A class selection counts as the element's `class` attribute, so a
        static `class` beside one (or two selections) duplicates (ADR-0044). -/
        if duplicate? (attrs.map StaticAttr.name ++ classIf.map fun _ => "class") then
          throw { code := "LRX-VIEW-001", message := "element has duplicate static attributes", spans := #[span] }
        for select in classIf do
          for field in select.predicate.subject.fieldRefs do
            checkFieldBound "LRX-VIEW-026" "class selection projects" field
              region #[select.span]
        /- Sealed row property reflections (ADR-0047/0049): the `value`
        property of a native input — or the `checked` property of a
        `type="checkbox"` input — at most once per element and property
        target, over payload-free in-bounds row expressions. -/
        for target in [RowReflectTarget.value, .checkedIf ""] do
          unless (reflects.filter
              (·.target.propertyName == target.propertyName)).length ≤ 1 do
            throw {
              code := "LRX-VIEW-035"
              message := s!"element reflects the {target.propertyName} property more than once"
              spans := #[span]
            }
        for reflect in reflects do
          unless tag == .input do
            throw {
              code := "LRX-VIEW-035"
              message := s!"a row {reflect.target.propertyName} reflection requires a native input element"
              spans := #[reflect.span]
            }
          if let .checkedIf _ := reflect.target then
            unless isCheckboxAttrs attrs do
              throw {
                code := "LRX-VIEW-037"
                message := s!"a row checked reflection in region {region.name} requires a type=\"checkbox\" input element"
                spans := #[reflect.span]
              }
          if reflect.value.hasPayload then
            throw {
              code := "LRX-VIEW-033"
              message := s!"a row value reflection in region {region.name} cannot reference an event payload"
              spans := #[reflect.span]
            }
          for field in reflect.value.fieldRefs do
            checkFieldBound "LRX-VIEW-026" "a row value reflection projects"
              field region #[reflect.span]
        /- The sealed focus marker (ADR-0048): a native input inside a
        two-branch cell's subtrees only, so the update callback's replacement
        arm — and nothing else — can honor it. -/
        if autoFocus then
          unless tag == .input do
            throw {
              code := "LRX-VIEW-036"
              message := "an autoFocus marker requires a native input element"
              spans := #[span]
            }
          unless inBranch do
            throw {
              code := "LRX-VIEW-036"
              message := s!"an autoFocus marker in region {region.name} must sit inside a two-branch row cell's subtrees"
              spans := #[span]
            }
        if duplicate? (events.map fun event => event.kind.name) then
          throw { code := "LRX-VIEW-002", message := "element has duplicate event bindings", spans := #[span] }
        for event in events do
          match event.kind with
          | .click =>
              unless tag == .button do
                throw {
                  code := "LRX-VIEW-027"
                  message := "row click handlers require a native button in the sealed row template"
                  spans := #[event.span]
                }
          | .dblclick =>
              /- ADR-0049: dblclick is permitted on non-button row elements so
              a label can carry the TodoMVC edit affordance; the delegated
              dispatch is structural, so no handler or tabindex ever lands on
              the element itself. -/
              pure ()
          | .input | .keydown =>
              /- Typed row payload bindings (ADR-0046) delegate the host
              `value`/`key` payloads by row structure, so they require the
              native input element that produces them. -/
              unless tag == .input do
                throw {
                  code := "LRX-VIEW-033"
                  message := s!"row {event.kind.name} bindings require a native input element"
                  spans := #[event.span]
                }
          | .checkedChange =>
              /- The delegated `checked` payload originates from checkbox
              inputs alone (ADR-0049). -/
              unless tag == .input && isCheckboxAttrs attrs do
                throw {
                  code := "LRX-VIEW-037"
                  message := s!"a row change binding in region {region.name} requires a type=\"checkbox\" input element"
                  spans := #[event.span]
                }
          | _ =>
              throw {
                code := "LRX-VIEW-027"
                message := s!"row events in region {region.name} support click, dblclick, input, keydown, and change bindings only"
                spans := #[event.span]
              }
          unless depth ≥ 2 do
            throw {
              code := "LRX-VIEW-027"
              message := s!"row event {event.eventName} must sit strictly inside a row cell for structural delegation"
              spans := #[event.span]
            }
          match region.events.toList.find? (·.name == event.eventName) with
          | none =>
              throw {
                code := "LRX-VIEW-028"
                message := s!"row template references unknown row event {event.eventName}"
                path := #[region.name, event.eventName]
                spans := #[event.span]
              }
          | some rowEvent =>
              if event.kind.payload == .none && rowEvent.takesPayload then
                throw {
                  code := "LRX-VIEW-033"
                  message := s!"typed row event {rowEvent.name} takes a payload and cannot serve a {event.kind.name} binding"
                  path := #[region.name, rowEvent.name]
                  spans := #[event.span]
                }
              if event.kind.payload != .none && !rowEvent.takesPayload then
                throw {
                  code := "LRX-VIEW-033"
                  message := s!"row event {rowEvent.name} takes no payload and cannot serve a {event.kind.name} binding"
                  path := #[region.name, rowEvent.name]
                  spans := #[event.span]
                }
              /- A key-branched row event compares the delegated `key` payload
              (ADR-0052), so only a keydown binding can serve it — a key
              equality over a `value` or `checked` payload is meaningless. -/
              if rowEvent.action.isKeySelect && event.kind != .keydown then
                throw {
                  code := "LRX-VIEW-039"
                  message := s!"key-branched row event {rowEvent.name} of region {region.name} binds through onKeyDown only, not {event.kind.name}"
                  path := #[region.name, rowEvent.name]
                  spans := #[event.span]
                }
        validateRowChildren region (depth + 1) inBranch children
    | .text _ _ => pure ()
    | .fieldText field span =>
        checkFieldBound "LRX-VIEW-026" "row template projects" field region #[span]
    | .exprText value span => do
        if value.hasPayload then
          throw {
            code := "LRX-VIEW-033"
            message := s!"row template text in region {region.name} cannot reference an event payload"
            spans := #[span]
          }
        for field in value.fieldRefs do
          checkFieldBound "LRX-VIEW-026" "row expression projects" field region #[span]
    | .branch field _ whenTrue whenFalse span => do
        /- The sealed two-branch row cell (ADR-0047): only at a cell position
        (depth 1), so it occupies exactly one row-root child index, its
        subtrees mount inside the generated wrapper (depth 2, where delegated
        events resolve structurally), and branches never nest. -/
        unless depth == 1 do
          throw {
            code := "LRX-VIEW-034"
            message := s!"a two-branch row cell in region {region.name} must be a direct cell of the row root"
            spans := #[span]
          }
        checkFieldBound "LRX-VIEW-026" "a two-branch row cell projects" field
          region #[span]
        for subtree in [whenTrue, whenFalse] do
          match subtree with
          | .element .. => pure ()
          | _ =>
              throw {
                code := "LRX-VIEW-034"
                message := s!"both branches of a two-branch row cell in region {region.name} must be sealed template elements"
                spans := #[span]
              }
          unless rowFocusCount subtree ≤ 1 do
            throw {
              code := "LRX-VIEW-036"
              message := s!"a branch subtree in region {region.name} carries more than one autoFocus marker"
              spans := #[span]
            }
        validateRowNode region 2 true whenTrue
        validateRowNode region 2 true whenFalse

  private def validateRowChildren (region : RegionSpec) (depth : Nat) (inBranch : Bool) :
      RowChildren → Except ComponentError Unit
    | .nil => pure ()
    | .cons head tail => do
        validateRowNode region depth inBranch head
        validateRowChildren region depth inBranch tail
end

private def regionChildCounts : ViewChildren Γ → Nat × Nat
  | .nil => (0, 0)
  | .cons head tail =>
      let (total, regions) := regionChildCounts tail
      (total + 1, if let View.region _ _ := head then regions + 1 else regions)

/- Region positions must be the only child of their parent element so the
container owns exactly the keyed rows plus the region marker (ADR-0041). -/
mutual
  private def regionPlacementView : View Γ → Except ComponentError Unit
    | .element _ _ _ children span _ _ => do
        let (total, regions) := regionChildCounts children
        if regions > 0 && (total != 1 || regions != 1) then
          throw {
            code := "LRX-VIEW-029"
            message := "a keyed region must be the only child of its container element"
            spans := #[span]
          }
        regionPlacementChildren children
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .propText _ _ | .region _ _
    | .regionCount _ _ _ _ => pure ()

  private def regionPlacementChildren : ViewChildren Γ → Except ComponentError Unit
    | .nil => pure ()
    | .cons head tail => do
        regionPlacementView head
        regionPlacementChildren tail
end

/-- Validate the region table, its row templates, and the view's region
references (ADR-0041). -/
private def validateRegions (spec : ComponentSpec Γ) (split : ViewSplit Γ) :
    Except ComponentError Unit := do
  let names := spec.regions.toList.map (·.name)
  if names.any String.isEmpty || duplicate? names then
    throw {
      code := "LRX-VIEW-025"
      message := "region names must be nonempty and unique"
      spans := spec.regions.map (·.span)
    }
  for region in spec.regions do
    if region.fields.isEmpty then
      throw {
        code := "LRX-VIEW-026"
        message := s!"region {region.name} must declare at least one row field"
        spans := #[region.span]
      }
    if region.fields.toList.any String.isEmpty || duplicate? region.fields.toList then
      throw {
        code := "LRX-VIEW-026"
        message := s!"region {region.name} row field names must be nonempty and unique"
        spans := #[region.span]
      }
    let eventNames := region.events.toList.map (·.name)
    if eventNames.any String.isEmpty || duplicate? eventNames then
      throw {
        code := "LRX-VIEW-025"
        message := s!"region {region.name} row event names must be nonempty and unique"
        spans := #[region.span]
      }
    /- Row update actions (ADR-0043): nonempty simultaneous assignments over
    distinct in-bounds targets, reading only in-bounds row fields. Key-branched
    actions (ADR-0052) carry the same obligations per arm, over a nonempty
    table of distinct sealed key literals, with payload-free right-hand sides
    (the selection consumes the discriminant). A stage's remove-if guard
    (ADR-0053) projects one in-bounds row field — raw or behind the one
    ADR-0054 trim unary — and a guarded plain stage lives on a payload-less
    row event only — commits, not keystrokes. -/
    for event in region.events do
      if let .keySelect arms := event.action then
        unless event.takesPayload do
          throw {
            code := "LRX-VIEW-039"
            message := s!"key-branched row event {event.name} of region {region.name} must declare a String payload parameter"
            spans := #[event.span]
          }
        if arms.isEmpty then
          throw {
            code := "LRX-VIEW-039"
            message := s!"key-branched row event {event.name} of region {region.name} declares no arm"
            spans := #[event.span]
          }
        if duplicate? (arms.map (·.1)) then
          throw {
            code := "LRX-VIEW-039"
            message := s!"key-branched row event {event.name} of region {region.name} maps one key literal twice"
            spans := #[event.span]
          }
        for (keyLiteral, stage) in arms do
          let assignments := stage.assignments
          unless RowAction.keyLiterals.contains keyLiteral do
            throw {
              code := "LRX-VIEW-039"
              message := s!"key-branched row event {event.name} of region {region.name} branches on {keyLiteral} outside the sealed key set (Enter, Escape)"
              spans := #[event.span]
            }
          if let some guard := stage.removeIf then
            match guard.subject.guardSubject? with
            | none =>
                throw {
                  code := "LRX-VIEW-040"
                  message := s!"key-branched row event {event.name} of region {region.name} guards on a non-subject expression; a guard subject is one row field, optionally trimmed"
                  spans := #[event.span]
                }
            | some field =>
                checkFieldBound "LRX-VIEW-040"
                  s!"key-branched row event {event.name} guards on" field region
                  #[event.span]
          if assignments.isEmpty then
            throw {
              code := "LRX-VIEW-039"
              message := s!"key-branched row event {event.name} of region {region.name} updates no field on {keyLiteral}"
              spans := #[event.span]
            }
          if duplicate? (assignments.map (toString ·.1)) then
            throw {
              code := "LRX-VIEW-039"
              message := s!"key-branched row event {event.name} of region {region.name} assigns one field twice on {keyLiteral}"
              spans := #[event.span]
            }
          for (target, value) in assignments do
            checkFieldBound "LRX-VIEW-039"
              s!"key-branched row event {event.name} writes" target region
              #[event.span]
            if value.hasPayload then
              throw {
                code := "LRX-VIEW-039"
                message := s!"key-branched row event {event.name} of region {region.name} references the payload in an arm; the key literal already fixes it"
                spans := #[event.span]
              }
            for field in value.fieldRefs do
              checkFieldBound "LRX-VIEW-039"
                s!"key-branched row event {event.name} reads" field region
                #[event.span]
      if let .update stage := event.action then
        let assignments := stage.assignments
        if let some guard := stage.removeIf then
          if event.takesPayload then
            throw {
              code := "LRX-VIEW-040"
              message := s!"guarded row event {event.name} of region {region.name} cannot take a payload; guards live on payload-less row events and key arms"
              spans := #[event.span]
            }
          match guard.subject.guardSubject? with
          | none =>
              throw {
                code := "LRX-VIEW-040"
                message := s!"guarded row event {event.name} of region {region.name} guards on a non-subject expression; a guard subject is one row field, optionally trimmed"
                spans := #[event.span]
              }
          | some field =>
              checkFieldBound "LRX-VIEW-040"
                s!"guarded row event {event.name} guards on" field region
                #[event.span]
        if assignments.isEmpty then
          throw {
            code := "LRX-VIEW-031"
            message := s!"row event {event.name} of region {region.name} updates no field"
            spans := #[event.span]
          }
        if duplicate? (assignments.map (toString ·.1)) then
          throw {
            code := "LRX-VIEW-031"
            message := s!"row event {event.name} of region {region.name} assigns one field twice"
            spans := #[event.span]
          }
        for (target, value) in assignments do
          checkFieldBound "LRX-VIEW-031" s!"row event {event.name} writes"
            target region #[event.span]
          if value.hasPayload && !event.takesPayload then
            throw {
              code := "LRX-VIEW-033"
              message := s!"row event {event.name} of region {region.name} references an event payload but declares none"
              spans := #[event.span]
            }
          for field in value.fieldRefs do
            checkFieldBound "LRX-VIEW-031" s!"row event {event.name} reads"
              field region #[event.span]
    match region.template with
    | .element _ _ events cells _ _ _ _ => do
        unless events.isEmpty do
          throw {
            code := "LRX-VIEW-027"
            message := s!"the row root of region {region.name} cannot bind row events"
            spans := #[region.span]
          }
        /- One row event per cell and per delegated kind: each kind's cell
        action array carries at most one action per cell (ADR-0041/0046). A
        branch cell keeps that bound per branch and must agree across its
        branches (ADR-0047): the delegated action arrays are static, so both
        branches must bind the same action for a kind, or the unbound branch
        must be unable to originate that kind — clicks and double clicks
        bubble from any content (exact agreement required), `input` and
        checkbox `change` events originate only from native inputs
        (ADR-0049), and `keydown` events only from the focusable
        input/button elements. -/
        for cell in cells.toList do
          match cell with
          | .branch _ _ whenTrue whenFalse _ =>
              for kind in rowEventKinds do
                for subtree in [whenTrue, whenFalse] do
                  unless ((rowBindings subtree).filter (·.kind == kind)).length ≤ 1 do
                    throw {
                      code := "LRX-VIEW-027"
                      message := s!"a row cell of region {region.name} binds more than one {kind.name} row event"
                      spans := #[region.span]
                    }
                let boundTrue := (rowBindings whenTrue).find? (·.kind == kind)
                let boundFalse := (rowBindings whenFalse).find? (·.kind == kind)
                match boundTrue, boundFalse with
                | some first, some second =>
                    unless first.eventName == second.eventName do
                      throw {
                        code := "LRX-VIEW-034"
                        message := s!"the branches of a row cell in region {region.name} bind different {kind.name} row events ({first.eventName}, {second.eventName})"
                        spans := #[first.span, second.span]
                      }
                | none, none => pure ()
                | some binding, none | none, some binding =>
                    let other := if boundTrue.isSome then whenFalse else whenTrue
                    match kind with
                    | .click | .dblclick =>
                        /- Clicks and double clicks bubble from any content
                        (ADR-0047/0049): exact agreement required, never
                        one-sided. -/
                        throw {
                          code := "LRX-VIEW-034"
                          message := s!"a {kind.name} row event bound in one branch of a row cell in region {region.name} must be bound identically in the other branch"
                          spans := #[binding.span]
                        }
                    | .input | .checkedChange =>
                        /- `input` and checkbox `change` events originate only
                        from native inputs (ADR-0046/0049). -/
                        if rowContainsTag .input other then
                          throw {
                            code := "LRX-VIEW-034"
                            message := s!"a one-branch {kind.name} binding in region {region.name} requires the other branch to contain no input element"
                            spans := #[binding.span]
                          }
                    | _ =>
                        if rowContainsTag .input other || rowContainsTag .button other then
                          throw {
                            code := "LRX-VIEW-034"
                            message := s!"a one-branch keydown binding in region {region.name} requires the other branch to contain no input or button element"
                            spans := #[binding.span]
                          }
          | _ =>
              for kind in rowEventKinds do
                unless ((rowBindings cell).filter (·.kind == kind)).length ≤ 1 do
                  throw {
                    code := "LRX-VIEW-027"
                    message := s!"a row cell of region {region.name} binds more than one {kind.name} row event"
                    spans := #[region.span]
                  }
        /- A payload-taking row event must be bound exactly once so its
        delegated payload class is determined by that binding (ADR-0046). -/
        let bindings := rowBindingsChildren cells
        for event in region.events do
          if event.takesPayload then
            unless (bindings.filter (·.eventName == event.name)).length == 1 do
              throw {
                code := "LRX-VIEW-033"
                message := s!"typed row event {event.name} of region {region.name} must be bound exactly once in the row template"
                path := #[region.name, event.name]
                spans := #[event.span]
              }
        validateRowNode region 0 false region.template
    | _ =>
        throw {
          code := "LRX-VIEW-027"
          message := s!"the row template of region {region.name} must be an element"
          spans := #[region.span]
        }
  for reference in split.regionRefs do
    unless names.contains reference.name do
      throw {
        code := "LRX-VIEW-025"
        message := s!"view references unknown region {reference.name}"
        spans := #[reference.span]
      }
  for region in spec.regions do
    let references := split.regionRefs.filter (·.name == region.name)
    unless references.length == 1 do
      throw {
        code := "LRX-VIEW-025"
        message := s!"region {region.name} must be mounted exactly once, found {references.length} reference(s)"
        spans := #[region.span]
      }
  /- Sealed row aggregates (ADR-0050): every count position names a declared
  region, and a count predicate projects an in-bounds row field. -/
  for count in split.regionCounts do
    match spec.regions.toList.find? (·.name == count.region) with
    | none =>
        throw {
          code := "LRX-VIEW-038"
          message := s!"view counts unknown region {count.region}"
          spans := #[count.span]
        }
    | some region =>
        if let some (fieldIndex, _) := count.predicate then
          checkFieldBound "LRX-VIEW-038" "a count predicate projects"
            fieldIndex region #[count.span, region.span]
  /- Sealed region-count subjects (ADR-0058/0059/0060): every `hiddenIfEmpty`
  and `checkedIfEmpty` selection names a declared region — the row-table
  subject exists exactly when the region does — and a predicate-count
  subject projects an in-bounds row field, the ADR-0050 count-predicate
  rule. -/
  for mounted in split.attrSelects do
    if let some regionName := mounted.select.regionSubject? then
      match spec.regions.toList.find? (·.name == regionName) with
      | none =>
          throw {
            code := "LRX-VIEW-042"
            message := s!"a {mounted.select.name} reflection references unknown region {regionName}"
            spans := #[mounted.select.span]
          }
      | some region =>
          if let some (fieldIndex, _) := mounted.select.regionPredicate? then
            checkFieldBound "LRX-VIEW-042"
              s!"a {mounted.select.name} reflection's predicate projects"
              fieldIndex region #[mounted.select.span, region.span]
  unless spec.regions.isEmpty do
    if let View.region _ span := spec.view then
      throw {
        code := "LRX-VIEW-029"
        message := "a keyed region cannot be the component view root"
        spans := #[span]
      }
    regionPlacementView spec.view

/-- Validate the sealed region filter table (ADR-0051): every filter names a
declared region at most once, and its arms are a nonempty table over distinct
state literals whose predicates project in-bounds row fields. -/
private def validateFilters (spec : ComponentSpec Γ) : Except ComponentError Unit := do
  if duplicate? (spec.filters.toList.map (·.region)) then
    throw {
      code := "LRX-TYPE-113"
      message := "a keyed region can carry at most one filter view"
      spans := spec.filters.map (·.span)
    }
  for filter in spec.filters do
    match spec.regions.toList.find? (·.name == filter.region) with
    | none =>
        throw {
          code := "LRX-TYPE-113"
          message := s!"filter view targets unknown region {filter.region}"
          spans := #[filter.span]
        }
    | some region =>
        if filter.arms.isEmpty then
          throw {
            code := "LRX-TYPE-113"
            message := s!"filter view on region {filter.region} declares no arm"
            spans := #[filter.span]
          }
        if duplicate? (filter.arms.map (·.1)) then
          throw {
            code := "LRX-TYPE-113"
            message := s!"filter view on region {filter.region} maps one state literal twice"
            spans := #[filter.span]
          }
        for (_, predicate) in filter.arms do
          for fieldIndex in predicate.subject.fieldRefs do
            checkFieldBound "LRX-TYPE-113" "filter view projects" fieldIndex
              region #[filter.span, region.span]

/-- The declared initial of one `String` source, for the ADR-0063 route
default rule. -/
private def stringInitial? : ValueSpec Γ → Option String
  | .source _ _ _ (.string value) _ => some value
  | _ => none

/-- Validate the sealed route table (ADR-0063): at most one route item, whose
field is a `String` source carrying a declared ADR-0051 region filter; the
arms are a nonempty one-to-one table from distinct `#/`-shaped hash literals
onto the field's existing state literals — the declared default plus the
filter table's literals — and exactly one arm maps the declared default, so
the unknown-hash fallback is a table entry. -/
private def validateRoutes (spec : ComponentSpec Γ) (sourceCount : Nat) :
    Except ComponentError Unit := do
  unless spec.routes.size ≤ 1 do
    throw {
      code := "LRX-TYPE-117"
      message := "a component declares at most one route item"
      spans := spec.routes.map (·.span)
    }
  for route in spec.routes do
    unless route.field.index < sourceCount do
      throw {
        code := "LRX-TYPE-117"
        message := s!"route item targets derived value {route.field.index}; the routed field is one String state field"
        spans := #[route.span]
      }
    let filterTable ← match spec.filters.toList.find?
        (·.field.index == route.field.index) with
      | some filter => pure (filter.arms.map (·.1), filter.span)
      | none =>
          throw {
            code := "LRX-TYPE-117"
            message := "route item targets a field with no declared region filter; routing seals onto the filter field"
            spans := #[route.span]
          }
    if route.arms.isEmpty then
      throw {
        code := "LRX-TYPE-117"
        message := "route item declares no arm"
        spans := #[route.span]
      }
    for (hash, _) in route.arms do
      unless hash.startsWith "#/" do
        throw {
          code := "LRX-TYPE-117"
          message := s!"route hash literal {hash} is outside the sealed #/-shaped set"
          spans := #[route.span]
        }
    if duplicate? (route.arms.map (·.1)) then
      throw {
        code := "LRX-TYPE-117"
        message := "route item maps one hash literal twice"
        spans := #[route.span]
      }
    if duplicate? (route.arms.map (·.2)) then
      throw {
        code := "LRX-TYPE-117"
        message := "route item maps one state literal twice; the correspondence is one-to-one"
        spans := #[route.span]
      }
    let default ← match spec.values[route.field.index]?.bind stringInitial? with
      | some value => pure value
      | none =>
          throw {
            code := "LRX-TYPE-117"
            message := "route item targets a field without a declared String initial"
            spans := #[route.span]
          }
    let sealedLiterals := default :: filterTable.1
    for (_, literal) in route.arms do
      unless sealedLiterals.contains literal do
        throw {
          code := "LRX-TYPE-117"
          message := s!"route state literal {literal} is outside the field's existing state literals (the declared default and the filter table)"
          spans := #[route.span, filterTable.2]
        }
    unless route.arms.any (·.2 == default) do
      throw {
        code := "LRX-TYPE-117"
        message := s!"route item never maps the declared default literal {default}; the unknown-hash fallback is a table entry"
        spans := #[route.span]
      }

/-- Validate the sealed persistence table (ADR-0063): at most one persist item
per component — one sealed literal key — targeting a declared region with a
nonempty key. -/
private def validatePersists (spec : ComponentSpec Γ) : Except ComponentError Unit := do
  unless spec.persists.size ≤ 1 do
    throw {
      code := "LRX-TYPE-118"
      message := "a component declares at most one persist item — one sealed literal storage key"
      spans := spec.persists.map (·.span)
    }
  for persist in spec.persists do
    if persist.key.isEmpty then
      throw {
        code := "LRX-TYPE-118"
        message := s!"persist item on region {persist.region} declares an empty storage key"
        spans := #[persist.span]
      }
    unless spec.regions.toList.any (·.name == persist.region) do
      throw {
        code := "LRX-TYPE-118"
        message := s!"persist item targets unknown region {persist.region}"
        spans := #[persist.span]
      }

/-- Validate the immutable prop table and the view's prop text positions
(ADR-0042). -/
private def validateProps (spec : ComponentSpec Γ) (split : ViewSplit Γ) :
    Except ComponentError Unit := do
  let names := spec.props.toList.map (·.name)
  if names.any String.isEmpty || duplicate? names then
    throw {
      code := "LRX-VIEW-030"
      message := "immutable prop names must be nonempty and unique"
      spans := spec.props.map (·.span)
    }
  for reference in split.propTexts do
    unless reference.field < spec.props.size do
      throw {
        code := "LRX-VIEW-030"
        message := s!"view projects immutable prop {reference.field} outside the {spec.props.size} declared prop(s)"
        spans := #[reference.span]
      }

/-- Validate the explicit component contract and retain its certified graph. -/
def check (spec : ComponentSpec Γ) : Except ComponentError (CheckedComponent Γ) := do
  if spec.name.isEmpty then
    .error { code := "LRX-ELAB-101", message := "component name must not be empty", spans := #[spec.span] }
  else match validateSurface spec with
  | .error error => .error error
  | .ok _ => match validateValues spec with
    | .error error => .error error
    | .ok sourceCount => match validateView spec.view with
      | .error error => .error error
      | .ok _ =>
        let split := spec.view.split
        match validateEvents spec sourceCount split with
        | .error error => .error error
        | .ok _ => match validateChildComponents spec split with
          | .error error => .error error
          | .ok _ => match validateRegions spec split with
            | .error error => .error error
            | .ok _ => match validateFilters spec with
              | .error error => .error error
              | .ok _ => match validateRoutes spec sourceCount with
                | .error error => .error error
                | .ok _ => match validatePersists spec with
                  | .error error => .error error
                  | .ok _ => match validateProps spec split with
                    | .error error => .error error
                    | .ok _ => match valueNodes spec.values with
                      | .error error => .error error
                      | .ok valueNodes => match sinkNodes spec.values split.textSinks with
                        | .error error => .error error
                        | .ok sinkNodes => match propNodes spec.values split.props with
                          | .error error => .error error
                          | .ok propNodes =>
                              match attrSelectNodes spec.values split.attrSelects with
                              | .error error => .error error
                              | .ok attrNodes =>
                                  match filterNodes spec.values spec.filters with
                                  | .error error => .error error
                                  | .ok filterNodes =>
                                      match Graph.plan
                                          (valueNodes ++ sinkNodes ++ propNodes ++
                                            attrNodes ++ filterNodes) with
                                      | .error error => .error {
                                          code := error.code, message := error.message,
                                          path := error.path, spans := error.spans
                                        }
                                      | .ok graph =>
                                          .ok ⟨spec, graph, sourceCount,
                                            summarizeEvents spec.events ++
                                              summarizeTypedEvents spec.typedEvents ++
                                              summarizeKeyEvents spec.events
                                                spec.keyEvents, split⟩

def validationMessage (spec : ComponentSpec Γ) : String :=
  match spec.check with
  | .ok _ => ""
  | .error error => error.render

end ComponentSpec

end LeanRx
