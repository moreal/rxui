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
onto a declared keyed region (ADR-0041). -/
inductive Update (Γ : Schema) where
  | set (field : Field Γ α) (value : RxExpr Γ deps α) (span : SourceSpan := .generated)
  | dispatch (eventName : String) (span : SourceSpan := .generated)
  | regionAppend (region : String) (values : List (RowValue Γ))
      (span : SourceSpan := .generated)
  | sequence (first second : Update Γ)

namespace Update

def directWriteTargets : Update Γ → List Nat
  | .set field _ _ => [field.index]
  | .dispatch .. | .regionAppend .. => []
  | .sequence first second => first.directWriteTargets ++ second.directWriteTargets

def directReadDependencies : Update Γ → List Nat
  | .set _ value _ => value.dependencies.ids
  | .dispatch .. => []
  | .regionAppend _ values _ => values.flatMap (·.deps.ids)
  | .sequence first second => first.directReadDependencies ++ second.directReadDependencies

def dispatchTargets : Update Γ → List String
  | .set .. | .regionAppend .. => []
  | .dispatch eventName _ => [eventName]
  | .sequence first second => first.dispatchTargets ++ second.dispatchTargets

/-- Region append targets with their field arity, for region-table checks. -/
def regionAppendTargets : Update Γ → List (String × Nat)
  | .set .. | .dispatch .. => []
  | .regionAppend region values _ => [(region, values.length)]
  | .sequence first second => first.regionAppendTargets ++ second.regionAppendTargets

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

structure ComponentSpec (Γ : Schema) where
  name : String
  values : Array (ValueSpec Γ)
  events : Array (EventSpec Γ)
  typedEvents : Array (AnyTypedEvent Γ) := #[]
  view : View Γ
  surface : Array SurfaceDecl := #[]
  children : Array ChildComponent := #[]
  regions : Array RegionSpec := #[]
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
  | .element tag attrs events children span props => do
      if duplicate? (attrs.map StaticAttr.name) then
        throw { code := "LRX-VIEW-001", message := "element has duplicate static attributes", spans := #[span] }
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

/- Row events bound anywhere inside one row-template subtree. -/
mutual
  private def rowEventCount : RowNode → Nat
    | .element _ _ events children _ _ => events.length + rowEventCountChildren children
    | .text _ _ | .fieldText _ _ | .exprText _ _ => 0

  private def rowEventCountChildren : RowChildren → Nat
    | .nil => 0
    | .cons head tail => rowEventCount head + rowEventCountChildren tail
end

/- Validate one sealed row template node (ADR-0041). `depth` is the distance
from the row root: the root is 0, cells are 1, and delegated row events may
only sit at depth ≥ 2 so structural resolution can find a strict cell
descendant. -/
mutual
  private def validateRowNode (region : RegionSpec) (depth : Nat) :
      RowNode → Except ComponentError Unit
    | .element tag attrs events children span classIf => do
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
        if duplicate? (events.map fun event => event.kind.name) then
          throw { code := "LRX-VIEW-002", message := "element has duplicate event bindings", spans := #[span] }
        for event in events do
          unless event.kind == .click do
            throw {
              code := "LRX-VIEW-027"
              message := s!"row events in region {region.name} support click bindings only"
              spans := #[event.span]
            }
          unless tag == .button do
            throw {
              code := "LRX-VIEW-027"
              message := "row click handlers require a native button in the sealed row template"
              spans := #[event.span]
            }
          unless depth ≥ 2 do
            throw {
              code := "LRX-VIEW-027"
              message := s!"row event {event.eventName} must sit strictly inside a row cell for structural delegation"
              spans := #[event.span]
            }
          unless region.events.toList.any (·.name == event.eventName) do
            throw {
              code := "LRX-VIEW-028"
              message := s!"row template references unknown row event {event.eventName}"
              path := #[region.name, event.eventName]
              spans := #[event.span]
            }
        validateRowChildren region (depth + 1) children
    | .text _ _ => pure ()
    | .fieldText field span =>
        unless field < region.fields.size do
          throw {
            code := "LRX-VIEW-026"
            message := s!"row template projects field {field} outside region {region.name}'s {region.fields.size} field(s)"
            spans := #[span]
          }
    | .exprText value span => do
        for field in value.fieldRefs do
          unless field < region.fields.size do
            throw {
              code := "LRX-VIEW-026"
              message := s!"row expression projects field {field} outside region {region.name}'s {region.fields.size} field(s)"
              spans := #[span]
            }

  private def validateRowChildren (region : RegionSpec) (depth : Nat) :
      RowChildren → Except ComponentError Unit
    | .nil => pure ()
    | .cons head tail => do
        validateRowNode region depth head
        validateRowChildren region depth tail
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
    | .element _ _ _ children span _ => do
        let (total, regions) := regionChildCounts children
        if regions > 0 && (total != 1 || regions != 1) then
          throw {
            code := "LRX-VIEW-029"
            message := "a keyed region must be the only child of its container element"
            spans := #[span]
          }
        regionPlacementChildren children
    | .text _ _ | .scalarText _ _ _ | .child _ _ _ | .propText _ _ | .region _ _ => pure ()

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
    distinct in-bounds targets, reading only in-bounds row fields. -/
    for event in region.events do
      if let .update assignments := event.action then
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
          for field in value.fieldRefs do
            unless field < region.fields.size do
              throw {
                code := "LRX-VIEW-031"
                message := s!"row event {event.name} reads field {field} outside region {region.name}'s {region.fields.size} field(s)"
                spans := #[event.span]
              }
    match region.template with
    | .element _ _ events cells _ _ => do
        unless events.isEmpty do
          throw {
            code := "LRX-VIEW-027"
            message := s!"the row root of region {region.name} cannot bind row events"
            spans := #[region.span]
          }
        for cell in cells.toList do
          unless rowEventCount cell ≤ 1 do
            throw {
              code := "LRX-VIEW-027"
              message := s!"a row cell of region {region.name} binds more than one row event"
              spans := #[region.span]
            }
        validateRowNode region 0 region.template
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
  unless spec.regions.isEmpty do
    if let View.region _ span := spec.view then
      throw {
        code := "LRX-VIEW-029"
        message := "a keyed region cannot be the component view root"
        spans := #[span]
      }
    regionPlacementView spec.view

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
            | .ok _ => match validateProps spec split with
              | .error error => .error error
              | .ok _ => match valueNodes spec.values with
                | .error error => .error error
                | .ok valueNodes => match sinkNodes spec.values split.textSinks with
                  | .error error => .error error
                  | .ok sinkNodes => match propNodes spec.values split.props with
                    | .error error => .error error
                    | .ok propNodes =>
                        match Graph.plan (valueNodes ++ sinkNodes ++ propNodes) with
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
