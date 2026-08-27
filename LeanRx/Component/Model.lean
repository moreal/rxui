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
`regionRemoveIf` removes every row whose projected field equals the literal —
both re-render through the keyed reconcile with retained-row identity
preserved (ADR-0050). -/
inductive Update (Γ : Schema) where
  | set (field : Field Γ α) (value : RxExpr Γ deps α) (span : SourceSpan := .generated)
  | dispatch (eventName : String) (span : SourceSpan := .generated)
  | regionAppend (region : String) (values : List (RowValue Γ))
      (span : SourceSpan := .generated)
  | regionBroadcast (region : String) (assignments : List (Nat × RowExpr))
      (span : SourceSpan := .generated)
  | regionRemoveIf (region : String) (field : Nat) (equals : String)
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

/-- Region removal targets with their predicate field, for region-table
checks (ADR-0050). -/
def regionRemoveIfTargets : Update Γ → List (String × Nat)
  | .set .. | .dispatch .. | .regionAppend .. | .regionBroadcast .. => []
  | .regionRemoveIf region field _ _ => [(region, field)]
  | .sequence first second => first.regionRemoveIfTargets ++ second.regionRemoveIfTargets

end Update

structure EventSpec (Γ : Schema) where
  name : String
  update : Update Γ
  span : SourceSpan := .generated

def EventSpec.withSpan (event : EventSpec Γ) (span : SourceSpan) : EventSpec Γ :=
  { event with span }

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
is `(stateLiteral, rowField, rowLiteral)`: while the filter field equals
`stateLiteral`, exactly the rows whose projected field equals `rowLiteral`
stay visible; a state value outside the table carries no predicate and shows
every row. The commit sweep records the selection as each row root's
`hidden` property — rows never mount or dispose on a filter change, so row
identity is untouched by construction. The typed `Field Γ String` makes a
cross-typed selector unrepresentable. -/
structure RegionFilter (Γ : Schema) where
  region : String
  field : Field Γ String
  arms : List (String × Nat × String)
  span : SourceSpan := .generated

structure ComponentSpec (Γ : Schema) where
  name : String
  values : Array (ValueSpec Γ)
  events : Array (EventSpec Γ)
  typedEvents : Array (AnyTypedEvent Γ) := #[]
  view : View Γ
  surface : Array SurfaceDecl := #[]
  children : Array ChildComponent := #[]
  regions : Array RegionSpec := #[]
  filters : Array (RegionFilter Γ) := #[]
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
  let nodes ← selects.zipIdx.mapM fun (mounted, index) => do
    pure <| NodeSpec.sink s!"attr:{index}:{mounted.select.name}" mounted.select.valueType
      (← refsFor values [mounted.select.fieldIndex]) mounted.select.debug mounted.select.span
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
serve `value`/`key` bindings, `Bool` events serve `checked` bindings. -/
private def acceptsPayload : AnyTypedEvent Γ → EventPayload → Bool
  | .string _, .value | .string _, .key => true
  | .bool _, .checked => true
  | _, _ => false

