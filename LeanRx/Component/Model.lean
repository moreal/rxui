import LeanRx.Graph.Topological
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

/-- Pure transaction-local update program. M4 validates writes target sources. -/
inductive Update (Γ : Schema) where
  | set (field : Field Γ α) (value : RxExpr Γ deps α) (span : SourceSpan := .generated)
  | dispatch (eventName : String) (span : SourceSpan := .generated)
  | sequence (first second : Update Γ)

namespace Update

def directWriteTargets : Update Γ → List Nat
  | .set field _ _ => [field.index]
  | .dispatch .. => []
  | .sequence first second => first.directWriteTargets ++ second.directWriteTargets

def directReadDependencies : Update Γ → List Nat
  | .set _ value _ => value.dependencies.ids
  | .dispatch .. => []
  | .sequence first second => first.directReadDependencies ++ second.directReadDependencies

def dispatchTargets : Update Γ → List String
  | .set .. => []
  | .dispatch eventName _ => [eventName]
  | .sequence first second => first.dispatchTargets ++ second.dispatchTargets

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

structure ComponentSpec (Γ : Schema) where
  name : String
  values : Array (ValueSpec Γ)
  events : Array (EventSpec Γ)
  view : View Γ
  surface : Array SurfaceDecl := #[]
  span : SourceSpan := .generated

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

private def validateEvents (spec : ComponentSpec Γ) (sourceCount : Nat)
    (split : ViewSplit Γ) : Except ComponentError Unit := do
  let names := spec.events.toList.map (·.name)
  if names.any String.isEmpty || duplicate? names then
    throw { code := "LRX-ELAB-102", message := "component event names must be nonempty and unique" }
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
  for mounted in split.events do
    unless names.contains mounted.binding.eventName do
      throw {
        code := "LRX-VIEW-006"
        message := s!"view references unknown event {mounted.binding.eventName}"
        spans := #[mounted.binding.span]
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
  | .element tag attrs events children span => do
      if duplicate? (attrs.map StaticAttr.name) then
        throw { code := "LRX-VIEW-001", message := "element has duplicate static attributes", spans := #[span] }
      if duplicate? (events.map fun event => event.kind.name) then
        throw { code := "LRX-VIEW-002", message := "element has duplicate event bindings", spans := #[span] }
      if !events.isEmpty && tag != .button then
        throw {
          code := "LRX-VIEW-005"
          message := "click handlers require a native button in the M4 safe view"
          spans := #[span]
        }
      for attr in attrs do
        if let .buttonType _ := attr then
          unless tag == .button do
            throw { code := "LRX-VIEW-003", message := "button type is valid only on button elements", spans := #[span] }
      validateChildren children
  | .text _ _ => pure ()
  | .scalarText name _ span =>
      if name.isEmpty then
        throw { code := "LRX-VIEW-004", message := "text sink name must not be empty", spans := #[span] }
      else pure ()

private def validateChildren : ViewChildren Γ → Except ComponentError Unit
  | .nil => pure ()
  | .cons head tail => do
      validateView head
      validateChildren tail
end

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
        | .ok _ => match valueNodes spec.values with
          | .error error => .error error
          | .ok valueNodes => match sinkNodes spec.values split.textSinks with
            | .error error => .error error
            | .ok sinkNodes => match Graph.plan (valueNodes ++ sinkNodes) with
              | .error error => .error {
                  code := error.code, message := error.message,
                  path := error.path, spans := error.spans
                }
              | .ok graph =>
                  .ok ⟨spec, graph, sourceCount, summarizeEvents spec.events, split⟩

def validationMessage (spec : ComponentSpec Γ) : String :=
  match spec.check with
  | .ok _ => ""
  | .error error => error.render

end ComponentSpec

end LeanRx
