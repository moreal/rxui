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

end ValueSpec

/-- Pure transaction-local update program. M4 validates writes target sources. -/
inductive Update (Γ : Schema) where
  | set (field : Field Γ α) (value : RxExpr Γ deps α) (span : SourceSpan := .generated)
  | sequence (first second : Update Γ)

namespace Update

def writeTargets : Update Γ → List Nat
  | .set field _ _ => [field.index]
  | .sequence first second => first.writeTargets ++ second.writeTargets

def readDependencies : Update Γ → List Nat
  | .set _ value _ => value.dependencies.ids
  | .sequence first second => first.readDependencies ++ second.readDependencies

end Update

structure EventSpec (Γ : Schema) where
  name : String
  update : Update Γ
  span : SourceSpan := .generated

structure ComponentSpec (Γ : Schema) where
  name : String
  values : Array (ValueSpec Γ)
  events : Array (EventSpec Γ)
  view : View Γ
  span : SourceSpan := .generated

structure ComponentError where
  code : String
  message : String
  spans : Array SourceSpan := #[]
deriving Repr, BEq

structure CheckedComponent (Γ : Schema) where
  private mk ::
  spec : ComponentSpec Γ
  graph : PlannedGraph
  sourceCount : Nat
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
        code := "LRX-COMP-006"
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
    throw { code := "LRX-COMP-002", message := "component must declare at least one value" }
  unless spec.values.size == Γ.size do
    throw {
      code := "LRX-COMP-003"
      message := "component value declarations must align exactly with its schema"
      spans := #[spec.span]
    }
  for index in List.range spec.values.size do
    match spec.values[index]? with
    | none =>
        throw { code := "LRX-COMP-003", message := "component value table changed during validation" }
    | some value =>
        unless value.fieldIndex == index do
          throw {
            code := "LRX-COMP-004"
            message := s!"component value at position {index} uses field {value.fieldIndex}"
            spans := #[value.span]
          }
  if duplicate? (spec.values.toList.map ValueSpec.name) then
    throw { code := "LRX-COMP-005", message := "component value names must be unique" }
  let count := sourceCount spec.values.toList
  unless spec.values.toList.take count |>.all ValueSpec.isSource do
    throw { code := "LRX-COMP-007", message := "component sources must form a leading prefix" }
  unless spec.values.toList.drop count |>.all (fun value => ¬value.isSource) do
    throw { code := "LRX-COMP-007", message := "component sources must form a leading prefix" }
  pure count

private def validateEvents (spec : ComponentSpec Γ) (sourceCount : Nat)
    (split : ViewSplit Γ) : Except ComponentError Unit := do
  let names := spec.events.toList.map (·.name)
  if names.any String.isEmpty || duplicate? names then
    throw { code := "LRX-COMP-008", message := "component event names must be nonempty and unique" }
  for event in spec.events do
    for target in event.update.writeTargets do
      unless target < sourceCount do
        throw {
          code := "LRX-COMP-009"
          message := s!"event {event.name} writes non-source value {target}"
          spans := #[event.span]
        }
    for dependency in event.update.readDependencies do
      unless dependency < sourceCount do
        throw {
          code := "LRX-COMP-011"
          message := s!"event {event.name} reads derived value {dependency}; derived reads require a transaction barrier"
          spans := #[event.span]
        }
  for mounted in split.events do
    unless names.contains mounted.binding.eventName do
      throw {
        code := "LRX-COMP-010"
        message := s!"view references unknown event {mounted.binding.eventName}"
        spans := #[mounted.binding.span]
      }

mutual
private def validateView : View Γ → Except ComponentError Unit
  | .element tag attrs events children span => do
      if duplicate? (attrs.map StaticAttr.name) then
        throw { code := "LRX-DOM-001", message := "element has duplicate static attributes", spans := #[span] }
      if duplicate? (events.map fun event => event.kind.name) then
        throw { code := "LRX-DOM-002", message := "element has duplicate event bindings", spans := #[span] }
      for attr in attrs do
        if let .buttonType _ := attr then
          unless tag == .button do
            throw { code := "LRX-DOM-003", message := "button type is valid only on button elements", spans := #[span] }
      validateChildren children
  | .text _ _ => pure ()
  | .scalarText name _ span =>
      if name.isEmpty then
        throw { code := "LRX-DOM-004", message := "text sink name must not be empty", spans := #[span] }
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
    .error { code := "LRX-COMP-001", message := "component name must not be empty", spans := #[spec.span] }
  else match validateValues spec with
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
                code := error.code, message := error.message, spans := error.spans
              }
            | .ok graph => .ok ⟨spec, graph, sourceCount, split⟩

end ComponentSpec

end LeanRx