private def validateEvents (spec : ComponentSpec Γ) (sourceCount : Nat)
    (split : ViewSplit Γ) : Except ComponentError Unit := do
  let names := spec.events.toList.map (·.name)
  let typedNames := spec.typedEvents.toList.map (·.name)
  if (names ++ typedNames).any String.isEmpty || duplicate? (names ++ typedNames) then
    throw { code := "LRX-ELAB-102", message := "component event names must be nonempty and unique" }
  for event in spec.typedEvents do
    unless event.targetIndex < sourceCount do
      throw {
        code := "LRX-TYPE-107"
        message := s!"event {event.name} writes non-source value {event.targetIndex}"
        spans := #[event.span]
      }
  for event in spec.events do
    for target in event.update.directWriteTargets do
      unless target < sourceCount do
        throw {
          code := "LRX-TYPE-107"
          message := s!"event {event.name} writes non-source value {target}"
          spans := #[event.span]
        }
    for dependency in event.update.directReadDependencies do
      unless dependency < sourceCount do
        throw {
          code := "LRX-TYPE-108"
          message := s!"event {event.name} reads derived value {dependency}; derived reads require a transaction barrier"
          spans := #[event.span]
        }
    for target in event.update.dispatchTargets do
      unless names.contains target do
        throw {
          code := "LRX-ELAB-106"
          message := s!"event {event.name} dispatches unknown event {target}"
          path := #[event.name, target]
          spans := #[event.span]
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
  for event in spec.events do
    for (target, arity) in event.update.regionAppendTargets do
      match spec.regions.toList.find? (·.name == target) with
      | none =>
          throw {
            code := "LRX-TYPE-109"
            message := s!"event {event.name} appends to unknown region {target}"
            path := #[event.name, target]
            spans := #[event.span]
          }
      | some region =>
          unless arity == region.fields.size do
            throw {
              code := "LRX-TYPE-110"
              message := s!"event {event.name} appends {arity} field(s) to region {target}, which declares {region.fields.size}"
              path := #[event.name, target]
              spans := #[event.span, region.span]
            }
  /- Region broadcasts and removals (ADR-0050): the target region must be
  declared; broadcast assignments are nonempty simultaneous writes over
  distinct in-bounds targets, reading only in-bounds row fields and never a
  payload (no row event is dispatching); removal predicates project one
  in-bounds row field. -/
  for event in spec.events do
    for (target, assignments) in event.update.regionBroadcastTargets do
      match spec.regions.toList.find? (·.name == target) with
      | none =>
          throw {
            code := "LRX-TYPE-111"
            message := s!"event {event.name} broadcasts to unknown region {target}"
            path := #[event.name, target]
            spans := #[event.span]
          }
      | some region =>
          if assignments.isEmpty then
            throw {
              code := "LRX-TYPE-111"
              message := s!"event {event.name} broadcasts no field to region {target}"
              path := #[event.name, target]
              spans := #[event.span]
            }
          if duplicate? (assignments.map (toString ·.1)) then
            throw {
              code := "LRX-TYPE-111"
              message := s!"event {event.name} broadcasts one field of region {target} twice"
              path := #[event.name, target]
              spans := #[event.span]
            }
          for (fieldIndex, value) in assignments do
            unless fieldIndex < region.fields.size do
              throw {
                code := "LRX-TYPE-111"
                message := s!"event {event.name} broadcasts field {fieldIndex} outside region {target}'s {region.fields.size} field(s)"
                path := #[event.name, target]
                spans := #[event.span, region.span]
              }
            if value.hasPayload then
              throw {
                code := "LRX-TYPE-111"
                message := s!"event {event.name} broadcasts a payload reference to region {target}; broadcasts dispatch no row event"
                path := #[event.name, target]
                spans := #[event.span]
              }
            for field in value.fieldRefs do
              unless field < region.fields.size do
                throw {
                  code := "LRX-TYPE-111"
                  message := s!"event {event.name} broadcasts a read of field {field} outside region {target}'s {region.fields.size} field(s)"
                  path := #[event.name, target]
                  spans := #[event.span, region.span]
                }
    for (target, fieldIndex) in event.update.regionRemoveIfTargets do
      match spec.regions.toList.find? (·.name == target) with
      | none =>
          throw {
            code := "LRX-TYPE-112"
            message := s!"event {event.name} removes rows from unknown region {target}"
            path := #[event.name, target]
            spans := #[event.span]
          }
      | some region =>
          unless fieldIndex < region.fields.size do
            throw {
              code := "LRX-TYPE-112"
              message := s!"event {event.name} removes rows by field {fieldIndex} outside region {target}'s {region.fields.size} field(s)"
              path := #[event.name, target]
              spans := #[event.span, region.span]
            }
  for mounted in split.events do
    if mounted.binding.kind.payload == .none then
      unless names.contains mounted.binding.eventName do
        throw {
          code := "LRX-VIEW-006"
          message := s!"view references unknown event {mounted.binding.eventName}"
          spans := #[mounted.binding.span]
        }
    else
      match spec.typedEvents.toList.find? (·.name == mounted.binding.eventName) with
      | none =>
          throw {
            code := "LRX-VIEW-017"
            message := s!"view references unknown typed event {mounted.binding.eventName}"
            spans := #[mounted.binding.span]
          }
      | some event =>
          unless acceptsPayload event mounted.binding.kind.payload do
            throw {
              code := "LRX-VIEW-018"
              message := s!"typed event {event.name} takes a {event.payloadType.debug} payload and cannot serve a {mounted.binding.kind.name} binding"
              spans := #[mounted.binding.span, event.span]
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
    directWrites := [event.targetIndex]
    directReads := []
    dispatchedEvents := []
    effectiveWrites := [event.targetIndex]
    effectiveReads := []
  }

private def summarizeEvents (events : Array (EventSpec Γ)) : Array EventSummary :=
  events.map fun event => {
    name := event.name
    directWrites := event.update.directWriteTargets.eraseDups
    directReads := event.update.directReadDependencies.eraseDups
    dispatchedEvents := event.update.dispatchTargets.eraseDups
    effectiveWrites := effectiveWrites events events.size event.update
    effectiveReads := effectiveReads events events.size event.update
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
        | .classSelect .. => pure ()
        | .pressedSelect .. | .disabledSelect .. =>
            unless tag == .button do
              throw {
                code := "LRX-VIEW-032"
                message := s!"a {select.name} selection requires a native button element"
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
      if duplicate? (props.map PropBinding.name) then
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
  | .regionCount _ _ _ => pure ()
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

/- Whether one element's static attributes carry `type="checkbox"` — the
only elements a delegated `change` binding or a `checked` reflection may sit
on (ADR-0049): the `checked` payload and property originate from checkbox
inputs alone. -/
private def isCheckboxAttrs (attrs : List StaticAttr) : Bool :=
  attrs.any (· == .inputType .checkbox)

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
          unless select.field < region.fields.size do
            throw {
              code := "LRX-VIEW-026"
              message := s!"class selection projects field {select.field} outside region {region.name}'s {region.fields.size} field(s)"
              spans := #[select.span]
            }
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
            unless field < region.fields.size do
              throw {
                code := "LRX-VIEW-026"
                message := s!"a row value reflection projects field {field} outside region {region.name}'s {region.fields.size} field(s)"
                spans := #[reflect.span]
              }
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
        unless field < region.fields.size do
          throw {
            code := "LRX-VIEW-026"
            message := s!"row template projects field {field} outside region {region.name}'s {region.fields.size} field(s)"
            spans := #[span]
          }
    | .exprText value span => do
        if value.hasPayload then
          throw {
            code := "LRX-VIEW-033"
            message := s!"row template text in region {region.name} cannot reference an event payload"
            spans := #[span]
          }
        for field in value.fieldRefs do
          unless field < region.fields.size do
            throw {
              code := "LRX-VIEW-026"
              message := s!"row expression projects field {field} outside region {region.name}'s {region.fields.size} field(s)"
              spans := #[span]
            }
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
        unless field < region.fields.size do
          throw {
            code := "LRX-VIEW-026"
            message := s!"a two-branch row cell projects field {field} outside region {region.name}'s {region.fields.size} field(s)"
            spans := #[span]
          }
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
    | .regionCount _ _ _ => pure ()

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
    (ADR-0053) projects one in-bounds row field, and a guarded plain stage
    lives on a payload-less row event only — commits, not keystrokes. -/
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
            unless guard.field < region.fields.size do
              throw {
                code := "LRX-VIEW-040"
                message := s!"key-branched row event {event.name} guards on field {guard.field} outside region {region.name}'s {region.fields.size} field(s)"
                spans := #[event.span]
              }
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
            unless target < region.fields.size do
              throw {
                code := "LRX-VIEW-039"
                message := s!"key-branched row event {event.name} writes field {target} outside region {region.name}'s {region.fields.size} field(s)"
                spans := #[event.span]
              }
            if value.hasPayload then
              throw {
                code := "LRX-VIEW-039"
                message := s!"key-branched row event {event.name} of region {region.name} references the payload in an arm; the key literal already fixes it"
                spans := #[event.span]
              }
            for field in value.fieldRefs do
              unless field < region.fields.size do
                throw {
                  code := "LRX-VIEW-039"
                  message := s!"key-branched row event {event.name} reads field {field} outside region {region.name}'s {region.fields.size} field(s)"
                  spans := #[event.span]
                }
      if let .update stage := event.action then
        let assignments := stage.assignments
        if let some guard := stage.removeIf then
          if event.takesPayload then
            throw {
              code := "LRX-VIEW-040"
              message := s!"guarded row event {event.name} of region {region.name} cannot take a payload; guards live on payload-less row events and key arms"
              spans := #[event.span]
            }
          unless guard.field < region.fields.size do
            throw {
              code := "LRX-VIEW-040"
              message := s!"guarded row event {event.name} guards on field {guard.field} outside region {region.name}'s {region.fields.size} field(s)"
              spans := #[event.span]
            }
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
          unless target < region.fields.size do
            throw {
              code := "LRX-VIEW-031"
              message := s!"row event {event.name} writes field {target} outside region {region.name}'s {region.fields.size} field(s)"
              spans := #[event.span]
            }
          if value.hasPayload && !event.takesPayload then
            throw {
              code := "LRX-VIEW-033"
              message := s!"row event {event.name} of region {region.name} references an event payload but declares none"
              spans := #[event.span]
            }
          for field in value.fieldRefs do
            unless field < region.fields.size do
              throw {
                code := "LRX-VIEW-031"
                message := s!"row event {event.name} reads field {field} outside region {region.name}'s {region.fields.size} field(s)"
                spans := #[event.span]
              }
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
          unless fieldIndex < region.fields.size do
            throw {
              code := "LRX-VIEW-038"
              message := s!"a count predicate projects field {fieldIndex} outside region {count.region}'s {region.fields.size} field(s)"
              spans := #[count.span, region.span]
            }
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
        for (_, fieldIndex, _) in filter.arms do
          unless fieldIndex < region.fields.size do
            throw {
              code := "LRX-TYPE-113"
              message := s!"filter view projects field {fieldIndex} outside region {filter.region}'s {region.fields.size} field(s)"
              spans := #[filter.span, region.span]
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
              | .ok _ => match validateProps spec split with
                | .error error => .error error
                | .ok _ => match valueNodes spec.values with
                  | .error error => .error error
                  | .ok valueNodes => match sinkNodes spec.values split.textSinks with
                    | .error error => .error error
                    | .ok sinkNodes => match propNodes spec.values split.props with
                      | .error error => .error error
                      | .ok propNodes => match attrSelectNodes spec.values split.attrSelects with
                        | .error error => .error error
                        | .ok attrNodes => match filterNodes spec.values spec.filters with
                          | .error error => .error error
                          | .ok filterNodes =>
                              match Graph.plan
                                  (valueNodes ++ sinkNodes ++ propNodes ++ attrNodes ++
                                    filterNodes) with
                              | .error error => .error {
                                  code := error.code, message := error.message,
                                  path := error.path, spans := error.spans
                                }
                              | .ok graph =>
                                  .ok ⟨spec, graph, sourceCount,
                                    summarizeEvents spec.events ++
                                      summarizeTypedEvents spec.typedEvents, split⟩

def validationMessage (spec : ComponentSpec Γ) : String :=
  match spec.check with
  | .ok _ => ""
  | .error error => error.render

end ComponentSpec

end LeanRx
